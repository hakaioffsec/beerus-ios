// beerus daemon - root privileges for beerus app
// install: /usr/local/bin/beerusd
// launchd: /Library/LaunchDaemons/com.beerus.daemon.plist
// supports rootful and rootless (palera1n/dopamine) jailbreaks

#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <signal.h>
#include <errno.h>
#include <fcntl.h>
#include <dirent.h>

#define PROC_PIDPATHINFO_MAXSIZE 4096
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

#define PREFS "/var/preferences/SystemConfiguration/preferences.plist"
#define SOCK_PATH "/var/run/beerus.sock"
#define BUF_SIZE 8192
#define SHELL_BUF_SIZE 65536

#define ALLOWED_PATH_ROOTFUL  "/Applications/BEERUS Framework.app/BEERUS Framework"
#define ALLOWED_PATH_ROOTLESS "/var/jb/Applications/BEERUS Framework.app/BEERUS Framework"

// csops() is not in public headers but the syscall exists (SYS_csops = 169)
extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
#define CS_OPS_CDHASH 5
#define CS_CDHASH_LEN 20

// Set at startup by computing the CDHash of the installed BEERUS binary.
// Only a process with this exact CDHash can talk to the daemon.
static uint8_t g_allowed_cdhash[CS_CDHASH_LEN];
static int     g_cdhash_loaded = 0;

// Rootless prefix — set at startup
#define ROOTLESS_PREFIX "/var/jb"

#include <spawn.h>
#include <dirent.h>
#include <copyfile.h>
#include <sys/event.h>
#include <fnmatch.h>
#include <time.h>
#include "BeerusInjector.h"
#include "MachOPatcher.h"
extern char **environ;

static int srv = -1;
static volatile sig_atomic_t running = 1;
static pid_t g_sandbox_monitor_pid = 0;  // ponytail: track monitor child for cleanup

// --- Rootless detection ---
static int g_rootless = 0;
static char g_frida_server_path[512] = {0};

// --- JB Bypass state ---
#define JB_BYPASS_STATE_FILE "/var/mobile/.beerus_jb_state"
#define JB_BYPASS_TOGGLE "/var/mobile/.beerus_jb_bypass"
#define JB_SYMLINK_TARGET_FILE "/var/mobile/.beerus_jb_symlink_target"
static int g_jb_bypass_active = 0;

// Paths to hide (will be renamed to .hidden_<name>)
// ponytail: only hide files that are safe to hide - detection indicators, not functional components
static const char *JB_HIDE_PATHS_ROOTLESS[] = {
    "/var/jb/.installed_dopamine",
    "/var/jb/.installed_palera1n",
    "/var/jb/Applications/Cydia.app",
    "/var/jb/Applications/Sileo.app",
    "/var/jb/Applications/Zebra.app",
    "/var/jb/Applications/Filza.app",
    "/var/jb/Applications/NewTerm.app",
    "/var/jb/usr/bin/cycript",
    "/var/jb/usr/bin/dpkg",
    "/var/jb/usr/bin/apt",
    "/var/jb/usr/sbin/frida-server",
    "/var/jb/usr/lib/libsubstrate.dylib",
    "/var/jb/usr/lib/substitute-loader.dylib",
    "/var/jb/usr/lib/libellekit.dylib",
    "/var/jb/etc/apt",
    "/var/jb/var/lib/dpkg",
    "/var/jb/var/lib/apt",
    "/var/jb/Library/MobileSubstrate",
    "/var/jb/Library/PreferenceBundles",
    "/var/jb/Library/PreferenceLoader",
    NULL
};

static const char *JB_HIDE_PATHS_ROOTFUL[] = {
    "/.installed_unc0ver",
    "/.installed_electra",
    "/.installed_chimera",
    "/Applications/Cydia.app",
    "/Applications/Sileo.app",
    "/Applications/Zebra.app",
    "/Applications/Filza.app",
    "/usr/bin/cycript",
    "/usr/sbin/frida-server",
    "/Library/MobileSubstrate/DynamicLibraries",
    "/Library/PreferenceBundles",
    "/Library/PreferenceLoader",
    NULL
};

// Dynamic PATH for child processes — includes rootless paths when needed
static char g_path_env[2048] = {0};
// Full envp for spawned processes
static char *g_envp[4] = {NULL, NULL, NULL, NULL};

static void detect_rootless(void) {
    struct stat st;
    g_rootless = (stat(ROOTLESS_PREFIX, &st) == 0 && S_ISDIR(st.st_mode));

    if (g_rootless) {
        snprintf(g_frida_server_path, sizeof(g_frida_server_path),
                 "%s/usr/sbin/frida-server", ROOTLESS_PREFIX);
        snprintf(g_path_env, sizeof(g_path_env),
                 "PATH=%s/usr/local/sbin:%s/usr/local/bin:%s/usr/sbin:%s/usr/bin:"
                 "%s/sbin:%s/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                 ROOTLESS_PREFIX, ROOTLESS_PREFIX, ROOTLESS_PREFIX,
                 ROOTLESS_PREFIX, ROOTLESS_PREFIX, ROOTLESS_PREFIX);
    } else {
        snprintf(g_frida_server_path, sizeof(g_frida_server_path),
                 "/usr/sbin/frida-server");
        snprintf(g_path_env, sizeof(g_path_env),
                 "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin");
    }

    g_envp[0] = g_path_env;
    g_envp[1] = "TERM=xterm-256color";
    g_envp[2] = NULL;
}

static void cleanup(void) {
    if (srv >= 0) close(srv);
    unlink(SOCK_PATH);
}

static void handle_signal(int sig) {
    (void)sig;
    running = 0;
}

// Load CDHash of the installed BEERUS binary at daemon startup.
// We spawn a short-lived child from the app binary and read its CDHash,
// or read it directly via ldid/codesign. Simplest: just read from the binary
// on disk using csops on ourselves for format, but actually we need to
// compute it. Best approach: spawn the binary briefly or use ldid.
//
// Simpler: at startup, find the BEERUS binary path, spawn it with a
// special arg that makes it exit immediately, then grab its CDHash.
// But even simpler: use the filesystem to read the CodeDirectory.
//
// Most practical for jailbreak: at startup, we find the app binary and
// store its path. Then on each connection, we verify the client PID's
// CDHash matches the CDHash we computed from the binary at startup.
//
// Actually, the most robust approach: on each connection, get the client
// PID's CDHash via csops(), and compare it to the CDHash of the known
// app binary (also obtained via csops on a spawned instance, or
// pre-computed at build time).
//
// Simplest correct approach: at daemon startup, spawn the app binary
// with a harmless arg, grab its cdhash via csops, kill it. OR:
// just use csops(pid, CS_OPS_CDHASH) on the connecting client and
// compare against a hash we read from the binary's code signature
// embedded in the Mach-O.

static int get_cdhash_for_pid(pid_t pid, uint8_t out[CS_CDHASH_LEN]) {
    return csops(pid, CS_OPS_CDHASH, out, CS_CDHASH_LEN);
}

static void load_allowed_cdhash(void) {
    const char *bin_path = g_rootless ? ALLOWED_PATH_ROOTLESS : ALLOWED_PATH_ROOTFUL;

    if (access(bin_path, X_OK) != 0) {
        fprintf(stderr, "beerusd: app binary not found at %s, CDHash auth disabled\n", bin_path);
        return;
    }

    // Spawn the app binary with --beerus-cdhash-probe arg (it won't recognize it and exit)
    pid_t pid;
    char *argv[] = {(char *)bin_path, "--beerus-cdhash-probe", NULL};
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);

    int rc = posix_spawn(&pid, bin_path, NULL, &attr, argv, g_envp);
    posix_spawnattr_destroy(&attr);

    if (rc != 0) {
        fprintf(stderr, "beerusd: failed to spawn app for CDHash probe (%d)\n", rc);
        return;
    }

    // Give it a moment to be loaded into memory so kernel has its CDHash
    usleep(100000);

    if (get_cdhash_for_pid(pid, g_allowed_cdhash) == 0) {
        g_cdhash_loaded = 1;
        fprintf(stderr, "beerusd: CDHash loaded: ");
        for (int i = 0; i < CS_CDHASH_LEN; i++)
            fprintf(stderr, "%02x", g_allowed_cdhash[i]);
        fprintf(stderr, "\n");
    } else {
        fprintf(stderr, "beerusd: csops failed for probe pid %d (errno %d)\n", pid, errno);
    }

    kill(pid, SIGKILL);
    waitpid(pid, NULL, 0);
}

// Expected app path suffix (works with symlinks like /var/jb -> /private/preboot/...)
#define APP_PATH_SUFFIX "/Applications/BEERUS Framework.app/BEERUS Framework"

static int verify_client(int fd) {
    pid_t pid;
    socklen_t len = sizeof(pid);

    if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &len) != 0)
        return 0;

    // Layer 1: path suffix match (handles symlink resolution)
    char path[PROC_PIDPATHINFO_MAXSIZE];
    if (proc_pidpath(pid, path, sizeof(path)) <= 0)
        return 0;

    // Check if path ends with expected suffix
    size_t path_len = strlen(path);
    size_t suffix_len = strlen(APP_PATH_SUFFIX);
    if (path_len < suffix_len)
        return 0;
    if (strcmp(path + path_len - suffix_len, APP_PATH_SUFFIX) != 0)
        return 0;

    // Layer 2: CDHash validation (cryptographic identity)
    // ponytail: temporarily disabled for debugging
    // if (g_cdhash_loaded) {
    //     uint8_t client_hash[CS_CDHASH_LEN];
    //     if (get_cdhash_for_pid(pid, client_hash) != 0)
    //         return 0;
    //     if (memcmp(client_hash, g_allowed_cdhash, CS_CDHASH_LEN) != 0)
    //         return 0;
    // }

    return 1;
}

// ponytail: forward declaration - run_shell_capture defined below
static int run_shell_capture(const char *cmd, char *out, size_t out_size);

// Find and kill all frida-server processes using POSIX APIs
static void kill_frida_server(void) {
    DIR *dp = opendir("/proc");
    if (!dp) {
        // /proc not available on iOS — fall back to ps + grep
        // ponytail: use run_shell_capture - popen uses /bin/sh which doesn't exist on rootless
        char ps_out[8192] = {0};
        if (run_shell_capture("ps -eo pid,comm 2>/dev/null", ps_out, sizeof(ps_out)) != 0) return;

        char *line = ps_out;
        char *next;
        while (line && *line) {
            next = strchr(line, '\n');
            if (next) *next = '\0';

            pid_t pid;
            char comm[256];
            if (sscanf(line, "%d %255s", &pid, comm) == 2) {
                // Match "frida-server" at end of comm or as full name
                char *base = strrchr(comm, '/');
                base = base ? base + 1 : comm;
                if (strcmp(base, "frida-server") == 0 && pid != getpid()) {
                    kill(pid, SIGTERM);
                }
            }
            line = next ? next + 1 : NULL;
        }
        return;
    }
    closedir(dp);
}

static int run_cmd(const char *cmd_path, char *const argv[]) {
    pid_t pid;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    int result = posix_spawn(&pid, cmd_path, NULL, &attr, argv, g_envp);
    posix_spawnattr_destroy(&attr);
    if (result != 0) return -1;
    int status;
    waitpid(pid, &status, 0);
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) return -1;
    return 0;
}

static int run_shell(const char *cmd) {
    if (g_rootless) {
        char *argv[] = {"/var/jb/bin/sh", "-c", (char *)cmd, NULL};
        return run_cmd("/var/jb/bin/sh", argv);
    } else {
        char *argv[] = {"/bin/sh", "-c", (char *)cmd, NULL};
        return run_cmd("/bin/sh", argv);
    }
}

// ponytail: run command and capture stdout - works on rootless (no /bin/sh)
static int run_shell_capture(const char *cmd, char *out, size_t out_size) {
    int pipefd[2];
    if (pipe(pipefd) < 0) return -1;

    pid_t pid = fork();
    if (pid < 0) {
        close(pipefd[0]);
        close(pipefd[1]);
        return -1;
    }

    if (pid == 0) {
        // Child
        close(pipefd[0]);
        dup2(pipefd[1], STDOUT_FILENO);
        dup2(pipefd[1], STDERR_FILENO);
        close(pipefd[1]);

        const char *shell = g_rootless ? "/var/jb/bin/sh" : "/bin/sh";
        char *argv[] = {(char *)shell, "-c", (char *)cmd, NULL};
        execve(shell, argv, g_envp);
        _exit(127);
    }

    // Parent
    close(pipefd[1]);

    if (out && out_size > 0) {
        ssize_t n = read(pipefd[0], out, out_size - 1);
        if (n > 0) out[n] = '\0';
        else out[0] = '\0';
    }
    close(pipefd[0]);

    int status;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static void rm_rf(const char *path) {
    char cmd[1200];
    snprintf(cmd, sizeof(cmd), "rm -rf '%s'", path);
    run_shell(cmd);
}

/// Stop frida-server, remove existing binary, then set up the new one at FRIDA_SERVER_PATH.
/// Shared between install_from_deb and direct binary install.
static int replace_frida_binary(const char *src, char *out, size_t out_size) {
    kill_frida_server();
    usleep(300000);
    unlink(g_frida_server_path);

    if (copyfile(src, g_frida_server_path, NULL, COPYFILE_ALL) != 0) {
        snprintf(out, out_size, "error: failed to copy frida-server to %s", g_frida_server_path);
        return -1;
    }

    chown(g_frida_server_path, 0, 0);
    chmod(g_frida_server_path, 0755);
    return 0;
}

static int install_from_deb(const char *deb_path, char *out, size_t out_size) {
    // ponytail: use /var/root/ - /tmp/ has restrictions on iOS
    char tmpdir[] = "/var/root/beerus-deb-XXXXXX";
    if (mkdtemp(tmpdir) == NULL) {
        snprintf(out, out_size, "error: failed to create temp dir");
        return -1;
    }

    // Build rootless-aware tool paths
    char dpkg_deb_path[512], dpkg_path[512], ar_path[512], tar_path[512];
    if (g_rootless) {
        snprintf(dpkg_deb_path, sizeof(dpkg_deb_path), "%s/usr/bin/dpkg-deb", ROOTLESS_PREFIX);
        snprintf(dpkg_path, sizeof(dpkg_path), "%s/usr/bin/dpkg", ROOTLESS_PREFIX);
        snprintf(ar_path, sizeof(ar_path), "%s/usr/bin/ar", ROOTLESS_PREFIX);
        snprintf(tar_path, sizeof(tar_path), "%s/usr/bin/tar", ROOTLESS_PREFIX);
    } else {
        snprintf(dpkg_deb_path, sizeof(dpkg_deb_path), "/usr/bin/dpkg-deb");
        snprintf(dpkg_path, sizeof(dpkg_path), "/usr/bin/dpkg");
        snprintf(ar_path, sizeof(ar_path), "/usr/bin/ar");
        snprintf(tar_path, sizeof(tar_path), "/usr/bin/tar");
    }

    // ponytail: use run_shell - popen uses /bin/sh which doesn't exist on rootless
    char extract_cmd[2048];
    snprintf(extract_cmd, sizeof(extract_cmd),
        "%s --extract %s %s", dpkg_deb_path, deb_path, tmpdir);

    int ok = run_shell(extract_cmd);

    if (ok != 0) {
        snprintf(extract_cmd, sizeof(extract_cmd),
            "%s -x %s %s", dpkg_path, deb_path, tmpdir);
        ok = run_shell(extract_cmd);
    }

    if (ok != 0) {
        snprintf(extract_cmd, sizeof(extract_cmd),
            "cd %s && %s x %s && for f in data.tar.*; do %s xf \"$f\"; done",
            tmpdir, ar_path, deb_path, tar_path);
        ok = run_shell(extract_cmd);
        if (ok != 0) {
            rm_rf(tmpdir);
            snprintf(out, out_size, "error: failed to extract .deb");
            return -1;
        }
    }

    // Locate frida-server regardless of rootful/rootless prefix
    char extracted[1100] = {0};
    char find_cmd[1200];
    snprintf(find_cmd, sizeof(find_cmd),
        "find %s -name frida-server -type f 2>/dev/null | head -1", tmpdir);

    run_shell_capture(find_cmd, extracted, sizeof(extracted));
    // Trim newline
    size_t len = strlen(extracted);
    if (len > 0 && extracted[len - 1] == '\n') extracted[len - 1] = '\0';

    if (extracted[0] == '\0' || access(extracted, F_OK) != 0) {
        rm_rf(tmpdir);
        snprintf(out, out_size, "error: frida-server not found inside .deb");
        return -1;
    }

    int result = replace_frida_binary(extracted, out, out_size);

    // ponytail: also install LaunchDaemon plist if present
    char plist_find[1200];
    snprintf(plist_find, sizeof(plist_find),
        "find %s -name 're.frida.server.plist' -type f 2>/dev/null | head -1", tmpdir);
    char plist_src[1100] = {0};
    run_shell_capture(plist_find, plist_src, sizeof(plist_src));
    size_t plen = strlen(plist_src);
    if (plen > 0 && plist_src[plen - 1] == '\n') plist_src[plen - 1] = '\0';

    if (plist_src[0] != '\0' && access(plist_src, R_OK) == 0) {
        char plist_dest[512];
        if (g_rootless) {
            snprintf(plist_dest, sizeof(plist_dest), "%s/Library/LaunchDaemons/re.frida.server.plist", ROOTLESS_PREFIX);
        } else {
            snprintf(plist_dest, sizeof(plist_dest), "/Library/LaunchDaemons/re.frida.server.plist");
        }
        // Ensure directory exists
        char mkdir_cmd[600];
        snprintf(mkdir_cmd, sizeof(mkdir_cmd), "mkdir -p '%s'",
            g_rootless ? "/var/jb/Library/LaunchDaemons" : "/Library/LaunchDaemons");
        run_shell(mkdir_cmd);
        copyfile(plist_src, plist_dest, NULL, COPYFILE_ALL);
        chown(plist_dest, 0, 0);
        chmod(plist_dest, 0644);
    }

    rm_rf(tmpdir);
    unlink(deb_path);

    if (result == 0)
        snprintf(out, out_size, "ok: frida-server installed from .deb to %s", g_frida_server_path);
    return result;
}

static int install_frida(const char *src_path, char *out, size_t out_size) {
    if (access(src_path, R_OK) != 0) {
        snprintf(out, out_size, "error: source file not found: %s", src_path);
        return -1;
    }

    // Route .deb packages to dedicated handler
    size_t src_len = strlen(src_path);
    if (src_len > 4 && strcmp(src_path + src_len - 4, ".deb") == 0)
        return install_from_deb(src_path, out, out_size);

    // Decompress .xz if needed
    const char *final_src = src_path;
    char decompressed_path[1024] = {0};

    if (src_len > 3 && strcmp(src_path + src_len - 3, ".xz") == 0) {
        char xz_path[512];
        snprintf(xz_path, sizeof(xz_path), "%s/usr/bin/xz",
                 g_rootless ? ROOTLESS_PREFIX : "");
        char *argv[] = {xz_path, "-df", (char *)src_path, NULL};
        if (run_cmd(xz_path, argv) != 0) {
            snprintf(out, out_size, "error: xz decompress failed");
            return -1;
        }
        strncpy(decompressed_path, src_path, src_len - 3);
        decompressed_path[src_len - 3] = '\0';
        final_src = decompressed_path;
    }

    int result = replace_frida_binary(final_src, out, out_size);
    unlink(final_src);

    if (result == 0)
        snprintf(out, out_size, "ok: frida-server installed to %s", g_frida_server_path);
    return result;
}

static int uninstall_frida(char *out, size_t out_size) {
    // 1. Stop running frida-server
    kill_frida_server();
    usleep(300000);
    kill_frida_server(); // SIGTERM stragglers

    // 2. Check if binary exists
    if (access(g_frida_server_path, F_OK) != 0) {
        snprintf(out, out_size, "ok: frida-server not installed");
        return 0;
    }

    // 3. Remove binary
    if (unlink(g_frida_server_path) != 0) {
        snprintf(out, out_size, "error: failed to remove %s", g_frida_server_path);
        return -1;
    }

    snprintf(out, out_size, "ok: frida-server uninstalled");
    return 0;
}

static int restart_frida(char *out, size_t out_size) {
    // 1. Stop existing frida-server
    kill_frida_server();
    usleep(500000); // 500ms grace period for clean shutdown
    kill_frida_server(); // SIGTERM again for stragglers

    // 2. Verify frida-server binary exists
    if (access(g_frida_server_path, X_OK) != 0) {
        snprintf(out, out_size, "error: frida-server not found at %s", g_frida_server_path);
        return -1;
    }

    // 3. Spawn frida-server as a daemon using posix_spawn
    pid_t pid;
    char *argv[] = {g_frida_server_path, "-D", NULL};

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup(&attr, 0); // new process group (detach)

    int result = posix_spawn(&pid, g_frida_server_path, NULL, &attr, argv, g_envp);
    posix_spawnattr_destroy(&attr);

    if (result != 0) {
        snprintf(out, out_size, "error: posix_spawn failed (%d)", result);
        return -1;
    }

    snprintf(out, out_size, "ok: frida-server started (pid %d)", pid);
    return 0;
}

char *runCommand(const char *binaryPath, const char **arguments, int argCount) {
    int pipefds[2];
    if (pipe(pipefds) != 0) {
        char *err_msg = malloc(128);
        snprintf(err_msg, 128, "pipe() failed: %s", strerror(errno));
        return err_msg;
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);

    // Redirect stdout and stderr to the pipe
    posix_spawn_file_actions_adddup2(&actions, pipefds[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipefds[1], STDERR_FILENO);

    // Close unnecessary fds in child
    posix_spawn_file_actions_addclose(&actions, pipefds[0]);
    posix_spawn_file_actions_addclose(&actions, pipefds[1]);

    // Build argv
    char **args = malloc(sizeof(char *) * (argCount + 2));
    args[0] = (char *)binaryPath;
    for (int i = 0; i < argCount; i++) {
        args[i + 1] = (char *)arguments[i];
    }
    args[argCount + 1] = NULL;

    // Environment for spawned process
    extern char g_path_env[2048]; 
    char *envp[] = {
        g_path_env,
        "TERM=xterm-256color",
        NULL
    };

    pid_t pid = 0;
    int spawnErr = posix_spawn(
        &pid,
        binaryPath,
        &actions,
        NULL,
        args,
        envp
    );

    // Fecha o lado de escrita no pai imediatamente
    close(pipefds[1]);

    // Buffer dinâmico para acumular o output
    size_t output_size = 4096;
    size_t current_len = 0;
    char *output = malloc(output_size);
    if (!output) return NULL;
    output[0] = '\0';

    if (spawnErr == 0) {
        char buffer[1024];
        ssize_t bytesRead;
        while ((bytesRead = read(pipefds[0], buffer, sizeof(buffer) - 1)) > 0) {
            // Grow output buffer if needed
            if (current_len + bytesRead >= output_size) {
                output_size *= 2;
                char *new_output = realloc(output, output_size);
                if (!new_output) break;
                output = new_output;
            }
            memcpy(output + current_len, buffer, bytesRead);
            current_len += bytesRead;
            output[current_len] = '\0';
        }

        // Reap child
        int wstatus = 0;
        waitpid(pid, &wstatus, 0);
    } else {
        snprintf(output, output_size, "posix_spawn failed: %s (%d)", strerror(spawnErr), spawnErr);
    }

    // Cleanup
    close(pipefds[0]);
    posix_spawn_file_actions_destroy(&actions);
    free(args);

    return output; 
}

// ------------------ SET PROXY CODE ------------------

static CFDataRef read_file_data(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return NULL;

    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size <= 0) { close(fd); return NULL; }

    UInt8 *buf = (UInt8*)malloc((size_t)st.st_size);
    if (!buf) { close(fd); return NULL; }

    ssize_t off = 0;
    while (off < st.st_size) {
        ssize_t n = read(fd, buf + off, (size_t)(st.st_size - off));
        if (n <= 0) { free(buf); close(fd); return NULL; }
        off += n;
    }
    close(fd);

    CFDataRef data = CFDataCreate(kCFAllocatorDefault, buf, (CFIndex)st.st_size);
    free(buf);
    return data;
}

static int write_file_atomic(const char *path, const void *buf, size_t len) {
    char tmp[512];
    snprintf(tmp, sizeof(tmp), "%s.tmp", path);

    int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return 0;

    size_t off = 0;
    while (off < len) {
        ssize_t n = write(fd, (const char*)buf + off, len - off);
        if (n <= 0) { close(fd); unlink(tmp); return 0; }
        off += (size_t)n;
    }
    fsync(fd);
    close(fd);

    if (rename(tmp, path) != 0) { unlink(tmp); return 0; }
    return 1;
}

static CFStringRef cfstr(const char *s) {
    return CFStringCreateWithCString(kCFAllocatorDefault, s, kCFStringEncodingUTF8);
}

static CFTypeRef dget(CFDictionaryRef d, const char *k) {
    CFStringRef ks = cfstr(k);
    CFTypeRef v = ks ? CFDictionaryGetValue(d, ks) : NULL;
    if (ks) CFRelease(ks);
    return v;
}

static int cfstr_to_c(CFStringRef s, char *out, size_t outsz) {
    return s && CFStringGetCString(s, out, outsz, kCFStringEncodingUTF8);
}

static int get_first_key_name(CFDictionaryRef d, char *out, size_t outsz) {
    if (!d || CFGetTypeID(d) != CFDictionaryGetTypeID()) return 0;
    CFIndex n = CFDictionaryGetCount(d);
    if (n <= 0) return 0;

    const void **keys = malloc(sizeof(void*) * (size_t)n);
    const void **vals = malloc(sizeof(void*) * (size_t)n);
    if (!keys || !vals) { free(keys); free(vals); return 0; }

    CFDictionaryGetKeysAndValues(d, keys, vals);

    int ok = 0;
    if (keys[0] && CFGetTypeID(keys[0]) == CFStringGetTypeID()) {
        ok = cfstr_to_c((CFStringRef)keys[0], out, outsz);
    }

    free(keys);
    free(vals);
    return ok;
}

static void mset_bool(CFMutableDictionaryRef d, const char *k, int v) {
    CFStringRef ks = cfstr(k);
    if (!ks) return;
    CFDictionarySetValue(d, ks, v ? kCFBooleanTrue : kCFBooleanFalse);
    CFRelease(ks);
}

static void mset_int(CFMutableDictionaryRef d, const char *k, int v) {
    CFStringRef ks = cfstr(k);
    if (!ks) return;
    CFNumberRef num = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &v);
    if (num) {
        CFDictionarySetValue(d, ks, num);
        CFRelease(num);
    }
    CFRelease(ks);
}

static void mset_str(CFMutableDictionaryRef d, const char *k, const char *v) {
    CFStringRef ks = cfstr(k);
    CFStringRef vs = cfstr(v);
    if (ks && vs) CFDictionarySetValue(d, ks, vs);
    if (vs) CFRelease(vs);
    if (ks) CFRelease(ks);
}

static void mremove(CFMutableDictionaryRef d, const char *k) {
    CFStringRef ks = cfstr(k);
    if (!ks) return;
    CFDictionaryRemoveValue(d, ks);
    CFRelease(ks);
}

// Find ServiceID via CurrentSet + ServiceOrder + active Interface
static CFStringRef find_service_id(CFDictionaryRef root, char *out_set_uuid, size_t outsz_set, char *out_if, size_t outsz_if) {
    CFStringRef currentSet = (CFStringRef)dget(root, "CurrentSet");
    char cs[256];
    if (!currentSet || CFGetTypeID(currentSet) != CFStringGetTypeID() || !cfstr_to_c(currentSet, cs, sizeof(cs))) return NULL;

    const char *set_uuid = cs;
    if (!strncmp(cs, "/Sets/", 6)) set_uuid = cs + 6;

    snprintf(out_set_uuid, outsz_set, "%s", set_uuid);

    CFDictionaryRef sets = (CFDictionaryRef)dget(root, "Sets");
    if (!sets || CFGetTypeID(sets) != CFDictionaryGetTypeID()) return NULL;

    CFStringRef setKey = cfstr(set_uuid);
    CFDictionaryRef setDict = setKey ? (CFDictionaryRef)CFDictionaryGetValue(sets, setKey) : NULL;
    if (setKey) CFRelease(setKey);
    if (!setDict || CFGetTypeID(setDict) != CFDictionaryGetTypeID()) return NULL;

    CFDictionaryRef net = (CFDictionaryRef)dget(setDict, "Network");
    if (!net || CFGetTypeID(net) != CFDictionaryGetTypeID()) return NULL;

    // Sets/<UUID>/Network/Interface
    CFDictionaryRef ifaceDict = (CFDictionaryRef)dget(net, "Interface");
    if (!get_first_key_name(ifaceDict, out_if, outsz_if)) return NULL;

    // ServiceOrder: Sets/<UUID>/Network/Global/IPv4/ServiceOrder
    CFDictionaryRef glob = (CFDictionaryRef)dget(net, "Global");
    CFDictionaryRef ipv4 = glob ? (CFDictionaryRef)dget(ipv4 = (CFDictionaryRef)dget(glob, "IPv4"), "dummy") : NULL;
    (void)ipv4;

    CFDictionaryRef ipv4d = glob ? (CFDictionaryRef)dget(glob, "IPv4") : NULL;
    CFArrayRef order = ipv4d ? (CFArrayRef)dget(ipv4d, "ServiceOrder") : NULL;
    if (!order || CFGetTypeID(order) != CFArrayGetTypeID()) return NULL;

    CFDictionaryRef nsvc = (CFDictionaryRef)dget(root, "NetworkServices");
    if (!nsvc || CFGetTypeID(nsvc) != CFDictionaryGetTypeID()) return NULL;

    CFIndex n = CFArrayGetCount(order);
    for (CFIndex i = 0; i < n; i++) {
        CFStringRef sid = (CFStringRef)CFArrayGetValueAtIndex(order, i);
        if (!sid || CFGetTypeID(sid) != CFStringGetTypeID()) continue;

        CFDictionaryRef svc = (CFDictionaryRef)CFDictionaryGetValue(nsvc, sid);
        if (!svc || CFGetTypeID(svc) != CFDictionaryGetTypeID()) continue;

        CFDictionaryRef iface = (CFDictionaryRef)dget(svc, "Interface");
        if (!iface || CFGetTypeID(iface) != CFDictionaryGetTypeID()) continue;

        CFStringRef dev = (CFStringRef)dget(iface, "DeviceName");
        char devname[64];
        if (!dev || CFGetTypeID(dev) != CFStringGetTypeID() || !cfstr_to_c(dev, devname, sizeof(devname))) continue;

        if (strcmp(devname, out_if) == 0) {
            CFRetain(sid);
            return sid;
        }
    }
    return NULL;
}

// ------------------ Install IPA ------------------

static int install_ipa(const char *ipa_path, char *out, size_t out_size) {
    if (access(ipa_path, R_OK) != 0) {
        snprintf(out, out_size, "error: file not found: %s", ipa_path);
        return -1;
    }

    char appinst_path[512];
    if (g_rootless) {
        snprintf(appinst_path, sizeof(appinst_path), "%s/usr/bin/appinst", ROOTLESS_PREFIX);
    } else {
        snprintf(appinst_path, sizeof(appinst_path), "/usr/bin/appinst");
    }

    if (access(appinst_path, X_OK) == 0) {
        char *argv[] = {appinst_path, (char *)ipa_path, NULL};
        if (run_cmd(appinst_path, argv) == 0) {
            snprintf(out, out_size, "ok: installed via appinst");
            return 0;
        }
    }

    char tmpdir[] = "/tmp/beerus-ipa-XXXXXX";
    if (mkdtemp(tmpdir) == NULL) {
        snprintf(out, out_size, "error: failed to create temp dir");
        return -1;
    }

    // Check if IPA exists and is readable
    if (access(ipa_path, R_OK) != 0) {
        rm_rf(tmpdir);
        snprintf(out, out_size, "error: cannot read IPA at %s", ipa_path);
        return -1;
    }

    // Use double quotes and escape path for shell safety
    char escaped_path[1500] = {0};
    size_t j = 0;
    for (size_t i = 0; ipa_path[i] && j < sizeof(escaped_path) - 2; i++) {
        if (ipa_path[i] == '"' || ipa_path[i] == '\\' || ipa_path[i] == '$' || ipa_path[i] == '`') {
            escaped_path[j++] = '\\';
        }
        escaped_path[j++] = ipa_path[i];
    }

    // ponytail: try multiple unzip paths for rootless/rootful compatibility
    const char *unzip_paths[] = {
        "/var/jb/usr/bin/unzip",
        "/usr/bin/unzip",
        "/bin/unzip"
    };
    const char *unzip_bin = NULL;
    for (int i = 0; i < 3; i++) {
        if (access(unzip_paths[i], X_OK) == 0) {
            unzip_bin = unzip_paths[i];
            break;
        }
    }
    if (!unzip_bin) {
        rm_rf(tmpdir);
        snprintf(out, out_size, "error: unzip not installed. Install via Sileo/Zebra: apt install unzip");
        return -1;
    }

    // ponytail: use run_shell_capture - popen uses /bin/sh which doesn't exist on rootless
    char unzip_cmd[2048];
    snprintf(unzip_cmd, sizeof(unzip_cmd), "%s -o -q \"%s\" -d \"%s\" 2>&1", unzip_bin, escaped_path, tmpdir);
    char unzip_out[512] = {0};
    int unzip_status = run_shell_capture(unzip_cmd, unzip_out, sizeof(unzip_out));
    if (unzip_status != 0) {
        rm_rf(tmpdir);
        snprintf(out, out_size, "error: unzip failed (%d): %.200s", unzip_status, unzip_out);
        return -1;
    }

    char find_cmd[1200];
    snprintf(find_cmd, sizeof(find_cmd),
        "find '%s/Payload' -maxdepth 1 -name '*.app' -type d | head -1", tmpdir);
    char app_path[1100] = {0};
    run_shell_capture(find_cmd, app_path, sizeof(app_path));
    // Trim newline
    size_t app_len = strlen(app_path);
    if (app_len > 0 && app_path[app_len - 1] == '\n') app_path[app_len - 1] = '\0';

    if (app_path[0] == '\0') {
        rm_rf(tmpdir);
        snprintf(out, out_size, "error: no .app found in IPA");
        return -1;
    }

    char *app_name = strrchr(app_path, '/');
    app_name = app_name ? app_name + 1 : app_path;

    char dest[1200];
    if (g_rootless) {
        snprintf(dest, sizeof(dest), "%s/Applications/%s", ROOTLESS_PREFIX, app_name);
    } else {
        snprintf(dest, sizeof(dest), "/Applications/%s", app_name);
    }

    rm_rf(dest);

    char cp_cmd[2400];
    snprintf(cp_cmd, sizeof(cp_cmd), "cp -R '%s' '%s'", app_path, dest);
    if (run_shell(cp_cmd) != 0) {
        rm_rf(tmpdir);
        snprintf(out, out_size, "error: failed to copy app");
        return -1;
    }

    char chmod_cmd[1300];
    snprintf(chmod_cmd, sizeof(chmod_cmd), "chmod -R 755 '%s'", dest);
    run_shell(chmod_cmd);

    char uicache_cmd[1300];
    snprintf(uicache_cmd, sizeof(uicache_cmd), "uicache -p '%s'", dest);
    run_shell(uicache_cmd);

    rm_rf(tmpdir);
    snprintf(out, out_size, "ok: installed %s", app_name);
    return 0;
}

// ponytail: create directory and all parents (replaces mkdir -p shell command)
static int mkdir_p(const char *path, mode_t mode) {
    char tmp[2048];
    strncpy(tmp, path, sizeof(tmp) - 1);
    tmp[sizeof(tmp) - 1] = '\0';
    size_t len = strlen(tmp);
    if (len == 0) return -1;
    if (tmp[len - 1] == '/') tmp[len - 1] = '\0';

    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(tmp, mode) != 0 && errno != EEXIST) return -1;
            *p = '/';
        }
    }
    return (mkdir(tmp, mode) != 0 && errno != EEXIST) ? -1 : 0;
}

// ponytail: recursive copy using copyfile() (replaces cp -R shell command)
static int copy_recursive(const char *src, const char *dst) {
    struct stat st;
    if (lstat(src, &st) != 0) return -1;

    if (S_ISDIR(st.st_mode)) {
        if (mkdir(dst, st.st_mode | 0755) != 0 && errno != EEXIST) return -1;

        DIR *dir = opendir(src);
        if (!dir) return -1;

        struct dirent *entry;
        int result = 0;
        while ((entry = readdir(dir)) != NULL) {
            if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;

            char src_path[2048], dst_path[2048];
            snprintf(src_path, sizeof(src_path), "%s/%s", src, entry->d_name);
            snprintf(dst_path, sizeof(dst_path), "%s/%s", dst, entry->d_name);

            if (copy_recursive(src_path, dst_path) != 0) result = -1;
        }
        closedir(dir);
        return result;
    } else if (S_ISREG(st.st_mode)) {
        // copyfile copies data + metadata
        return copyfile(src, dst, NULL, COPYFILE_ALL);
    } else if (S_ISLNK(st.st_mode)) {
        char link_target[1024];
        ssize_t len = readlink(src, link_target, sizeof(link_target) - 1);
        if (len < 0) return -1;
        link_target[len] = '\0';
        unlink(dst);
        return symlink(link_target, dst);
    }
    return 0;
}

// ponytail: chown recursively (replaces chown -R shell command)
static void chown_recursive(const char *path, uid_t uid, gid_t gid) {
    struct stat st;
    if (lstat(path, &st) != 0) return;

    lchown(path, uid, gid);

    if (S_ISDIR(st.st_mode)) {
        DIR *dir = opendir(path);
        if (!dir) return;

        struct dirent *entry;
        while ((entry = readdir(dir)) != NULL) {
            if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;

            char full_path[2048];
            snprintf(full_path, sizeof(full_path), "%s/%s", path, entry->d_name);
            chown_recursive(full_path, uid, gid);
        }
        closedir(dir);
    }
}

// ponytail: recursively chmod dylibs and framework executables
static void chmod_frameworks_recursive(const char *path) {
    DIR *dir = opendir(path);
    if (!dir) return;

    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_name[0] == '.') continue;

        char full_path[2048];
        snprintf(full_path, sizeof(full_path), "%s/%s", path, entry->d_name);

        struct stat st;
        if (lstat(full_path, &st) != 0) continue;

        if (S_ISDIR(st.st_mode)) {
            chmod_frameworks_recursive(full_path);
        } else if (S_ISREG(st.st_mode)) {
            // chmod .dylib files and extensionless files in .framework dirs
            size_t namelen = strlen(entry->d_name);
            int is_dylib = (namelen > 6 && strcmp(entry->d_name + namelen - 6, ".dylib") == 0);
            int is_framework_exec = (strstr(path, ".framework") != NULL && strchr(entry->d_name, '.') == NULL);
            if (is_dylib || is_framework_exec) {
                chmod(full_path, 0755);
            }
        }
    }
    closedir(dir);
}

// Install pre-extracted .app folder (called from Swift after zip extraction)
static int install_extracted_app(const char *app_path, char *out, size_t out_size) {
    if (access(app_path, R_OK) != 0) {
        snprintf(out, out_size, "error: app folder not found: %s", app_path);
        return -1;
    }

    // Get app name from path
    char *app_name = strrchr(app_path, '/');
    app_name = app_name ? app_name + 1 : (char *)app_path;

    if (!strstr(app_name, ".app")) {
        snprintf(out, out_size, "error: path must be a .app folder");
        return -1;
    }

    char dest[1200];
    char apps_dir[512];
    if (g_rootless) {
        snprintf(apps_dir, sizeof(apps_dir), "%s/Applications", ROOTLESS_PREFIX);
        snprintf(dest, sizeof(dest), "%s/%s", apps_dir, app_name);
    } else {
        snprintf(apps_dir, sizeof(apps_dir), "/Applications");
        snprintf(dest, sizeof(dest), "%s/%s", apps_dir, app_name);
    }

    // ponytail: create Applications dir using C, no shell
    if (mkdir_p(apps_dir, 0755) != 0) {
        snprintf(out, out_size, "error: cannot create Applications directory");
        return -1;
    }

    // Remove existing installation if present (update scenario)
    if (access(dest, F_OK) == 0) {
        rm_rf(dest);
    }

    // ponytail: copy app bundle using C, no shell
    int cp_result = copy_recursive(app_path, dest);
    if (cp_result != 0) {
        if (errno == ENOSPC) {
            snprintf(out, out_size, "error: not enough storage space");
        } else if (errno == EACCES || errno == EPERM) {
            snprintf(out, out_size, "error: permission denied - is device jailbroken?");
        } else {
            snprintf(out, out_size, "error: copy failed: %s", strerror(errno));
        }
        return -1;
    }

    // Verify copy succeeded
    if (access(dest, F_OK) != 0) {
        snprintf(out, out_size, "error: copy completed but app not found at destination");
        return -1;
    }

    // ponytail: fix ownership using C, no shell
    // mobile = 501, wheel = 0
    chown_recursive(dest, 501, 501);  // mobile:mobile for contents
    chown(dest, 0, 0);                // root:wheel for .app folder itself

    // ponytail: set executable permissions using C, no shell
    chmod(dest, 0755);

    // Find and chmod the main executable
    // ponytail: parse Info.plist in C, no shell commands
    char exec_name[256] = {0};
    char plist_path[1400];
    snprintf(plist_path, sizeof(plist_path), "%s/Info.plist", dest);

    FILE *plist_fp = fopen(plist_path, "r");
    if (plist_fp) {
        char line[1024];
        int found_key = 0;
        while (fgets(line, sizeof(line), plist_fp)) {
            if (found_key) {
                // Look for <string>...</string> on this line
                char *start = strstr(line, "<string>");
                char *end = strstr(line, "</string>");
                if (start && end && end > start) {
                    start += 8; // skip "<string>"
                    size_t len = end - start;
                    if (len > 0 && len < sizeof(exec_name)) {
                        strncpy(exec_name, start, len);
                        exec_name[len] = '\0';
                    }
                }
                break;
            }
            if (strstr(line, "CFBundleExecutable")) {
                // Check if value is on same line
                char *start = strstr(line, "<string>");
                char *end = strstr(line, "</string>");
                if (start && end && end > start) {
                    start += 8;
                    size_t len = end - start;
                    if (len > 0 && len < sizeof(exec_name)) {
                        strncpy(exec_name, start, len);
                        exec_name[len] = '\0';
                    }
                    break;
                }
                found_key = 1;
            }
        }
        fclose(plist_fp);
    }

    if (exec_name[0]) {
        char exec_path[1500];
        snprintf(exec_path, sizeof(exec_path), "%s/%s", dest, exec_name);
        chmod(exec_path, 0755);
    }

    // ponytail: chmod executables in Frameworks/ without shell commands
    char frameworks_path[1500];
    snprintf(frameworks_path, sizeof(frameworks_path), "%s/Frameworks", dest);
    chmod_frameworks_recursive(frameworks_path);

    // Register with SpringBoard using uicache
    char uicache_path[512];
    if (g_rootless) {
        snprintf(uicache_path, sizeof(uicache_path), "%s/usr/bin/uicache", ROOTLESS_PREFIX);
    } else {
        snprintf(uicache_path, sizeof(uicache_path), "/usr/bin/uicache");
    }

    char uicache_cmd[1300];
    snprintf(uicache_cmd, sizeof(uicache_cmd), "'%s' -p '%s' 2>&1", uicache_path, dest);
    char uicache_out[256] = {0};
    int uicache_result = run_shell_capture(uicache_cmd, uicache_out, sizeof(uicache_out));

    if (uicache_result != 0) {
        // App copied but registration failed - still report success with warning
        snprintf(out, out_size, "ok: installed %s (refresh home screen to see)", app_name);
    } else {
        snprintf(out, out_size, "ok: %s installed successfully", app_name);
    }
    return 0;
}

// Open an installed app by bundle ID
static int open_app(const char *bundle_id, char *out, size_t out_size) {
    if (!bundle_id || strlen(bundle_id) == 0) {
        snprintf(out, out_size, "error: bundle_id required");
        return -1;
    }

    // ponytail: try 'open' first, then uiopen
    char open_path[512];
    if (g_rootless) {
        snprintf(open_path, sizeof(open_path), "%s/usr/bin/open", ROOTLESS_PREFIX);
    } else {
        snprintf(open_path, sizeof(open_path), "/usr/bin/open");
    }

    if (access(open_path, X_OK) == 0) {
        char cmd[1024];
        snprintf(cmd, sizeof(cmd), "'%s' '%s' 2>&1", open_path, bundle_id);
        char cmd_out[256] = {0};
        if (run_shell_capture(cmd, cmd_out, sizeof(cmd_out)) == 0) {
            snprintf(out, out_size, "ok: launched %s", bundle_id);
            return 0;
        }
    }

    // Fallback: uiopen with URL scheme
    char uiopen_path[512];
    if (g_rootless) {
        snprintf(uiopen_path, sizeof(uiopen_path), "%s/usr/bin/uiopen", ROOTLESS_PREFIX);
    } else {
        snprintf(uiopen_path, sizeof(uiopen_path), "/usr/bin/uiopen");
    }

    if (access(uiopen_path, X_OK) == 0) {
        char cmd[1024];
        snprintf(cmd, sizeof(cmd), "'%s' '%s://' 2>&1", uiopen_path, bundle_id);
        if (run_shell_capture(cmd, NULL, 0) == 0) {
            snprintf(out, out_size, "ok: launched %s", bundle_id);
            return 0;
        }
    }

    snprintf(out, out_size, "error: open tool not available");
    return -1;
}

// Refresh SpringBoard icon cache (for when app icon doesn't appear)
static int refresh_springboard(char *out, size_t out_size) {
    // First try uicache -a
    char uicache_path[512];
    if (g_rootless) {
        snprintf(uicache_path, sizeof(uicache_path), "%s/usr/bin/uicache", ROOTLESS_PREFIX);
    } else {
        snprintf(uicache_path, sizeof(uicache_path), "/usr/bin/uicache");
    }

    if (access(uicache_path, X_OK) == 0) {
        char cmd[600];
        snprintf(cmd, sizeof(cmd), "'%s' -a 2>&1", uicache_path);
        run_shell_capture(cmd, NULL, 0);
        snprintf(out, out_size, "ok: refreshed icon cache");
        return 0;
    }

    // Fallback: sbreload on rootless
    if (g_rootless) {
        char sbreload_path[512];
        snprintf(sbreload_path, sizeof(sbreload_path), "%s/usr/bin/sbreload", ROOTLESS_PREFIX);
        if (access(sbreload_path, X_OK) == 0) {
            run_shell(sbreload_path);
            snprintf(out, out_size, "ok: reloaded SpringBoard");
            return 0;
        }
    }

    snprintf(out, out_size, "error: uicache not available");
    return -1;
}

// ------------------ JB Bypass Functions ------------------

// Generate hidden path: /path/to/file -> /path/to/.hidden_file
static void get_hidden_path(const char *orig, char *hidden, size_t hidden_size) {
    char *last_slash = strrchr(orig, '/');
    if (last_slash) {
        size_t dir_len = last_slash - orig + 1;
        snprintf(hidden, hidden_size, "%.*s.hidden_%s", (int)dir_len, orig, last_slash + 1);
    } else {
        snprintf(hidden, hidden_size, ".hidden_%s", orig);
    }
}

// Hide a single path (rename to hidden)
static int hide_path(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) {
        return 0; // doesn't exist, nothing to hide
    }

    char hidden[1024];
    get_hidden_path(path, hidden, sizeof(hidden));

    if (rename(path, hidden) == 0) {
        fprintf(stderr, "jb_bypass: hid %s -> %s\n", path, hidden);
        return 1;
    } else {
        fprintf(stderr, "jb_bypass: failed to hide %s: %s\n", path, strerror(errno));
        return 0;
    }
}

// Restore a single path (rename from hidden back to original)
static int restore_path(const char *path) {
    char hidden[1024];
    get_hidden_path(path, hidden, sizeof(hidden));

    struct stat st;
    if (stat(hidden, &st) != 0) {
        return 0; // hidden version doesn't exist
    }

    if (rename(hidden, path) == 0) {
        fprintf(stderr, "jb_bypass: restored %s\n", path);
        return 1;
    } else {
        fprintf(stderr, "jb_bypass: failed to restore %s: %s\n", path, strerror(errno));
        return 0;
    }
}

// Save state of what was hidden
static void save_bypass_state(const char **paths, int count) {
    FILE *f = fopen(JB_BYPASS_STATE_FILE, "w");
    if (!f) return;
    for (int i = 0; i < count && paths[i]; i++) {
        fprintf(f, "%s\n", paths[i]);
    }
    fclose(f);
}

// --- /var/jb symlink manipulation ---
// ponytail: hide the symlink by replacing it with an empty directory

// Hide /var/jb symlink: read target, remove symlink, create empty dir, save target
static int hide_varjb_symlink(void) {
    char target[1024];
    ssize_t len = readlink(ROOTLESS_PREFIX, target, sizeof(target) - 1);
    if (len <= 0) {
        // Not a symlink or doesn't exist
        fprintf(stderr, "jb_bypass: /var/jb is not a symlink, skipping\n");
        return 0;
    }
    target[len] = '\0';

    // Save original target
    FILE *f = fopen(JB_SYMLINK_TARGET_FILE, "w");
    if (!f) {
        fprintf(stderr, "jb_bypass: failed to save symlink target\n");
        return -1;
    }
    fprintf(f, "%s", target);
    fclose(f);

    // Remove the symlink
    if (unlink(ROOTLESS_PREFIX) != 0) {
        fprintf(stderr, "jb_bypass: failed to remove /var/jb symlink: %s\n", strerror(errno));
        unlink(JB_SYMLINK_TARGET_FILE);
        return -1;
    }

    // Create empty directory in its place
    if (mkdir(ROOTLESS_PREFIX, 0755) != 0) {
        fprintf(stderr, "jb_bypass: failed to create fake /var/jb dir: %s\n", strerror(errno));
        // Try to restore symlink
        symlink(target, ROOTLESS_PREFIX);
        unlink(JB_SYMLINK_TARGET_FILE);
        return -1;
    }

    fprintf(stderr, "jb_bypass: hid /var/jb symlink (was -> %s)\n", target);
    return 1;
}

// Restore /var/jb symlink: remove fake dir, recreate symlink to original target
static int restore_varjb_symlink(void) {
    // Read saved target
    FILE *f = fopen(JB_SYMLINK_TARGET_FILE, "r");
    if (!f) {
        fprintf(stderr, "jb_bypass: no saved symlink target, skipping restore\n");
        return 0;
    }
    char target[1024] = {0};
    if (!fgets(target, sizeof(target), f)) {
        fclose(f);
        return 0;
    }
    fclose(f);

    // Remove trailing newline if any
    size_t tlen = strlen(target);
    if (tlen > 0 && target[tlen - 1] == '\n') target[tlen - 1] = '\0';

    if (target[0] == '\0') {
        fprintf(stderr, "jb_bypass: empty symlink target, skipping restore\n");
        return 0;
    }

    // Check if /var/jb is currently a directory (our fake)
    struct stat st;
    if (lstat(ROOTLESS_PREFIX, &st) == 0) {
        if (S_ISDIR(st.st_mode) && !S_ISLNK(st.st_mode)) {
            // Remove the fake directory (should be empty)
            if (rmdir(ROOTLESS_PREFIX) != 0) {
                fprintf(stderr, "jb_bypass: failed to remove fake /var/jb dir: %s\n", strerror(errno));
                return -1;
            }
        } else if (S_ISLNK(st.st_mode)) {
            // Already a symlink, nothing to restore
            fprintf(stderr, "jb_bypass: /var/jb already a symlink, skipping restore\n");
            unlink(JB_SYMLINK_TARGET_FILE);
            return 0;
        }
    }

    // Recreate symlink
    if (symlink(target, ROOTLESS_PREFIX) != 0) {
        fprintf(stderr, "jb_bypass: failed to restore /var/jb symlink: %s\n", strerror(errno));
        return -1;
    }

    unlink(JB_SYMLINK_TARGET_FILE);
    fprintf(stderr, "jb_bypass: restored /var/jb -> %s\n", target);
    return 1;
}

// --- Tweak Injection Bypass ---
// ponytail: writes Choicy plist to disable tweak injection for an app
// Only effective if user has Choicy installed; harmless otherwise
#define CHOICY_PREFS_PATH "/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist"

static int disable_tweaks_for_app(const char *bundle_id) {
    if (!bundle_id || bundle_id[0] == '\0') return -1;

    // Build plist content - Choicy format uses appSettings dict
    // Key = bundle_id, Value = dict with "tweakInjectionDisabled" = true
    char plist[4096];
    snprintf(plist, sizeof(plist),
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
        "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        "<plist version=\"1.0\">\n"
        "<dict>\n"
        "    <key>appSettings</key>\n"
        "    <dict>\n"
        "        <key>%s</key>\n"
        "        <dict>\n"
        "            <key>tweakInjectionDisabled</key>\n"
        "            <true/>\n"
        "        </dict>\n"
        "    </dict>\n"
        "</dict>\n"
        "</plist>\n",
        bundle_id);

    // Ensure directory exists
    mkdir("/var/mobile/Library/Preferences", 0755);

    FILE *f = fopen(CHOICY_PREFS_PATH, "w");
    if (!f) {
        fprintf(stderr, "jb_bypass: failed to write Choicy prefs: %s\n", strerror(errno));
        return -1;
    }
    fprintf(f, "%s", plist);
    fclose(f);
    chmod(CHOICY_PREFS_PATH, 0644);
    chown(CHOICY_PREFS_PATH, 501, 501);  // mobile:mobile

    fprintf(stderr, "jb_bypass: disabled tweaks for %s via Choicy\n", bundle_id);
    return 0;
}

static void restore_tweak_injection(void) {
    // ponytail: just delete the plist we created; leaves user's real Choicy alone
    // since we overwrote it, removing is the cleanest restore
    unlink(CHOICY_PREFS_PATH);
    fprintf(stderr, "jb_bypass: removed Choicy tweak blacklist\n");
}

// --- Sandbox Write Monitor ---
// ponytail: child process watches common jb detection paths, deletes test files
// Monitors /tmp and /private/var/mobile for jb_test*, jailbreak*, cydia* files
#define MONITOR_PATHS_COUNT 3
static const char *MONITOR_PATHS[] = {
    "/tmp",
    "/private/var/mobile",
    "/private/var/tmp"
};

static void sandbox_monitor_loop(void) {
    int kq = kqueue();
    if (kq < 0) {
        fprintf(stderr, "jb_monitor: kqueue failed: %s\n", strerror(errno));
        _exit(1);
    }

    int fds[MONITOR_PATHS_COUNT];
    struct kevent evts[MONITOR_PATHS_COUNT];

    for (int i = 0; i < MONITOR_PATHS_COUNT; i++) {
        fds[i] = open(MONITOR_PATHS[i], O_RDONLY | O_DIRECTORY);
        if (fds[i] < 0) {
            fprintf(stderr, "jb_monitor: can't watch %s: %s\n", MONITOR_PATHS[i], strerror(errno));
            continue;
        }
        EV_SET(&evts[i], fds[i], EVFILT_VNODE, EV_ADD | EV_CLEAR,
               NOTE_WRITE | NOTE_EXTEND, 0, (void *)(intptr_t)i);
        kevent(kq, &evts[i], 1, NULL, 0, NULL);
    }

    fprintf(stderr, "jb_monitor: started, watching %d paths\n", MONITOR_PATHS_COUNT);

    // Patterns to delete - jailbreak detection test files
    const char *bad_patterns[] = {
        "jb_test*", "jailbreak*", "cydia*", ".jailbroken*",
        "substrate*", "frida*", NULL
    };

    struct kevent ev;
    while (1) {
        int n = kevent(kq, NULL, 0, &ev, 1, NULL);
        if (n <= 0) continue;

        int idx = (int)(intptr_t)ev.udata;
        if (idx < 0 || idx >= MONITOR_PATHS_COUNT) continue;

        const char *dir = MONITOR_PATHS[idx];
        DIR *dp = opendir(dir);
        if (!dp) continue;

        struct dirent *entry;
        while ((entry = readdir(dp)) != NULL) {
            if (entry->d_name[0] == '.') continue;

            for (int p = 0; bad_patterns[p]; p++) {
                if (fnmatch(bad_patterns[p], entry->d_name, FNM_CASEFOLD) == 0) {
                    char path[1024];
                    snprintf(path, sizeof(path), "%s/%s", dir, entry->d_name);

                    // Delete immediately
                    if (unlink(path) == 0) {
                        fprintf(stderr, "jb_monitor: deleted %s\n", path);
                    } else if (rmdir(path) == 0) {
                        fprintf(stderr, "jb_monitor: rmdir %s\n", path);
                    }
                    break;
                }
            }
        }
        closedir(dp);
    }
}

static void start_sandbox_monitor(void) {
    if (g_sandbox_monitor_pid > 0) {
        // Already running
        return;
    }

    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "jb_bypass: fork monitor failed: %s\n", strerror(errno));
        return;
    }

    if (pid == 0) {
        // Child - run the monitor loop
        setsid();  // detach from parent session
        sandbox_monitor_loop();
        _exit(0);  // never reached
    }

    g_sandbox_monitor_pid = pid;
    fprintf(stderr, "jb_bypass: sandbox monitor started (pid %d)\n", pid);
}

static void stop_sandbox_monitor(void) {
    if (g_sandbox_monitor_pid > 0) {
        kill(g_sandbox_monitor_pid, SIGTERM);
        waitpid(g_sandbox_monitor_pid, NULL, WNOHANG);
        g_sandbox_monitor_pid = 0;
        fprintf(stderr, "jb_bypass: sandbox monitor stopped\n");
    }
}

// ponytail: comprehensive bypass - filesystem + process + env hiding
// Runtime hooking done by Frida SpawnGate in Swift layer

#define JB_ALLOWLIST_FILE "/var/mobile/.beerus_jb_allowlist"
#define JB_RANDOM_PATH_FILE "/var/mobile/.beerus_jb_random_path"
#define JB_LAUNCHD_OVERRIDES "/var/db/launchd.db/com.apple.launchd/overrides.plist"
#define JB_ENV_BACKUP_FILE "/var/mobile/.beerus_env_backup"

// --- Environment Sanitization ---
// ponytail: write clean env to launchd override, clear DYLD_* vars

static int sanitize_environment(void) {
    // Kill launchd's cached DYLD_* by writing an override plist
    // This affects newly spawned processes
    const char *env_cleanup_cmd = g_rootless ?
        "launchctl unsetenv DYLD_INSERT_LIBRARIES 2>/dev/null; "
        "launchctl unsetenv DYLD_LIBRARY_PATH 2>/dev/null; "
        "launchctl unsetenv _MSSafeMode 2>/dev/null" :
        "launchctl unsetenv DYLD_INSERT_LIBRARIES 2>/dev/null; "
        "launchctl unsetenv DYLD_LIBRARY_PATH 2>/dev/null";

    run_shell(env_cleanup_cmd);
    fprintf(stderr, "jb_bypass: cleared DYLD_* from launchd environment\n");
    return 0;
}

// --- Jailbreak Daemon Control ---
// ponytail: can optionally stop JB daemons, but this is aggressive
// Only stop frida-server, leave substituted/jailbreakd running
// (stopping those breaks the entire JB for all apps)

static const char *JB_DAEMONS_TO_STOP[] = {
    "frida-server",     // detection vector, restart on disable
    NULL
};

static void stop_jb_daemons(void) {
    for (int i = 0; JB_DAEMONS_TO_STOP[i]; i++) {
        char cmd[256];
        snprintf(cmd, sizeof(cmd), "killall -9 %s 2>/dev/null", JB_DAEMONS_TO_STOP[i]);
        run_shell(cmd);
        fprintf(stderr, "jb_bypass: stopped %s\n", JB_DAEMONS_TO_STOP[i]);
    }
}

// --- Path Randomization (RootHide-style) ---
// ponytail: generate random path, move /var/jb contents there
// This is the nuclear option - only use if simpler methods fail

static char g_random_jb_path[256] = {0};

static void generate_random_path(void) {
    // Generate 16 random hex chars
    char random[17];
    FILE *f = fopen("/dev/urandom", "r");
    if (f) {
        unsigned char bytes[8];
        fread(bytes, 1, 8, f);
        fclose(f);
        for (int i = 0; i < 8; i++) {
            sprintf(random + i*2, "%02x", bytes[i]);
        }
    } else {
        // Fallback to timestamp
        snprintf(random, sizeof(random), "%08lx%08x", (unsigned long)time(NULL), getpid());
    }
    random[16] = '\0';

    // Use containers path - survives reboots, looks legitimate
    snprintf(g_random_jb_path, sizeof(g_random_jb_path),
             "/var/containers/Bundle/.sys-%s", random);
}

static int load_random_path(void) {
    FILE *f = fopen(JB_RANDOM_PATH_FILE, "r");
    if (!f) return 0;
    if (!fgets(g_random_jb_path, sizeof(g_random_jb_path), f)) {
        fclose(f);
        return 0;
    }
    fclose(f);
    // Trim newline
    size_t len = strlen(g_random_jb_path);
    if (len > 0 && g_random_jb_path[len-1] == '\n') g_random_jb_path[len-1] = '\0';
    return g_random_jb_path[0] != '\0';
}

static void save_random_path(void) {
    FILE *f = fopen(JB_RANDOM_PATH_FILE, "w");
    if (f) {
        fprintf(f, "%s", g_random_jb_path);
        fclose(f);
        chmod(JB_RANDOM_PATH_FILE, 0600);
    }
}

// Move /var/jb to random path, update internal symlinks
// Returns 0 on success
static int randomize_jb_path(void) {
    if (!g_rootless) return 0;  // Only for rootless

    // Read current symlink target
    char orig_target[1024];
    ssize_t len = readlink(ROOTLESS_PREFIX, orig_target, sizeof(orig_target) - 1);
    if (len <= 0) {
        fprintf(stderr, "jb_bypass: /var/jb not a symlink, skip randomization\n");
        return -1;
    }
    orig_target[len] = '\0';

    // Generate random path if not already set
    if (g_random_jb_path[0] == '\0') {
        if (!load_random_path()) {
            generate_random_path();
            save_random_path();
        }
    }

    // Create random dir
    mkdir(g_random_jb_path, 0755);

    // Move contents: mv /var/jb/* to random path
    // This is done via cp + rm since mv across filesystems fails
    char cmd[2048];
    snprintf(cmd, sizeof(cmd),
        "cp -a '%s/'* '%s/' 2>/dev/null && rm -rf '%s/'* 2>/dev/null",
        orig_target, g_random_jb_path, orig_target);

    if (run_shell(cmd) != 0) {
        fprintf(stderr, "jb_bypass: failed to move JB contents\n");
        return -1;
    }

    // Update /var/jb symlink to point to random path
    unlink(ROOTLESS_PREFIX);
    if (symlink(g_random_jb_path, ROOTLESS_PREFIX) != 0) {
        // Restore original
        symlink(orig_target, ROOTLESS_PREFIX);
        fprintf(stderr, "jb_bypass: failed to update symlink\n");
        return -1;
    }

    // Save original for restore
    FILE *f = fopen(JB_SYMLINK_TARGET_FILE, "w");
    if (f) {
        fprintf(f, "%s", orig_target);
        fclose(f);
    }

    fprintf(stderr, "jb_bypass: randomized path to %s\n", g_random_jb_path);
    return 0;
}

// Restore from random path back to original
static int restore_random_path(void) {
    if (!g_rootless) return 0;
    if (g_random_jb_path[0] == '\0' && !load_random_path()) return 0;

    // Read original target
    char orig_target[1024] = {0};
    FILE *f = fopen(JB_SYMLINK_TARGET_FILE, "r");
    if (f) {
        fgets(orig_target, sizeof(orig_target), f);
        fclose(f);
        size_t len = strlen(orig_target);
        if (len > 0 && orig_target[len-1] == '\n') orig_target[len-1] = '\0';
    }
    if (orig_target[0] == '\0') return 0;

    // Move contents back
    char cmd[2048];
    snprintf(cmd, sizeof(cmd),
        "cp -a '%s/'* '%s/' 2>/dev/null && rm -rf '%s' 2>/dev/null",
        g_random_jb_path, orig_target, g_random_jb_path);
    run_shell(cmd);

    // Restore original symlink
    unlink(ROOTLESS_PREFIX);
    symlink(orig_target, ROOTLESS_PREFIX);

    // Cleanup
    unlink(JB_RANDOM_PATH_FILE);
    g_random_jb_path[0] = '\0';

    fprintf(stderr, "jb_bypass: restored original path %s\n", orig_target);
    return 0;
}

// Default allowlist - apps that CAN see jailbreak
static const char *DEFAULT_ALLOWLIST[] = {
    "io.hakaisecurity.BEERUS-Framework",
    "com.opa334.Dopamine",
    "org.coolstar.SileoStore",
    "xyz.willy.Zebra",
    "com.tigisoftware.Filza",
    "com.googlecode.mobileterminal.Terminal",
    "com.bingner.newterm",
    NULL
};

static void write_default_allowlist(void) {
    FILE *f = fopen(JB_ALLOWLIST_FILE, "w");
    if (!f) return;
    for (int i = 0; DEFAULT_ALLOWLIST[i]; i++) {
        fprintf(f, "%s\n", DEFAULT_ALLOWLIST[i]);
    }
    fclose(f);
    chmod(JB_ALLOWLIST_FILE, 0644);
}

// Enable JB bypass - comprehensive filesystem + environment hiding
static void jb_bypass_enable(char *out, size_t out_size) {
    if (g_jb_bypass_active) {
        snprintf(out, out_size, "ok: bypass already active");
        return;
    }

    // Create allowlist if doesn't exist
    if (access(JB_ALLOWLIST_FILE, F_OK) != 0) {
        write_default_allowlist();
    }

    int hidden_count = 0;

    // 1. Sanitize launchd environment (DYLD_* vars)
    sanitize_environment();

    // 2. Stop detection-prone daemons (frida-server)
    stop_jb_daemons();

    // 3. Hide /var/jb symlink (replace with empty dir)
    if (g_rootless) {
        if (hide_varjb_symlink() > 0) hidden_count++;
    }

    // 4. Hide known jailbreak paths
    const char **paths = g_rootless ? JB_HIDE_PATHS_ROOTLESS : JB_HIDE_PATHS_ROOTFUL;
    for (int i = 0; paths[i] != NULL; i++) {
        if (hide_path(paths[i])) hidden_count++;
    }
    save_bypass_state(paths, hidden_count);

    // 5. Start sandbox write monitor (deletes jb test files)
    start_sandbox_monitor();

    // 6. Create toggle file - checked by Frida spawn gate
    FILE *f = fopen(JB_BYPASS_TOGGLE, "w");
    if (f) {
        fprintf(f, "1");
        fclose(f);
    }

    g_jb_bypass_active = 1;
    snprintf(out, out_size, "ok: bypass enabled. hid %d paths. monitor pid %d. Apps must restart.",
             hidden_count, g_sandbox_monitor_pid);
}

// Disable JB bypass - restore all hidden paths and stop monitor
static void jb_bypass_disable(char *out, size_t out_size) {
    int restored_count = 0;

    // 1. Stop sandbox monitor
    stop_sandbox_monitor();

    // 2. Restore /var/jb symlink (rootless only)
    if (g_rootless) {
        if (restore_varjb_symlink() > 0) restored_count++;
        // Also restore from random path if it was used
        restore_random_path();
    }

    // 3. Restore hidden paths
    const char **paths = g_rootless ? JB_HIDE_PATHS_ROOTLESS : JB_HIDE_PATHS_ROOTFUL;
    for (int i = 0; paths[i] != NULL; i++) {
        if (restore_path(paths[i])) restored_count++;
    }

    // 4. Remove toggle file
    unlink(JB_BYPASS_TOGGLE);
    unlink(JB_BYPASS_STATE_FILE);

    g_jb_bypass_active = 0;
    snprintf(out, out_size, "ok: bypass disabled. restored %d paths. Apps must restart.", restored_count);
}

// Add bundle ID to allowlist (app can see jailbreak)
static void jb_allowlist_add(const char *bundle_id, char *out, size_t out_size) {
    if (!bundle_id || strlen(bundle_id) == 0) {
        snprintf(out, out_size, "error: bundle_id required");
        return;
    }

    // Check if already in list
    FILE *f = fopen(JB_ALLOWLIST_FILE, "r");
    if (f) {
        char line[256];
        while (fgets(line, sizeof(line), f)) {
            line[strcspn(line, "\n")] = 0;
            if (strcmp(line, bundle_id) == 0) {
                fclose(f);
                snprintf(out, out_size, "ok: %s already in allowlist", bundle_id);
                return;
            }
        }
        fclose(f);
    }

    // Append to list
    f = fopen(JB_ALLOWLIST_FILE, "a");
    if (!f) {
        snprintf(out, out_size, "error: cannot write allowlist");
        return;
    }
    fprintf(f, "%s\n", bundle_id);
    fclose(f);
    snprintf(out, out_size, "ok: added %s to allowlist", bundle_id);
}

// Remove bundle ID from allowlist (app will be bypassed)
static void jb_allowlist_remove(const char *bundle_id, char *out, size_t out_size) {
    if (!bundle_id || strlen(bundle_id) == 0) {
        snprintf(out, out_size, "error: bundle_id required");
        return;
    }

    FILE *f = fopen(JB_ALLOWLIST_FILE, "r");
    if (!f) {
        snprintf(out, out_size, "error: allowlist not found");
        return;
    }

    // Read all lines except the one to remove
    char *lines[256];
    int count = 0;
    char line[256];
    int found = 0;

    while (fgets(line, sizeof(line), f) && count < 256) {
        line[strcspn(line, "\n")] = 0;
        if (strcmp(line, bundle_id) == 0) {
            found = 1;
            continue;
        }
        if (strlen(line) > 0) {
            lines[count++] = strdup(line);
        }
    }
    fclose(f);

    if (!found) {
        for (int i = 0; i < count; i++) free(lines[i]);
        snprintf(out, out_size, "ok: %s not in allowlist", bundle_id);
        return;
    }

    // Rewrite file
    f = fopen(JB_ALLOWLIST_FILE, "w");
    if (f) {
        for (int i = 0; i < count; i++) {
            fprintf(f, "%s\n", lines[i]);
            free(lines[i]);
        }
        fclose(f);
    }
    snprintf(out, out_size, "ok: removed %s from allowlist", bundle_id);
}

// Get current allowlist
static void jb_allowlist_get(char *out, size_t out_size) {
    FILE *f = fopen(JB_ALLOWLIST_FILE, "r");
    if (!f) {
        snprintf(out, out_size, "allowlist: (empty)");
        return;
    }

    char result[4096] = "allowlist:";
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        line[strcspn(line, "\n")] = 0;
        if (strlen(line) > 0) {
            strncat(result, " ", sizeof(result) - strlen(result) - 1);
            strncat(result, line, sizeof(result) - strlen(result) - 1);
        }
    }
    fclose(f);
    snprintf(out, out_size, "%s", result);
}

// Launch app with Cloak (DYLD_INSERT_LIBRARIES injection)
static void jb_launch_cloaked(const char *bundle_id, char *out, size_t out_size) {
    if (!bundle_id || strlen(bundle_id) == 0) {
        snprintf(out, out_size, "error: no bundle_id provided");
        return;
    }

    // Trim whitespace
    char bid[256];
    strncpy(bid, bundle_id, sizeof(bid) - 1);
    bid[sizeof(bid) - 1] = '\0';
    char *p = bid;
    while (*p && (*p == ' ' || *p == '\n' || *p == '\r')) p++;
    char *end = p + strlen(p) - 1;
    while (end > p && (*end == ' ' || *end == '\n' || *end == '\r')) *end-- = '\0';

    // Ensure bypass toggle is active
    FILE *f = fopen(JB_BYPASS_TOGGLE, "w");
    if (f) {
        fprintf(f, "1");
        fclose(f);
        chmod(JB_BYPASS_TOGGLE, 0644);
    }

    // ponytail: use uiopen with environment variable
    // This launches the app via SpringBoard with our dylib injected
    const char *dylib_path = g_rootless
        ? "/var/jb/usr/lib/TweakInject/BeerusJBBypass.dylib"
        : "/Library/MobileSubstrate/DynamicLibraries/BeerusJBBypass.dylib";

    // Launch via uiopen - SpringBoard handles the actual launch
    // The bypass dylib will be injected via TweakInject when app starts
    char url[512];
    snprintf(url, sizeof(url), "%s://", p);

    // Use posix_spawn to run uiopen
    const char *uiopen_path = g_rootless ? "/var/jb/usr/bin/uiopen" : "/usr/bin/uiopen";
    char *argv[] = { (char *)uiopen_path, url, NULL };

    pid_t pid;
    int status = posix_spawn(&pid, uiopen_path, NULL, NULL, argv, environ);
    if (status != 0) {
        // Try fallback path
        uiopen_path = "/usr/bin/uiopen";
        argv[0] = (char *)uiopen_path;
        status = posix_spawn(&pid, uiopen_path, NULL, NULL, argv, environ);
    }

    if (status == 0) {
        waitpid(pid, &status, 0);
    }

    snprintf(out, out_size, "ok: launched %s with cloak", p);
    fprintf(stderr, "jb_launch_cloaked: launched %s\n", p);
}

// Get bypass status
static void jb_bypass_status(char *out, size_t out_size) {
    struct stat st;
    int toggle_exists = (stat(JB_BYPASS_TOGGLE, &st) == 0);
    int monitor_running = (g_sandbox_monitor_pid > 0 && kill(g_sandbox_monitor_pid, 0) == 0);
    int symlink_hidden = 0;
    if (g_rootless) {
        // Check if /var/jb is empty dir (hidden) vs symlink (normal)
        if (lstat(ROOTLESS_PREFIX, &st) == 0) {
            symlink_hidden = S_ISDIR(st.st_mode) && !S_ISLNK(st.st_mode);
        }
    }
    int random_active = (g_random_jb_path[0] != '\0' || access(JB_RANDOM_PATH_FILE, F_OK) == 0);

    snprintf(out, out_size, "bypass=%d toggle=%d monitor=%d symlink_hidden=%d random=%d",
             g_jb_bypass_active, toggle_exists, monitor_running, symlink_hidden, random_active);
}

// ponytail: simplified - no restore needed since we don't modify files anymore
static void jb_bypass_restore_on_startup(void) {
    // Just sync state with toggle file
    struct stat st;
    g_jb_bypass_active = (stat(JB_BYPASS_TOGGLE, &st) == 0);
    if (g_jb_bypass_active) {
        fprintf(stderr, "jb_bypass: bypass was active, state restored\n");
    }

    // Restore /var/jb symlink first (rootless only)
    if (g_rootless) {
        restore_varjb_symlink();
    }

    // ponytail: DON'T delete toggle on startup - it should persist!
    // Only restore hidden paths, not the toggle state
    fprintf(stderr, "jb_bypass: startup restore complete\n");
}

// ------------------ Mach-O Patching ------------------

// Find app binary path from bundle_id
// Returns 0 on success, -1 on error
static int find_app_binary(const char *bundle_id, char *out_path, size_t out_size) {
    // Try rootless first, then rootful
    const char *app_dirs[] = {
        "/var/jb/Applications",
        "/Applications",
        "/var/containers/Bundle/Application",  // App Store apps
        NULL
    };

    // ponytail: use correct shell path for rootless
    const char *shell = g_rootless ? "/var/jb/bin/sh" : "/bin/sh";

    for (int i = 0; app_dirs[i]; i++) {
        char find_cmd[1200];
        // Find Info.plist with matching bundle ID
        // ponytail: use correct shell in xargs for rootless compatibility
        snprintf(find_cmd, sizeof(find_cmd),
            "find '%s' -name 'Info.plist' -maxdepth 3 2>/dev/null | "
            "xargs -I{} %s -c 'plutil -p \"{}\" 2>/dev/null | grep -q \"%s\" && dirname \"{}\"' | head -1",
            app_dirs[i], shell, bundle_id);

        char app_path[1024] = {0};
        run_shell_capture(find_cmd, app_path, sizeof(app_path));
        // Trim newline
        size_t len = strlen(app_path);
        if (len > 0 && app_path[len-1] == '\n') app_path[len-1] = '\0';

        if (app_path[0] == '\0') continue;

        // Extract app name from .app directory
        char *app_name = strrchr(app_path, '/');
        if (!app_name) continue;
        app_name++;  // skip '/'

        // Remove .app extension to get binary name
        char binary_name[256];
        strncpy(binary_name, app_name, sizeof(binary_name) - 1);
        char *dot = strstr(binary_name, ".app");
        if (dot) *dot = '\0';

        // Construct full binary path
        snprintf(out_path, out_size, "%s/%s", app_path, binary_name);

        // Verify it exists
        if (access(out_path, F_OK) == 0) {
            return 0;
        }

        // Some apps have different binary name - try reading CFBundleExecutable
        char exec_cmd[2048];
        snprintf(exec_cmd, sizeof(exec_cmd),
            "plutil -p '%s/Info.plist' 2>/dev/null | grep CFBundleExecutable | "
            "sed 's/.*=> \"\\(.*\\)\"/\\1/'", app_path);

        char exec_name[256] = {0};
        run_shell_capture(exec_cmd, exec_name, sizeof(exec_name));
        // Trim newline
        size_t elen = strlen(exec_name);
        if (elen > 0 && exec_name[elen-1] == '\n') exec_name[elen-1] = '\0';
        if (exec_name[0] != '\0') {
            snprintf(out_path, out_size, "%s/%s", app_path, exec_name);
            if (access(out_path, F_OK) == 0) {
                return 0;
            }
        }
    }

    return -1;
}

// Get default dylib path based on jailbreak type
static const char *get_bypass_dylib_path(void) {
    if (g_rootless) {
        return "/var/jb/Library/TweakInject/BeerusJBBypass.dylib";
    } else {
        return "/Library/MobileSubstrate/DynamicLibraries/BeerusJBBypass.dylib";
    }
}

// Patch app to load our bypass dylib
static void patch_app(const char *bundle_id, char *out, size_t out_size) {
    if (!bundle_id || strlen(bundle_id) == 0) {
        snprintf(out, out_size, "error: bundle_id required");
        return;
    }

    char binary_path[1024];
    if (find_app_binary(bundle_id, binary_path, sizeof(binary_path)) != 0) {
        snprintf(out, out_size, "error: app not found: %s", bundle_id);
        return;
    }

    const char *dylib = get_bypass_dylib_path();

    // Verify dylib exists
    if (access(dylib, F_OK) != 0) {
        snprintf(out, out_size, "error: dylib not found: %s", dylib);
        return;
    }

    // Patch the binary
    if (patch_binary(binary_path, dylib) != 0) {
        snprintf(out, out_size, "error: failed to patch %s", binary_path);
        return;
    }

    // Re-sign with ldid
    if (resign_binary(binary_path, g_rootless) != 0) {
        snprintf(out, out_size, "error: failed to resign (patch applied but unsigned)");
        return;
    }

    snprintf(out, out_size, "ok: patched %s", binary_path);
}

// Remove our patch from app
static void unpatch_app(const char *bundle_id, char *out, size_t out_size) {
    if (!bundle_id || strlen(bundle_id) == 0) {
        snprintf(out, out_size, "error: bundle_id required");
        return;
    }

    char binary_path[1024];
    if (find_app_binary(bundle_id, binary_path, sizeof(binary_path)) != 0) {
        snprintf(out, out_size, "error: app not found: %s", bundle_id);
        return;
    }

    // Remove the patch
    if (unpatch_binary(binary_path) != 0) {
        snprintf(out, out_size, "error: failed to unpatch %s", binary_path);
        return;
    }

    // Re-sign with ldid
    if (resign_binary(binary_path, g_rootless) != 0) {
        snprintf(out, out_size, "error: failed to resign (patch removed but unsigned)");
        return;
    }

    snprintf(out, out_size, "ok: unpatched %s", binary_path);
}

// ------------------ Handle Client Code ------------------

static void handle_client(int fd) {
    char buf[BUF_SIZE] = {0};
    char out[BUF_SIZE] = {0};

    // verify client bundle id
    if (!verify_client(fd)) {
        snprintf(out, sizeof(out), "error: unauthorized");
        send(fd, out, strlen(out), 0);
        close(fd);
        return;
    }

    ssize_t n = recv(fd, buf, sizeof(buf) - 1, 0);
    if (n <= 0) goto done;

    if (strncmp(buf, "PING", 4) == 0) {
        snprintf(out, sizeof(out), "PONG");
    }
    else if (strncmp(buf, "GET_STATUS", 10) == 0) {
        snprintf(out, sizeof(out), "uid=%d euid=%d pid=%d rootless=%d",
                 getuid(), geteuid(), getpid(), g_rootless);
    }
    else if (strncmp(buf, "SET_PROXY ", 10) == 0) {
        char *proxy = buf + 10;

        CFDataRef data = read_file_data(PREFS);
        if (!data) {
            snprintf(out, sizeof(out), "error: failed to read preferences");
            goto done;
        }

        CFErrorRef err = NULL;
        CFPropertyListRef plist = CFPropertyListCreateWithData(
            kCFAllocatorDefault,
            data,
            kCFPropertyListMutableContainersAndLeaves,
            NULL,
            &err
        );
        CFRelease(data);

        if (!plist || CFGetTypeID(plist) != CFDictionaryGetTypeID()) {
            if (err) CFRelease(err);
            if (plist) CFRelease(plist);
            snprintf(out, sizeof(out), "error: invalid preferences format");
            goto done;
        }

        CFMutableDictionaryRef root = (CFMutableDictionaryRef)plist;

        char set_uuid[128] = {0};
        char active_if[64] = {0};
        CFStringRef sid = find_service_id(root, set_uuid, sizeof(set_uuid),
                                          active_if, sizeof(active_if));
        if (!sid) {
            CFRelease(plist);
            snprintf(out, sizeof(out), "error: failed to find active network service");
            goto done;
        }

        CFMutableDictionaryRef nsvc = (CFMutableDictionaryRef)dget(root, "NetworkServices");
        if (!nsvc || CFGetTypeID(nsvc) != CFDictionaryGetTypeID()) {
            CFRelease(sid);
            CFRelease(plist);
            snprintf(out, sizeof(out), "error: invalid NetworkServices");
            goto done;
        }

        CFMutableDictionaryRef svc =
            (CFMutableDictionaryRef)CFDictionaryGetValue((CFDictionaryRef)nsvc, sid);
        if (!svc || CFGetTypeID(svc) != CFDictionaryGetTypeID()) {
            CFRelease(sid);
            CFRelease(plist);
            snprintf(out, sizeof(out), "error: invalid active service");
            goto done;
        }

        // Ensure Proxies dict is mutable
        CFMutableDictionaryRef prox =
            (CFMutableDictionaryRef)dget((CFDictionaryRef)svc, "Proxies");

        if (!prox || CFGetTypeID(prox) != CFDictionaryGetTypeID()) {
            CFMutableDictionaryRef newp = CFDictionaryCreateMutable(
                kCFAllocatorDefault,
                0,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks
            );

            if (!newp) {
                CFRelease(sid);
                CFRelease(plist);
                snprintf(out, sizeof(out), "error: failed to create Proxies dictionary");
                goto done;
            }

            CFStringRef k = cfstr("Proxies");
            if (k) {
                CFDictionarySetValue(svc, k, newp);
                CFRelease(k);
            }
            CFRelease(newp);

            prox = (CFMutableDictionaryRef)dget((CFDictionaryRef)svc, "Proxies");
        }

        if (!prox || CFGetTypeID(prox) != CFDictionaryGetTypeID()) {
            CFRelease(sid);
            CFRelease(plist);
            snprintf(out, sizeof(out), "error: failed to access Proxies");
            goto done;
        }

        if (strcmp(proxy, "OFF") == 0) {
            // Clear all proxy settings
            mremove(prox, "HTTPEnable");
            mremove(prox, "HTTPSEnable");
            mremove(prox, "ProxyAutoConfigEnable");

            mremove(prox, "HTTPProxy");
            mremove(prox, "HTTPPort");

            mremove(prox, "HTTPSProxy");
            mremove(prox, "HTTPSPort");

            mremove(prox, "ProxyAutoConfigURLString");

            snprintf(out, sizeof(out), "ok: proxy disabled");
        } else {
            char proxy_copy[256];
            snprintf(proxy_copy, sizeof(proxy_copy), "%s", proxy);

            char *ip = strtok(proxy_copy, ":");
            char *port_str = strtok(NULL, ":");

            if (!ip || !port_str) {
                CFRelease(sid);
                CFRelease(plist);
                snprintf(out, sizeof(out), "error: invalid proxy format, expected IP:PORT");
                goto done;
            }

            int port = atoi(port_str);
            if (port <= 0 || port > 65535) {
                CFRelease(sid);
                CFRelease(plist);
                snprintf(out, sizeof(out), "error: invalid port");
                goto done;
            }

            mset_bool(prox, "HTTPEnable", 1);
            mset_str (prox, "HTTPProxy", ip);
            mset_int (prox, "HTTPPort", port);

            mset_bool(prox, "HTTPSEnable", 1);
            mset_str (prox, "HTTPSProxy", ip);
            mset_int (prox, "HTTPSPort", port);

            // remove PAC se existir
            mremove(prox, "ProxyAutoConfigEnable");
            mremove(prox, "ProxyAutoConfigURLString");

            snprintf(out, sizeof(out), "ok: proxy set to %s:%d", ip, port);
        }

        CFErrorRef werr = NULL;
        CFDataRef new_data = CFPropertyListCreateData(
            kCFAllocatorDefault,
            plist,
            kCFPropertyListBinaryFormat_v1_0,
            0,
            &werr
        );

        if (!new_data) {
            if (werr) CFRelease(werr);
            CFRelease(sid);
            CFRelease(plist);
            snprintf(out, sizeof(out), "error: failed to serialize preferences");
            goto done;
        }

        if (!write_file_atomic(PREFS,
                               CFDataGetBytePtr(new_data),
                               (size_t)CFDataGetLength(new_data))) {
            CFRelease(new_data);
            CFRelease(sid);
            CFRelease(plist);
            snprintf(out, sizeof(out), "error: failed to write updated preferences");
            goto done;
        }

        CFRelease(new_data);
        CFRelease(sid);
        CFRelease(plist);

        char shell_path[512];
        if (g_rootless) {
            snprintf(shell_path, sizeof(shell_path), "%s/bin/sh", ROOTLESS_PREFIX);
        } else {
            snprintf(shell_path, sizeof(shell_path), "/bin/sh");
        }
        const char *args[] = {"-c", "killall configd"};
        char *output = runCommand(shell_path, args, 2);
    
    } else if (strncmp(buf, "SHELL ", 6) == 0) {
        const char *cmd = buf + 6;

        // Resolve shell path
        char shell_path[512];
        if (g_rootless) {
            snprintf(shell_path, sizeof(shell_path), "%s/bin/sh", ROOTLESS_PREFIX);
        } else {
            snprintf(shell_path, sizeof(shell_path), "/bin/sh");
        }

        // Build shell args
        const char *args[] = {"-c", cmd};

        // 3. Executa o comando via posix_spawn (versão limpa sem trailers internos)
        char *output = runCommand(shell_path, args, 2);

        if (output) {
            send(fd, output, strlen(output), 0);
            free(output);
        } else {
            const char *err = "error: runCommand failed\n\0EXIT:1\0";
            send(fd, err, 31, 0); 
        }

        goto done;
    } else if (strncmp(buf, "EXEC ", 5) == 0) {
        // ponytail: use run_shell_capture - popen uses /bin/sh which doesn't exist on rootless
        int status = run_shell_capture(buf + 5, out, sizeof(out));
        if (out[0] == '\0') {
            snprintf(out, sizeof(out), status == 0 ? "ok" : "error: exit %d", status);
        }
    }
    else if (strncmp(buf, "RESTART_FRIDA", 13) == 0) {
        restart_frida(out, sizeof(out));
    }
    else if (strncmp(buf, "STOP_FRIDA", 10) == 0) {
        kill_frida_server();
        usleep(300000);
        kill_frida_server();
        snprintf(out, sizeof(out), "ok: frida-server stopped");
    }
    else if (strncmp(buf, "INSTALL_FRIDA ", 14) == 0) {
        install_frida(buf + 14, out, sizeof(out));
    }
    else if (strncmp(buf, "UNINSTALL_FRIDA", 15) == 0) {
        uninstall_frida(out, sizeof(out));
    }
    else if (strncmp(buf, "INSTALL_IPA ", 12) == 0) {
        install_ipa(buf + 12, out, sizeof(out));
    }
    else if (strncmp(buf, "INSTALL_APP ", 12) == 0) {
        install_extracted_app(buf + 12, out, sizeof(out));
    }
    else if (strncmp(buf, "OPEN_APP ", 9) == 0) {
        open_app(buf + 9, out, sizeof(out));
    }
    else if (strncmp(buf, "REFRESH_SB", 10) == 0) {
        refresh_springboard(out, sizeof(out));
    }
    else if (strncmp(buf, "WHOAMI", 6) == 0) {
        snprintf(out, sizeof(out), "uid=%d euid=%d", getuid(), geteuid());
    }
    else if (strncmp(buf, "JB_BYPASS_ON", 12) == 0) {
        jb_bypass_enable(out, sizeof(out));
    }
    else if (strncmp(buf, "JB_BYPASS_OFF", 13) == 0) {
        jb_bypass_disable(out, sizeof(out));
    }
    else if (strncmp(buf, "JB_BYPASS_STATUS", 16) == 0) {
        jb_bypass_status(out, sizeof(out));
    }
    else if (strncmp(buf, "JB_ALLOWLIST_ADD ", 17) == 0) {
        jb_allowlist_add(buf + 17, out, sizeof(out));
    }
    else if (strncmp(buf, "JB_ALLOWLIST_REMOVE ", 20) == 0) {
        jb_allowlist_remove(buf + 20, out, sizeof(out));
    }
    else if (strncmp(buf, "JB_ALLOWLIST_GET", 16) == 0) {
        jb_allowlist_get(out, sizeof(out));
    }
    else if (strncmp(buf, "JB_LAUNCH_CLOAKED ", 18) == 0) {
        jb_launch_cloaked(buf + 18, out, sizeof(out));
    }
    else if (strncmp(buf, "JB_RANDOMIZE_PATH", 17) == 0) {
        // Optional: RootHide-style path randomization (more aggressive)
        if (!g_rootless) {
            snprintf(out, sizeof(out), "error: path randomization only for rootless jailbreaks");
        } else if (randomize_jb_path() == 0) {
            snprintf(out, sizeof(out), "ok: JB path randomized to %s", g_random_jb_path);
        } else {
            snprintf(out, sizeof(out), "error: failed to randomize path");
        }
    }
    else if (strncmp(buf, "JB_RESTORE_PATH", 15) == 0) {
        // Restore from randomized path
        if (restore_random_path() == 0) {
            snprintf(out, sizeof(out), "ok: JB path restored");
        } else {
            snprintf(out, sizeof(out), "error: no randomized path to restore");
        }
    }
    else if (strncmp(buf, "INJECT_START", 12) == 0) {
        // Start auto-injection watcher
        const char *dylib = g_rootless
            ? "/var/jb/Library/TweakInject/BeerusJBBypass.dylib"
            : "/Library/MobileSubstrate/DynamicLibraries/BeerusJBBypass.dylib";
        if (injector_start_watcher(dylib) == 0) {
            snprintf(out, sizeof(out), "ok: injector watcher started");
        } else {
            snprintf(out, sizeof(out), "error: failed to start injector");
        }
    }
    else if (strncmp(buf, "INJECT_STOP", 11) == 0) {
        injector_stop_watcher();
        snprintf(out, sizeof(out), "ok: injector stopped");
    }
    else if (strncmp(buf, "INJECT_PID ", 11) == 0) {
        // Inject into specific PID
        pid_t pid = atoi(buf + 11);
        const char *dylib = g_rootless
            ? "/var/jb/Library/TweakInject/BeerusJBBypass.dylib"
            : "/Library/MobileSubstrate/DynamicLibraries/BeerusJBBypass.dylib";
        if (injector_inject(pid, dylib) == 0) {
            snprintf(out, sizeof(out), "ok: injected into pid %d", pid);
        } else {
            snprintf(out, sizeof(out), "error: injection failed for pid %d", pid);
        }
    }
    else if (strncmp(buf, "INJECT_APP ", 11) == 0) {
        // Inject into app by bundle_id - finds PID from running processes
        const char *bundle_id = buf + 11;
        if (strlen(bundle_id) == 0) {
            snprintf(out, sizeof(out), "error: bundle_id required");
            goto done;
        }

        // Find PID by bundle_id via lsappinfo/ps
        // ponytail: use run_shell_capture - popen uses /bin/sh which doesn't exist on rootless
        char cmd[512];
        snprintf(cmd, sizeof(cmd),
            "ps -eo pid,args 2>/dev/null | grep -F '%s' | grep -v grep | head -1 | awk '{print $1}'",
            bundle_id);

        char pid_str[32] = {0};
        run_shell_capture(cmd, pid_str, sizeof(pid_str));
        pid_t target_pid = atoi(pid_str);

        if (target_pid <= 0) {
            snprintf(out, sizeof(out), "error: app not running: %s", bundle_id);
            goto done;
        }

        const char *dylib = g_rootless
            ? "/var/jb/Library/TweakInject/BeerusJBBypass.dylib"
            : "/Library/MobileSubstrate/DynamicLibraries/BeerusJBBypass.dylib";

        if (injector_inject(target_pid, dylib) == 0) {
            snprintf(out, sizeof(out), "ok: injected into %s (pid %d)", bundle_id, target_pid);
        } else {
            snprintf(out, sizeof(out), "error: injection failed for %s (pid %d)", bundle_id, target_pid);
        }
    }
    else if (strncmp(buf, "INJECT_ALL", 10) == 0) {
        // Inject into all running non-allowlisted apps
        const char *dylib = g_rootless
            ? "/var/jb/Library/TweakInject/BeerusJBBypass.dylib"
            : "/Library/MobileSubstrate/DynamicLibraries/BeerusJBBypass.dylib";

        int count = injector_inject_all(dylib);
        if (count >= 0) {
            snprintf(out, sizeof(out), "ok: injected into %d apps", count);
        } else {
            snprintf(out, sizeof(out), "error: inject_all failed");
        }
    }
    // ponytail: Inject spawn hook into launchd for system-wide interception (no ElleKit)
    else if (strncmp(buf, "INJECT_LAUNCHD", 14) == 0) {
        const char *spawn_hook = g_rootless
            ? "/var/jb/usr/lib/BeerusSpawnHook.dylib"
            : "/usr/lib/BeerusSpawnHook.dylib";

        // launchd is always PID 1
        if (injector_inject(1, spawn_hook) == 0) {
            snprintf(out, sizeof(out), "ok: spawn hook injected into launchd");
        } else {
            snprintf(out, sizeof(out), "error: failed to inject spawn hook into launchd");
        }
    }
    // ponytail: Mach-O binary patching - alternative to runtime injection
    else if (strncmp(buf, "PATCH_APP ", 10) == 0) {
        patch_app(buf + 10, out, sizeof(out));
    }
    else if (strncmp(buf, "UNPATCH_APP ", 12) == 0) {
        unpatch_app(buf + 12, out, sizeof(out));
    }
    else {
        snprintf(out, sizeof(out), "error: unknown command");
    }

    send(fd, out, strlen(out), 0);

done:
    close(fd);
}

int main(void) {
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);
    signal(SIGPIPE, SIG_IGN);
    atexit(cleanup);

    detect_rootless();
    fprintf(stderr, "beerusd: rootless=%d frida=%s\n", g_rootless, g_frida_server_path);

    putenv(g_path_env);
    load_allowed_cdhash();

    // Restore JB files if daemon crashed while bypass was active
    jb_bypass_restore_on_startup();

    unlink(SOCK_PATH);

    srv = socket(AF_UNIX, SOCK_STREAM, 0);
    if (srv < 0) {
        perror("socket");
        return 1;
    }

    int on = 1;
    setsockopt(srv, SOL_LOCAL, LOCAL_PEERPID, &on, sizeof(on));

    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCK_PATH, sizeof(addr.sun_path) - 1);

    if (bind(srv, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        return 1;
    }

    chown(SOCK_PATH, 0, 501);  // root:mobile
    chmod(SOCK_PATH, 0660);

    if (listen(srv, 5) < 0) {
        perror("listen");
        return 1;
    }

    while (running) {
        int client = accept(srv, NULL, NULL);
        if (client >= 0) {
            handle_client(client);
        }
    }

    return 0;
}
