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



// proc_pidpath declaration (not in public SDK)
#define PROC_PIDPATHINFO_MAXSIZE 4096
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

#define PREFS "/var/preferences/SystemConfiguration/preferences.plist"
#define SOCK_PATH "/var/run/beerus.sock"
#define BUF_SIZE 8192
#define SHELL_BUF_SIZE 65536
#define ALLOWED_BUNDLE "BEERUS"

// Rootless prefix — set at startup
#define ROOTLESS_PREFIX "/var/jb"

#include <spawn.h>
#include <dirent.h>
#include <copyfile.h>
extern char **environ;

static int srv = -1;
static volatile sig_atomic_t running = 1;

// --- Rootless detection ---
static int g_rootless = 0;
static char g_frida_server_path[512] = {0};

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

// verify client is beerus app
static int verify_client(int fd) {
    pid_t pid;
    socklen_t len = sizeof(pid);

    // get client pid
    if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &len) != 0)
        return 0;

    // get executable path
    char path[PROC_PIDPATHINFO_MAXSIZE];
    if (proc_pidpath(pid, path, sizeof(path)) <= 0)
        return 0;

    // check if path contains bundle id
    return strstr(path, ALLOWED_BUNDLE) != NULL;
}

// Find and kill all frida-server processes using POSIX APIs
static void kill_frida_server(void) {
    DIR *dp = opendir("/proc");
    if (!dp) {
        // /proc not available on iOS — fall back to ps + grep
        FILE *fp = popen("ps -eo pid,comm 2>/dev/null", "r");
        if (!fp) return;
        char line[512];
        while (fgets(line, sizeof(line), fp)) {
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
        }
        pclose(fp);
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
    // Extract .deb to a temp dir, find frida-server, copy to FRIDA_SERVER_PATH
    char tmpdir[] = "/tmp/beerus-deb-XXXXXX";
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

    // Try dpkg-deb → dpkg -x → ar+tar fallback
    char *argv_dpkg[] = {dpkg_deb_path, "--extract", (char *)deb_path, tmpdir, NULL};
    char *argv_dpkg2[] = {dpkg_path, "-x", (char *)deb_path, tmpdir, NULL};

    int ok = run_cmd(dpkg_deb_path, argv_dpkg);
    if (ok != 0) ok = run_cmd(dpkg_path, argv_dpkg2);

    if (ok != 0) {
        char ar_cmd[2048];
        snprintf(ar_cmd, sizeof(ar_cmd),
            "cd '%s' && '%s' x '%s' 2>/dev/null && "
            "for f in data.tar.*; do '%s' xf \"$f\" 2>/dev/null; done",
            tmpdir, ar_path, deb_path, tar_path);
        if (run_shell(ar_cmd) != 0) {
            rm_rf(tmpdir);
            snprintf(out, out_size, "error: failed to extract .deb (no dpkg, ar+tar also failed)");
            return -1;
        }
    }

    // Locate frida-server regardless of rootful/rootless prefix
    char extracted[1100] = {0};
    char find_cmd[1200];
    snprintf(find_cmd, sizeof(find_cmd),
        "find '%s' -name frida-server -type f 2>/dev/null | head -1", tmpdir);
    FILE *fp = popen(find_cmd, "r");
    if (fp) {
        if (fgets(extracted, sizeof(extracted), fp)) {
            size_t len = strlen(extracted);
            if (len > 0 && extracted[len - 1] == '\n') extracted[len - 1] = '\0';
        }
        pclose(fp);
    }

    if (extracted[0] == '\0' || access(extracted, F_OK) != 0) {
        rm_rf(tmpdir);
        snprintf(out, out_size, "error: frida-server not found inside .deb");
        return -1;
    }

    int result = replace_frida_binary(extracted, out, out_size);
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
        snprintf(err_msg, 128, "pipe() falhou: %s", strerror(errno));
        return err_msg;
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);

    // Redireciona stdout e stderr para o pipe
    posix_spawn_file_actions_adddup2(&actions, pipefds[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipefds[1], STDERR_FILENO);

    // Fecha os fds desnecessários no processo filho
    posix_spawn_file_actions_addclose(&actions, pipefds[0]);
    posix_spawn_file_actions_addclose(&actions, pipefds[1]);

    // Prepara os argumentos (argv)
    char **args = malloc(sizeof(char *) * (argCount + 2));
    args[0] = (char *)binaryPath;
    for (int i = 0; i < argCount; i++) {
        args[i + 1] = (char *)arguments[i];
    }
    args[argCount + 1] = NULL;

    // Define o ambiente (PATH do rootless é crucial aqui)
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
            // Verifica se precisa de mais espaço no buffer de output
            if (current_len + bytesRead >= output_size) {
                output_size *= 2;
                char *new_output = realloc(output, output_size);
                if (!new_output) break; // Falha catastrófica de memória
                output = new_output;
            }
            memcpy(output + current_len, buffer, bytesRead);
            current_len += bytesRead;
            output[current_len] = '\0';
        }

        // Aguarda o processo terminar para não deixar "zumbi"
        int wstatus = 0;
        waitpid(pid, &wstatus, 0);
    } else {
        snprintf(output, output_size, "posix_spawn falhou: %s (%d)", strerror(spawnErr), spawnErr);
    }

    // Limpeza
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

// Encontra o ServiceID pelo CurrentSet + ServiceOrder + Interface ativa (Network/Interface)
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

    // Interface correta: Sets/<UUID>/Network/Interface
    CFDictionaryRef ifaceDict = (CFDictionaryRef)dget(net, "Interface");
    if (!get_first_key_name(ifaceDict, out_if, outsz_if)) return NULL;

    // ServiceOrder: Sets/<UUID>/Network/Global/IPv4/ServiceOrder
    CFDictionaryRef glob = (CFDictionaryRef)dget(net, "Global");
    CFDictionaryRef ipv4 = glob ? (CFDictionaryRef)dget(ipv4 = (CFDictionaryRef)dget(glob, "IPv4"), "dummy") : NULL;
    (void)ipv4; // evita warning se o compilador implicar

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

        // garante Proxies mutável
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
            // remove tudo
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

        // 1. Determina o shell correto conforme o ambiente (Rootful vs Rootless)
        char shell_path[512];
        if (g_rootless) {
            snprintf(shell_path, sizeof(shell_path), "%s/bin/sh", ROOTLESS_PREFIX);
        } else {
            snprintf(shell_path, sizeof(shell_path), "/bin/sh");
        }

        // 2. Prepara os argumentos para o shell
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
        FILE *fp = popen(buf + 5, "r");
        if (fp) {
            size_t len = fread(out, 1, sizeof(out) - 1, fp);
            out[len] = '\0';
            int status = pclose(fp);
            if (len == 0) {
                snprintf(out, sizeof(out), status == 0 ? "ok" : "error: exit %d", WEXITSTATUS(status));
            }
        } else {
            snprintf(out, sizeof(out), "error: popen failed");
        }
    }
    else if (strncmp(buf, "RESTART_FRIDA", 13) == 0) {
        restart_frida(out, sizeof(out));
    }
    else if (strncmp(buf, "INSTALL_FRIDA ", 14) == 0) {
        install_frida(buf + 14, out, sizeof(out));
    }
    else if (strncmp(buf, "UNINSTALL_FRIDA", 15) == 0) {
        uninstall_frida(out, sizeof(out));
    }
    else if (strncmp(buf, "WHOAMI", 6) == 0) {
        snprintf(out, sizeof(out), "uid=%d euid=%d", getuid(), geteuid());
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

    // Set PATH for popen/system calls that inherit environment
    putenv(g_path_env);

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

    // allow mobile user to connect
    chmod(SOCK_PATH, 0666);

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
