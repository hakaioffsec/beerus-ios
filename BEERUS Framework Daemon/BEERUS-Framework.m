#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <sys/wait.h>
#import <sys/un.h>
#import <syslog.h>
#import <signal.h>
#import <unistd.h>
#import <errno.h>
#import <spawn.h>

#include <sys/stat.h>
#include <sys/types.h>

#define PROC_PIDPATHINFO_MAXSIZE 4096
extern int proc_pidpath(pid_t pid, void *buffer, uint32_t buffersize);

#define SOCKET_PATH "/tmp/beerus.sock"

static volatile sig_atomic_t gKeepRunning = 1;

static void handleSignal(int sig) {
    if (sig == SIGTERM || sig == SIGINT) {
        gKeepRunning = 0;
    }
}

static BOOL isAllowedAction(NSString *action) {
    static NSSet<NSString *> *allow;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allow = [NSSet setWithArray:@[
            @"ping",
            @"get_status",
            @"run_command"
        ]];
    });
    return [allow containsObject:action];
}

BOOL isRootless(void) {
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"];
}

static NSString *defaultPATH(void) {
    if (isRootless()) {
        return @"/var/jb/usr/local/sbin:"
               "/var/jb/usr/local/bin:"
               "/var/jb/usr/sbin:"
               "/var/jb/usr/bin:"
               "/var/jb/sbin:"
               "/var/jb/bin:"
               "/usr/bin:/bin:/sbin";
    } else {
        return @"/usr/local/sbin:"
               "/usr/local/bin:"
               "/usr/sbin:"
               "/usr/bin:"
               "/sbin:/bin";
    }
}

NSString *runCommand(NSString *binaryPath, NSArray<NSString *> *arguments) {
    int pipefds[2];
    if (pipe(pipefds) != 0) {
        return [NSString stringWithFormat:@"pipe() falhou: %s", strerror(errno)];
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);

    posix_spawn_file_actions_adddup2(&actions, pipefds[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipefds[1], STDERR_FILENO);

    posix_spawn_file_actions_addclose(&actions, pipefds[0]);
    posix_spawn_file_actions_addclose(&actions, pipefds[1]);

    NSUInteger count = arguments.count;
    char **args = malloc(sizeof(char *) * (count + 2));
    args[0] = (char *)binaryPath.UTF8String;
    for (NSUInteger i = 0; i < count; i++) {
        args[i + 1] = (char *)arguments[i].UTF8String;
    }
    args[count + 1] = NULL;

    NSString *envPATH = [NSString stringWithFormat:@"PATH=%@", defaultPATH()];
    NSString *envTERM = @"TERM=xterm-256color";

    char *envp[] = {
        strdup(envPATH.UTF8String),
        strdup(envTERM.UTF8String),
        NULL
    };

    pid_t pid = 0;
    int spawnErr = posix_spawn(
        &pid,
        binaryPath.UTF8String,
        &actions,
        NULL,
        args,
        envp
    );

    close(pipefds[1]);

    NSMutableString *output = [NSMutableString string];

    if (spawnErr == 0) {
        char buffer[1024];
        ssize_t bytesRead;
        while ((bytesRead = read(pipefds[0], buffer, sizeof(buffer) - 1)) > 0) {
            buffer[bytesRead] = '\0';
            [output appendString:[NSString stringWithUTF8String:buffer] ?: @""];
        }

        int wstatus = 0;
        waitpid(pid, &wstatus, 0);

        if (WIFEXITED(wstatus)) {
            [output appendFormat:@"\n[exit=%d]", WEXITSTATUS(wstatus)];
        } else if (WIFSIGNALED(wstatus)) {
            [output appendFormat:@"\n[signal=%d]", WTERMSIG(wstatus)];
        }
    } else {
        [output appendFormat:@"posix_spawn falhou: %s (%d)", strerror(spawnErr), spawnErr];
    }

    close(pipefds[0]);
    posix_spawn_file_actions_destroy(&actions);
    free(args);

    free(envp[0]);
    free(envp[1]);

    return output;
}

static NSDictionary *handleRequest(NSDictionary *req) {
    NSString *action = req[@"action"];
    if (![action isKindOfClass:[NSString class]] || !isAllowedAction(action)) {
        return @{ @"ok": @NO, @"error": @"action_not_allowed" };
    }

    if ([action isEqualToString:@"ping"]) {
        return @{ @"ok": @YES, @"reply": @"pong" };
    }

    if ([action isEqualToString:@"get_status"]) {
        return @{
            @"ok": @YES,
            @"pid": @(getpid()),
            @"uid": @(getuid()),
            @"euid": @(geteuid())
        };
    }

    if ([action isEqualToString:@"run_command"]) {
        NSString *binaryPath = req[@"binary_path"];
        NSArray *arguments = req[@"arguments"];
        return @{ @"ok": @YES, @"result": runCommand(binaryPath, arguments) };
    }

    return @{ @"ok": @NO, @"error": @"unknown_action" };
}

// Lê uma linha (terminada em '\n') do socket. Retorna NSData (sem o '\n') ou nil se desconectou/erro.
static NSData *readLineFromFD(int fd) {
    NSMutableData *acc = [NSMutableData dataWithCapacity:256];
    uint8_t ch = 0;

    while (1) {
        ssize_t r = read(fd, &ch, 1);
        if (r == 0) {
            // cliente fechou
            return nil;
        }
        if (r < 0) {
            if (errno == EINTR) continue;
            return nil;
        }
        if (ch == '\n') {
            return [acc copy];
        }
        [acc appendBytes:&ch length:1];
        // limite simples pra evitar payload gigante
        if (acc.length > 64 * 1024) {
            return nil;
        }
    }
}

static int makeServerSocket(void) {
    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server < 0) {
        syslog(LOG_ERR, "socket() failed");
        return -1;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);

    unlink(SOCKET_PATH);

    if (bind(server, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        syslog(LOG_ERR, "bind() failed for %s", SOCKET_PATH);
        close(server);
        return -1;
    }

    // Permissões do arquivo-socket (pra testes por CLI/app). Ajuste se quiser restringir.
    chmod(SOCKET_PATH, 0666);

    if (listen(server, 16) != 0) {
        syslog(LOG_ERR, "listen() failed");
        close(server);
        return -1;
    }

    syslog(LOG_INFO, "Socket server listening on %s", SOCKET_PATH);
    return server;
}

static bool isBeerusFramework(int client) {
    pid_t pid;
    bool isBeerus;
    socklen_t len = sizeof(pid);
    if (getsockopt(client, SOL_LOCAL, LOCAL_PEERPID, &pid, &len) == 0) {
        char pathBuffer[PROC_PIDPATHINFO_MAXSIZE];
        if (proc_pidpath(pid, pathBuffer, sizeof(pathBuffer)) > 0) {
            isBeerus = (strstr(pathBuffer, "Applications/BEERUS Framework.app/BEERUS Framework") != NULL);
        } else {
            isBeerus = false;
        }
    } else {
        isBeerus = false;
    }
    
    return isBeerus;
}

static void serveRequests(int serverFD) {
    while (gKeepRunning) {
        int client = accept(serverFD, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) continue;
            syslog(LOG_ERR, "accept() failed");
            continue;
        }

        // if (!isBeerusFramework(client)) {
        //     NSLog(@"[BEERUS] Rejected connection from BEERUS Framework app (PID: %d)", getpid());
        //     // syslog(LOG_WARNING, "Rejected connection from BEERUS Framework app (PID: %d)", getpid());
        //     close(client);
        //     continue;
        // }
        // NSLog(@"[BEERUS] Accept connection");


        NSData *line = readLineFromFD(client);
        if (!line) {
            close(client);
            continue;
        }

        NSError *err = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:line options:0 error:&err];
        NSDictionary *req = [obj isKindOfClass:[NSDictionary class]] ? (NSDictionary *)obj : nil;

        if (!req) {
            NSDictionary *resp = @{@"ok": @NO, @"error": @"bad_json"};
            NSData *out = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
            if (out) {
                write(client, out.bytes, out.length);
                write(client, "\n", 1);
            }
            close(client);
            continue;
        }

        NSDictionary *resp = handleRequest(req);
        NSData *out = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
        if (out) {
            write(client, out.bytes, out.length);
            write(client, "\n", 1);
        }

        syslog(LOG_INFO, "handled action=%s ok=%d",
               [[req[@"action"] description] UTF8String],
               [resp[@"ok"] boolValue] ? 1 : 0);

        close(client);
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {

        signal(SIGTERM, handleSignal);
        signal(SIGINT, handleSignal);

        syslog(LOG_INFO, "Daemon starting (pid=%d uid=%d euid=%d)", getpid(), getuid(), geteuid());

        int serverFD = makeServerSocket();
        if (serverFD < 0) {
            syslog(LOG_ERR, "Failed to start socket server");
            closelog();
            return 1;
        }

        serveRequests(serverFD);

        close(serverFD);
        unlink(SOCKET_PATH);

        syslog(LOG_INFO, "Daemon exiting");
        closelog();
    }
    return 0;
}