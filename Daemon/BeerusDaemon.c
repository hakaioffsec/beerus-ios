// beerus daemon - root privileges for beerus app
// install: /usr/local/bin/beerusd
// launchd: /Library/LaunchDaemons/com.beerus.daemon.plist

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <signal.h>

// proc_pidpath declaration (not in public SDK)
#define PROC_PIDPATHINFO_MAXSIZE 4096
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

#define SOCK_PATH "/var/run/beerus.sock"
#define BUF_SIZE 8192
#define SHELL_BUF_SIZE 65536
#define ALLOWED_BUNDLE "BEERUS"
#define FRIDA_SERVER_PATH "/usr/sbin/frida-server"

#include <spawn.h>
#include <dirent.h>
#include <copyfile.h>
extern char **environ;

static int srv = -1;
static volatile sig_atomic_t running = 1;

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
    int result = posix_spawn(&pid, cmd_path, NULL, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);
    if (result != 0) return -1;
    int status;
    waitpid(pid, &status, 0);
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) return -1;
    return 0;
}

static int run_shell(const char *cmd) {
    char *argv[] = {"/bin/sh", "-c", (char *)cmd, NULL};
    return run_cmd("/bin/sh", argv);
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
    unlink(FRIDA_SERVER_PATH);

    if (copyfile(src, FRIDA_SERVER_PATH, NULL, COPYFILE_ALL) != 0) {
        snprintf(out, out_size, "error: failed to copy frida-server to %s", FRIDA_SERVER_PATH);
        return -1;
    }

    chown(FRIDA_SERVER_PATH, 0, 0);
    chmod(FRIDA_SERVER_PATH, 0755);
    return 0;
}

static int install_from_deb(const char *deb_path, char *out, size_t out_size) {
    // Extract .deb to a temp dir, find frida-server, copy to FRIDA_SERVER_PATH
    char tmpdir[] = "/tmp/beerus-deb-XXXXXX";
    if (mkdtemp(tmpdir) == NULL) {
        snprintf(out, out_size, "error: failed to create temp dir");
        return -1;
    }

    // Try dpkg-deb → dpkg -x → ar+tar fallback
    char *argv_dpkg[] = {"/usr/bin/dpkg-deb", "--extract", (char *)deb_path, tmpdir, NULL};
    char *argv_dpkg2[] = {"/usr/bin/dpkg", "-x", (char *)deb_path, tmpdir, NULL};

    int ok = run_cmd("/usr/bin/dpkg-deb", argv_dpkg);
    if (ok != 0) ok = run_cmd("/usr/bin/dpkg", argv_dpkg2);

    if (ok != 0) {
        char ar_cmd[2048];
        snprintf(ar_cmd, sizeof(ar_cmd),
            "cd '%s' && /usr/bin/ar x '%s' 2>/dev/null && "
            "for f in data.tar.*; do /usr/bin/tar xf \"$f\" 2>/dev/null; done",
            tmpdir, deb_path);
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
        snprintf(out, out_size, "ok: frida-server installed from .deb to %s", FRIDA_SERVER_PATH);
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
        char *argv[] = {"/usr/bin/xz", "-df", (char *)src_path, NULL};
        if (run_cmd("/usr/bin/xz", argv) != 0) {
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
        snprintf(out, out_size, "ok: frida-server installed to %s", FRIDA_SERVER_PATH);
    return result;
}

static int uninstall_frida(char *out, size_t out_size) {
    // 1. Stop running frida-server
    kill_frida_server();
    usleep(300000);
    kill_frida_server(); // SIGTERM stragglers

    // 2. Check if binary exists
    if (access(FRIDA_SERVER_PATH, F_OK) != 0) {
        snprintf(out, out_size, "ok: frida-server not installed");
        return 0;
    }

    // 3. Remove binary
    if (unlink(FRIDA_SERVER_PATH) != 0) {
        snprintf(out, out_size, "error: failed to remove %s", FRIDA_SERVER_PATH);
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
    if (access(FRIDA_SERVER_PATH, X_OK) != 0) {
        snprintf(out, out_size, "error: frida-server not found at %s", FRIDA_SERVER_PATH);
        return -1;
    }

    // 3. Spawn frida-server as a daemon using posix_spawn
    pid_t pid;
    char *argv[] = {FRIDA_SERVER_PATH, "-D", NULL};

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup(&attr, 0); // new process group (detach)

    int result = posix_spawn(&pid, FRIDA_SERVER_PATH, NULL, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);

    if (result != 0) {
        snprintf(out, out_size, "error: posix_spawn failed (%d)", result);
        return -1;
    }

    snprintf(out, out_size, "ok: frida-server started (pid %d)", pid);
    return 0;
}

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
    else if (strncmp(buf, "SHELL ", 6) == 0) {
        // Enhanced shell command: streams output and appends exit code trailer
        // Protocol: <stdout/stderr bytes>\n\x00EXIT:<code>\x00
        const char *cmd = buf + 6;
        // Redirect stderr to stdout capture both
        char full_cmd[BUF_SIZE + 16];
        snprintf(full_cmd, sizeof(full_cmd), "%s 2>&1", cmd);

        FILE *fp = popen(full_cmd, "r");
        if (!fp) {
            const char *err = "error: popen failed\n\0EXIT:127\0";
            send(fd, err, 30, 0);
            goto done;
        }

        char chunk[4096];
        size_t nr;
        while ((nr = fread(chunk, 1, sizeof(chunk), fp)) > 0) {
            size_t sent = 0;
            while (sent < nr) {
                ssize_t s = send(fd, chunk + sent, nr - sent, 0);
                if (s <= 0) { pclose(fp); goto done; }
                sent += (size_t)s;
            }
        }
        int status = pclose(fp);
        int exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : 128;

        char trailer[32];
        trailer[0] = '\n';
        trailer[1] = '\0';
        int tlen = snprintf(trailer + 2, sizeof(trailer) - 2, "EXIT:%d", exit_code);
        send(fd, trailer, 2 + tlen + 1, 0);  
        goto done;  
    }
    else if (strncmp(buf, "EXEC ", 5) == 0) {
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
