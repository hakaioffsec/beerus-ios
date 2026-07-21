// BeerusJBBypass.m - Native JB bypass using fishhook
// DEBUG VERSION with extensive logging

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <sys/mount.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <mach-o/dyld.h>
#import <dirent.h>
#import <errno.h>
#import <spawn.h>
#import <pthread.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <mach/vm_map.h>

// ponytail: mach_vm types not in iOS SDK, declare manually
typedef uint64_t mach_vm_address_t;
typedef uint64_t mach_vm_size_t;

#include "fishhook.h"
#include <sys/syscall.h>

// ponytail: csops flags for code signing detection
#ifndef CS_OPS_STATUS
#define CS_OPS_STATUS 0
#endif
#ifndef CS_VALID
#define CS_VALID 0x00000001
#endif
#ifndef CS_ADHOC
#define CS_ADHOC 0x00000002
#endif
#ifndef CS_GET_TASK_ALLOW
#define CS_GET_TASK_ALLOW 0x00000004
#endif
#ifndef CS_PLATFORM_BINARY
#define CS_PLATFORM_BINARY 0x04000000
#endif

// ptrace requests
#ifndef PT_DENY_ATTACH
#define PT_DENY_ATTACH 31
#endif
#ifndef PT_ATTACHEXC
#define PT_ATTACHEXC 14
#endif

// csops syscall
int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

#define ALLOWLIST_PATH "/var/mobile/.beerus_jb_allowlist"
#define BYPASS_TOGGLE "/var/mobile/.beerus_jb_bypass"
#define LOG_PATH "/var/mobile/.beerus_jb_log"

// ponytail: stock iOS 17 loads ~150-180 dylibs, cap filtered count to avoid detection
#define STOCK_IOS_MAX_DYLD_IMAGES 180

static BOOL g_bypass_active = NO;
static BOOL g_in_allowlist = NO;  // ponytail: cached allowlist check
static uint64_t g_last_toggle_check = 0;  // ponytail: mach_absolute_time of last check
static NSSet<NSString*> *g_jb_paths = nil;
static NSSet<NSString*> *g_jb_schemes = nil;
static NSSet<NSString*> *g_jb_substrings = nil;
// ponytail: shared set for directory entry/dyld image filtering
static NSSet<NSString*> *g_jb_name_substrings = nil;
static NSSet<NSString*> *g_jb_procs = nil;
static FILE *g_logfile = NULL;

#pragma mark - Logging

// ponytail: debug logging disabled in production - uncomment for debugging
#define BYPASS_DEBUG 1

static void logMsg(const char *fmt, ...) {
#if BYPASS_DEBUG
    va_list args;
    va_start(args, fmt);

    // Log to file only, no NSLog (exposes bypass name in system logs)
    if (!g_logfile) {
        g_logfile = fopen(LOG_PATH, "a");
    }
    if (g_logfile) {
        time_t now = time(NULL);
        struct tm *t = localtime(&now);
        fprintf(g_logfile, "[%02d:%02d:%02d] ", t->tm_hour, t->tm_min, t->tm_sec);
        vfprintf(g_logfile, fmt, args);
        fprintf(g_logfile, "\n");
        fflush(g_logfile);
    }
    va_end(args);
#else
    (void)fmt;
#endif
}

#pragma mark - Path checking

// ponytail: hide our own config files from apps
static BOOL isBypassConfigPath(const char *path) {
    if (!path) return NO;
    return (strcmp(path, ALLOWLIST_PATH) == 0 ||
            strcmp(path, BYPASS_TOGGLE) == 0 ||
            strcmp(path, LOG_PATH) == 0 ||
            strstr(path, ".beerus_jb") != NULL);
}

static BOOL isJBPath(const char *path) {
    if (!path) return NO;

    // ponytail: hide bypass config files
    if (isBypassConfigPath(path)) {
        return YES;
    }

    NSString *p = @(path);

    if ([g_jb_paths containsObject:p]) {
        logMsg("isJBPath: MATCH (exact) %s", path);
        return YES;
    }

    // ponytail: comprehensive prefix list for rootless/rootful JB paths
    if ([p hasPrefix:@"/var/jb"] ||
        [p hasPrefix:@"/private/var/jb"] ||
        [p hasPrefix:@"/Library/MobileSubstrate"] ||
        [p hasPrefix:@"/usr/lib/substrate"] ||
        [p hasPrefix:@"/usr/lib/substitute"] ||
        [p hasPrefix:@"/Developer"] ||
        [p hasPrefix:@"/cores/binpack"] ||
        [p hasPrefix:@"/private/preboot"] ||
        [p hasPrefix:@"/var/binpack"] ||
        [p hasPrefix:@"/var/containers/Bundle/iosbinpack"]) {
        logMsg("isJBPath: MATCH (prefix) %s", path);
        return YES;
    }

    // ponytail: paths commonly checked in JB detection
    if ([p isEqualToString:@"/usr/share"] ||
        [p isEqualToString:@"/usr/include"] ||
        [p isEqualToString:@"/boot"]) {
        return YES;
    }

    // ponytail: block readable system files used for JB detection
    // On stock iOS, sandboxed apps cannot read these - reading them = jailbroken
    if ([p isEqualToString:@"/etc/passwd"] ||
        [p isEqualToString:@"/etc/fstab"] ||
        [p isEqualToString:@"/etc/hosts"] ||
        [p isEqualToString:@"/etc/group"] ||
        [p isEqualToString:@"/etc/master.passwd"] ||
        [p isEqualToString:@"/etc/resolv.conf"] ||
        [p isEqualToString:@"/private/etc/passwd"] ||
        [p isEqualToString:@"/private/etc/fstab"] ||
        [p isEqualToString:@"/private/etc/hosts"] ||
        [p isEqualToString:@"/private/etc/group"] ||
        [p isEqualToString:@"/private/etc/master.passwd"] ||
        [p isEqualToString:@"/private/etc/resolv.conf"]) {
        logMsg("isJBPath: MATCH (sysfile) %s", path);
        return YES;
    }

    NSString *lower = p.lowercaseString;
    for (NSString *sub in g_jb_substrings) {
        if ([lower containsString:sub]) {
            logMsg("isJBPath: MATCH (substring %@) %s", sub, path);
            return YES;
        }
    }
    return NO;
}

// ponytail: shared check for directory entry names (readdir, contentsOfDirectory)
static BOOL isJBName(NSString *name) {
    if (!name) return NO;
    NSString *lower = name.lowercaseString;
    if ([lower isEqualToString:@"jb"] || [lower hasPrefix:@".hidden_"]) return YES;
    for (NSString *sub in g_jb_name_substrings) {
        if ([lower containsString:sub]) return YES;
    }
    return NO;
}

// ponytail: sandbox boundary check - only app container and temp are writable on stock iOS
static BOOL isInSandbox(const char *path) {
    if (!path) return YES;

    // ponytail: allow JBDetector log for testing purposes
    if (strstr(path, ".jbdetector_log") != NULL) return YES;

    // ponytail: block /var/tmp writes (JB detection test)
    if (strstr(path, "/var/tmp") != NULL || strstr(path, "/private/var/tmp") != NULL) {
        return NO;
    }

    NSString *p = @(path);
    NSString *real = p.stringByStandardizingPath;

    // App container paths
    NSString *home = NSHomeDirectory();
    NSString *tmp = NSTemporaryDirectory();

    if ([real hasPrefix:home] || [real hasPrefix:tmp]) return YES;
    if ([real hasPrefix:@"/var/mobile/Containers/Data/Application/"] ||
        [real hasPrefix:@"/private/var/mobile/Containers/Data/Application/"]) return YES;
    // Shared containers
    if ([real hasPrefix:@"/var/mobile/Containers/Shared/AppGroup/"] ||
        [real hasPrefix:@"/private/var/mobile/Containers/Shared/AppGroup/"]) return YES;

    return NO;
}

// ponytail: dynamic toggle check with 500ms cache to avoid excessive I/O
static BOOL shouldBypass(void) {
    // If in allowlist, never bypass (cached at init)
    if (g_in_allowlist) return NO;

    // Check toggle file every 500ms max
    static mach_timebase_info_data_t timebase = {0};
    if (timebase.denom == 0) mach_timebase_info(&timebase);

    uint64_t now = mach_absolute_time();
    uint64_t elapsed_ns = (now - g_last_toggle_check) * timebase.numer / timebase.denom;

    // 500ms = 500,000,000 ns
    if (elapsed_ns > 500000000 || g_last_toggle_check == 0) {
        g_last_toggle_check = now;
        g_bypass_active = [[NSFileManager defaultManager] fileExistsAtPath:@BYPASS_TOGGLE];
    }

    return g_bypass_active;
}

#pragma mark - C function hooks via fishhook

// stat
static int (*orig_stat)(const char *path, struct stat *buf);
static int hook_stat(const char *path, struct stat *buf) {
    if (shouldBypass() && path && isJBPath(path)) {
        logMsg("HOOK stat: BLOCKED %s", path);
        errno = ENOENT;
        return -1;
    }
    return orig_stat(path, buf);
}

// lstat
static int (*orig_lstat)(const char *path, struct stat *buf);
static int hook_lstat(const char *path, struct stat *buf) {
    if (shouldBypass() && path && isJBPath(path)) {
        logMsg("HOOK lstat: BLOCKED %s", path);
        errno = ENOENT;
        return -1;
    }
    return orig_lstat(path, buf);
}

// ponytail: stat64/lstat64 variants used by some detectors
static int (*orig_stat64)(const char *path, struct stat *buf);
static int hook_stat64(const char *path, struct stat *buf) {
    if (shouldBypass() && path && isJBPath(path)) {
        logMsg("HOOK stat64: BLOCKED %s", path);
        errno = ENOENT;
        return -1;
    }
    if (orig_stat64) return orig_stat64(path, buf);
    return orig_stat(path, buf);
}

static int (*orig_lstat64)(const char *path, struct stat *buf);
static int hook_lstat64(const char *path, struct stat *buf) {
    if (shouldBypass() && path && isJBPath(path)) {
        logMsg("HOOK lstat64: BLOCKED %s", path);
        errno = ENOENT;
        return -1;
    }
    if (orig_lstat64) return orig_lstat64(path, buf);
    return orig_lstat(path, buf);
}

// access
static int (*orig_access)(const char *path, int mode);
static int hook_access(const char *path, int mode) {
    if (shouldBypass() && path && isJBPath(path)) {
        logMsg("HOOK access: BLOCKED %s", path);
        errno = ENOENT;
        return -1;
    }
    return orig_access(path, mode);
}

// faccessat
static int (*orig_faccessat)(int dirfd, const char *path, int mode, int flag);
static int hook_faccessat(int dirfd, const char *path, int mode, int flag) {
    if (shouldBypass() && path && isJBPath(path)) {
        logMsg("HOOK faccessat: BLOCKED %s", path);
        errno = ENOENT;
        return -1;
    }
    return orig_faccessat(dirfd, path, mode, flag);
}

// ponytail: fstatat - detectors use AT_FDCWD to bypass stat hooks
static int (*orig_fstatat)(int dirfd, const char *path, struct stat *buf, int flag);
static int hook_fstatat(int dirfd, const char *path, struct stat *buf, int flag) {
    if (shouldBypass() && path && isJBPath(path)) {
        logMsg("HOOK fstatat: BLOCKED %s", path);
        errno = ENOENT;
        return -1;
    }
    if (orig_fstatat) return orig_fstatat(dirfd, path, buf, flag);
    return orig_stat(path, buf);
}

// fopen
static FILE* (*orig_fopen)(const char *path, const char *mode);
static FILE* hook_fopen(const char *path, const char *mode) {
    if (shouldBypass() && path && isJBPath(path)) {
        logMsg("HOOK fopen: BLOCKED %s", path);
        errno = ENOENT;
        return NULL;
    }
    return orig_fopen(path, mode);
}

// ponytail: freopen can also open files
static FILE* (*orig_freopen)(const char *path, const char *mode, FILE *stream);
static FILE* hook_freopen(const char *path, const char *mode, FILE *stream) {
    if (shouldBypass() && path && isJBPath(path)) {
        logMsg("HOOK freopen: BLOCKED %s", path);
        errno = ENOENT;
        return NULL;
    }
    return orig_freopen(path, mode, stream);
}

// ponytail: fopen$NOCANCEL variant
static FILE* (*orig_fopen_nocancel)(const char *path, const char *mode);
static FILE* hook_fopen_nocancel(const char *path, const char *mode) {
    if (shouldBypass() && path && isJBPath(path)) {
        logMsg("HOOK fopen$NOCANCEL: BLOCKED %s", path);
        errno = ENOENT;
        return NULL;
    }
    if (orig_fopen_nocancel) return orig_fopen_nocancel(path, mode);
    return orig_fopen(path, mode);
}

// open
static int (*orig_open)(const char *path, int flags, ...);
static int hook_open(const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode = (mode_t)va_arg(args, int);
        va_end(args);
    }

    if (shouldBypass() && path && isJBPath(path)) {
        logMsg("HOOK open: BLOCKED %s", path);
        errno = ENOENT;
        return -1;
    }
    return orig_open(path, flags, mode);
}

// ponytail: openat for relative path access
static int (*orig_openat)(int dirfd, const char *path, int flags, ...);
static int hook_openat(int dirfd, const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode = (mode_t)va_arg(args, int);
        va_end(args);
    }

    if (shouldBypass() && path && isJBPath(path)) {
        logMsg("HOOK openat: BLOCKED %s", path);
        errno = ENOENT;
        return -1;
    }
    if (orig_openat) return orig_openat(dirfd, path, flags, mode);
    return -1;
}

// readlink
static ssize_t (*orig_readlink)(const char *path, char *buf, size_t bufsize);
static ssize_t hook_readlink(const char *path, char *buf, size_t bufsize) {
    if (shouldBypass() && path && isJBPath(path)) {
        logMsg("HOOK readlink: BLOCKED %s", path);
        errno = ENOENT;
        return -1;
    }
    return orig_readlink(path, buf, bufsize);
}

// ponytail: readlinkat for AT_FDCWD relative paths
static ssize_t (*orig_readlinkat)(int dirfd, const char *path, char *buf, size_t bufsize);
static ssize_t hook_readlinkat(int dirfd, const char *path, char *buf, size_t bufsize) {
    if (shouldBypass() && path && isJBPath(path)) {
        logMsg("HOOK readlinkat: BLOCKED %s", path);
        errno = ENOENT;
        return -1;
    }
    if (orig_readlinkat) return orig_readlinkat(dirfd, path, buf, bufsize);
    return orig_readlink(path, buf, bufsize);
}

// ponytail: realpath resolves symlinks - block for /var/jb etc
static char* (*orig_realpath)(const char *path, char *resolved_path);
static char* hook_realpath(const char *path, char *resolved_path) {
    if (shouldBypass() && path && isJBPath(path)) {
        logMsg("HOOK realpath: BLOCKED %s", path);
        errno = ENOENT;
        return NULL;
    }
    // Also filter output - resolved path might reveal JB locations
    char *result = orig_realpath(path, resolved_path);
    if (shouldBypass() && result && isJBPath(result)) {
        logMsg("HOOK realpath: BLOCKED resolved %s", result);
        errno = ENOENT;
        return NULL;
    }
    return result;
}

// readdir
static struct dirent* (*orig_readdir)(DIR *dirp);
static struct dirent* hook_readdir(DIR *dirp) {
    struct dirent *entry;
    while ((entry = orig_readdir(dirp)) != NULL) {
        if (!shouldBypass()) return entry;
        if (isJBName(@(entry->d_name))) {
            logMsg("HOOK readdir: SKIP %s", entry->d_name);
            continue;
        }
        return entry;
    }
    return NULL;
}

// fork - ponytail: also hook vfork, both must return -1 for sandbox appearance
static pid_t (*orig_fork)(void);
static pid_t hook_fork(void) {
    if (shouldBypass()) {
        logMsg("HOOK fork: BLOCKED");
        errno = EPERM;
        return -1;
    }
    if (orig_fork) return orig_fork();
    errno = EPERM;
    return -1;
}

static pid_t (*orig_vfork)(void);
static pid_t hook_vfork(void) {
    if (shouldBypass()) {
        logMsg("HOOK vfork: BLOCKED");
        errno = EPERM;
        return -1;
    }
    if (orig_vfork) return orig_vfork();
    errno = EPERM;
    return -1;
}

// popen - uses fork internally
static FILE* (*orig_popen)(const char *command, const char *type);
static FILE* hook_popen(const char *command, const char *type) {
    if (shouldBypass()) {
        logMsg("HOOK popen: BLOCKED %s", command ? command : "(null)");
        errno = EPERM;
        return NULL;
    }
    if (orig_popen) return orig_popen(command, type);
    errno = EPERM;
    return NULL;
}

// system - uses fork internally
static int (*orig_system)(const char *command);
static int hook_system(const char *command) {
    if (shouldBypass()) {
        logMsg("HOOK system: BLOCKED %s", command ? command : "(null)");
        errno = EPERM;
        return -1;
    }
    if (orig_system) return orig_system(command);
    errno = EPERM;
    return -1;
}

// ponytail: forward declarations for dlsym hook
static int hook_posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *file_actions,
                             const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]);
static int hook_syscall(int number, ...);
static int hook_open_nocancel(const char *path, int flags, ...);
static int hook_openat_nocancel(int dirfd, const char *path, int flags, ...);
static int hook_ptrace(int request, pid_t pid, caddr_t addr, int data);
static int hook_csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
static int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
static int hook_fstatat(int dirfd, const char *path, struct stat *buf, int flag);
static void* hook_dlopen(const char *path, int mode);
static int hook_isatty(int fd);
static pid_t hook_getppid(void);
static Class hook_objc_getClass(const char *name);
static kern_return_t hook_task_get_exception_ports(task_t, exception_mask_t, exception_mask_array_t,
    mach_msg_type_number_t *, exception_handler_array_t, exception_behavior_array_t, exception_flavor_array_t);
static kern_return_t hook_vm_read_overwrite(vm_map_t, vm_address_t, vm_size_t, vm_address_t, vm_size_t *);
static kern_return_t hook_mach_vm_read_overwrite(vm_map_t, mach_vm_address_t, mach_vm_size_t, mach_vm_address_t, mach_vm_size_t *);

// dlsym - ponytail: JBDetector uses dlsym(RTLD_DEFAULT, "fork") to bypass fishhook
// We hook dlsym to return our fake fork when asked
static void* (*orig_dlsym)(void *handle, const char *symbol);
static void* hook_dlsym(void *handle, const char *symbol) {
    if (shouldBypass() && symbol) {
        if (strcmp(symbol, "fork") == 0) {
            logMsg("HOOK dlsym: BLOCKED fork lookup, returning fake");
            return (void *)hook_fork;
        }
        if (strcmp(symbol, "vfork") == 0) {
            logMsg("HOOK dlsym: BLOCKED vfork lookup, returning fake");
            return (void *)hook_vfork;
        }
        if (strcmp(symbol, "popen") == 0) {
            logMsg("HOOK dlsym: BLOCKED popen lookup");
            return (void *)hook_popen;
        }
        if (strcmp(symbol, "system") == 0) {
            logMsg("HOOK dlsym: BLOCKED system lookup");
            return (void *)hook_system;
        }
        if (strcmp(symbol, "syscall") == 0) {
            logMsg("HOOK dlsym: BLOCKED syscall lookup");
            return (void *)hook_syscall;
        }
        if (strcmp(symbol, "posix_spawn") == 0) {
            logMsg("HOOK dlsym: BLOCKED posix_spawn lookup");
            return (void *)hook_posix_spawn;
        }
        // ponytail: block file reading lookups to prevent bypass
        if (strcmp(symbol, "fopen") == 0) {
            logMsg("HOOK dlsym: BLOCKED fopen lookup");
            return (void *)hook_fopen;
        }
        if (strcmp(symbol, "freopen") == 0) {
            logMsg("HOOK dlsym: BLOCKED freopen lookup");
            return (void *)hook_freopen;
        }
        if (strcmp(symbol, "open") == 0) {
            logMsg("HOOK dlsym: BLOCKED open lookup");
            return (void *)hook_open;
        }
        if (strcmp(symbol, "openat") == 0) {
            logMsg("HOOK dlsym: BLOCKED openat lookup");
            return (void *)hook_openat;
        }
        if (strcmp(symbol, "stat") == 0 || strcmp(symbol, "stat64") == 0) {
            logMsg("HOOK dlsym: BLOCKED stat lookup");
            return (void *)hook_stat;
        }
        if (strcmp(symbol, "lstat") == 0 || strcmp(symbol, "lstat64") == 0) {
            logMsg("HOOK dlsym: BLOCKED lstat lookup");
            return (void *)hook_lstat;
        }
        if (strcmp(symbol, "access") == 0) {
            logMsg("HOOK dlsym: BLOCKED access lookup");
            return (void *)hook_access;
        }
        // ponytail: $NOCANCEL variants for detectors that try to bypass hooks
        if (strcmp(symbol, "fopen$NOCANCEL") == 0) {
            logMsg("HOOK dlsym: BLOCKED fopen$NOCANCEL lookup");
            return (void *)hook_fopen_nocancel;
        }
        if (strcmp(symbol, "open$NOCANCEL") == 0) {
            logMsg("HOOK dlsym: BLOCKED open$NOCANCEL lookup");
            return (void *)hook_open_nocancel;
        }
        if (strcmp(symbol, "openat$NOCANCEL") == 0) {
            logMsg("HOOK dlsym: BLOCKED openat$NOCANCEL lookup");
            return (void *)hook_openat_nocancel;
        }
        // ponytail: anti-debug via dlsym bypass
        if (strcmp(symbol, "ptrace") == 0) {
            logMsg("HOOK dlsym: BLOCKED ptrace lookup");
            return (void *)hook_ptrace;
        }
        if (strcmp(symbol, "csops") == 0) {
            logMsg("HOOK dlsym: BLOCKED csops lookup");
            return (void *)hook_csops;
        }
        if (strcmp(symbol, "sysctl") == 0) {
            logMsg("HOOK dlsym: BLOCKED sysctl lookup");
            return (void *)hook_sysctl;
        }
        if (strcmp(symbol, "sysctlbyname") == 0) {
            logMsg("HOOK dlsym: BLOCKED sysctlbyname lookup");
            return (void *)hook_sysctlbyname;
        }
        if (strcmp(symbol, "fstatat") == 0) {
            logMsg("HOOK dlsym: BLOCKED fstatat lookup");
            return (void *)hook_fstatat;
        }
        if (strcmp(symbol, "dlopen") == 0) {
            logMsg("HOOK dlsym: BLOCKED dlopen lookup");
            return (void *)hook_dlopen;
        }
        if (strcmp(symbol, "isatty") == 0) {
            logMsg("HOOK dlsym: BLOCKED isatty lookup");
            return (void *)hook_isatty;
        }
        if (strcmp(symbol, "getppid") == 0) {
            logMsg("HOOK dlsym: BLOCKED getppid lookup");
            return (void *)hook_getppid;
        }
        if (strcmp(symbol, "objc_getClass") == 0) {
            logMsg("HOOK dlsym: BLOCKED objc_getClass lookup");
            return (void *)hook_objc_getClass;
        }
        if (strcmp(symbol, "task_get_exception_ports") == 0) {
            logMsg("HOOK dlsym: BLOCKED task_get_exception_ports lookup");
            return (void *)hook_task_get_exception_ports;
        }
        // ponytail: vm_read hooks for Frida memory scanning bypass
        if (strcmp(symbol, "vm_read_overwrite") == 0) {
            logMsg("HOOK dlsym: BLOCKED vm_read_overwrite lookup");
            return (void *)hook_vm_read_overwrite;
        }
        if (strcmp(symbol, "mach_vm_read_overwrite") == 0) {
            logMsg("HOOK dlsym: BLOCKED mach_vm_read_overwrite lookup");
            return (void *)hook_mach_vm_read_overwrite;
        }
    }
    if (orig_dlsym) return orig_dlsym(handle, symbol);
    return NULL;
}

// ponytail: objc_getClass - hide bypass tweak classes from runtime introspection
static Class (*orig_objc_getClass)(const char *name);
static Class hook_objc_getClass(const char *name) {
    if (shouldBypass() && name) {
        NSString *n = @(name);
        if ([n isEqualToString:@"ShadowRuleset"] ||
            [n isEqualToString:@"ABPattern"] ||
            [n isEqualToString:@"FlyJBX"] ||
            [n isEqualToString:@"HideJB"] ||
            [n isEqualToString:@"Liberty"] ||
            [n isEqualToString:@"BeerusJBBypass"]) {
            logMsg("HOOK objc_getClass: hiding %s", name);
            return nil;
        }
    }
    return orig_objc_getClass(name);
}

// posix_spawn - alternative to fork, used by some JB detections
static int (*orig_posix_spawn)(pid_t *pid, const char *path, const posix_spawn_file_actions_t *file_actions,
                                const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]);
static int hook_posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *file_actions,
                             const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]) {
    if (shouldBypass()) {
        logMsg("HOOK posix_spawn: BLOCKED %s", path ? path : "(null)");
        errno = EPERM;
        return EPERM;
    }
    if (orig_posix_spawn) return orig_posix_spawn(pid, path, file_actions, attrp, argv, envp);
    errno = EPERM;
    return EPERM;
}

// ponytail: syscall() hook - detectors bypass libc by calling syscall() directly
// arm64 syscall numbers: SYS_fork=2, SYS_open=5, SYS_stat=188, SYS_stat64=338,
// SYS_lstat=190, SYS_lstat64=340, SYS_access=33, SYS_vfork=66, SYS_openat=463
static int (*orig_syscall)(int number, ...);
static int hook_syscall(int number, ...) {
    va_list args;
    va_start(args, number);
    long a1 = va_arg(args, long);
    long a2 = va_arg(args, long);
    long a3 = va_arg(args, long);
    long a4 = va_arg(args, long);
    long a5 = va_arg(args, long);
    long a6 = va_arg(args, long);
    va_end(args);

    if (!shouldBypass()) {
        if (orig_syscall) return orig_syscall(number, a1, a2, a3, a4, a5, a6);
        errno = ENOSYS;
        return -1;
    }

    // SYS_fork = 2, SYS_vfork = 66
    if (number == 2 || number == 66) {
        logMsg("HOOK syscall: BLOCKED SYS_%s", number == 2 ? "fork" : "vfork");
        errno = EPERM;
        return -1;
    }

    // SYS_open = 5 (path is a1)
    if (number == 5 && a1 && isJBPath((const char *)a1)) {
        logMsg("HOOK syscall: BLOCKED SYS_open %s", (const char *)a1);
        errno = ENOENT;
        return -1;
    }

    // SYS_openat = 463 (path is a2)
    if (number == 463 && a2 && isJBPath((const char *)a2)) {
        logMsg("HOOK syscall: BLOCKED SYS_openat %s", (const char *)a2);
        errno = ENOENT;
        return -1;
    }

    // SYS_stat = 188, SYS_stat64 = 338 (path is a1)
    if ((number == 188 || number == 338) && a1 && isJBPath((const char *)a1)) {
        logMsg("HOOK syscall: BLOCKED SYS_stat %s", (const char *)a1);
        errno = ENOENT;
        return -1;
    }

    // SYS_lstat = 190, SYS_lstat64 = 340 (path is a1)
    if ((number == 190 || number == 340) && a1 && isJBPath((const char *)a1)) {
        logMsg("HOOK syscall: BLOCKED SYS_lstat %s", (const char *)a1);
        errno = ENOENT;
        return -1;
    }

    // SYS_access = 33 (path is a1)
    if (number == 33 && a1 && isJBPath((const char *)a1)) {
        logMsg("HOOK syscall: BLOCKED SYS_access %s", (const char *)a1);
        errno = ENOENT;
        return -1;
    }

    // ponytail: SYS_fstatat = 469 (path is a2, like openat)
    if (number == 469 && a2 && isJBPath((const char *)a2)) {
        logMsg("HOOK syscall: BLOCKED SYS_fstatat %s", (const char *)a2);
        errno = ENOENT;
        return -1;
    }

    // ponytail: SYS_csops = 169, SYS_csops_audittoken = 170 - code signing checks
    if (number == 169 || number == 170) {
        // a1 = pid, a2 = ops, a3 = useraddr, a4 = usersize
        unsigned int ops = (unsigned int)a2;
        if (ops == CS_OPS_STATUS && a3 && a4 >= sizeof(uint32_t)) {
            // Return valid signature - looks like legit Apple binary
            uint32_t *flags = (uint32_t *)a3;
            *flags = CS_VALID | CS_PLATFORM_BINARY;
            logMsg("HOOK syscall: FAKE SYS_csops status -> valid");
            return 0;
        }
    }

    // ponytail: SYS_ptrace = 26 - anti-debug
    if (number == 26) {
        int request = (int)a1;
        if (request == PT_DENY_ATTACH) {
            logMsg("HOOK syscall: BLOCKED SYS_ptrace PT_DENY_ATTACH");
            return 0;  // Pretend it worked
        }
        if (request == PT_ATTACHEXC) {
            logMsg("HOOK syscall: BLOCKED SYS_ptrace PT_ATTACHEXC");
            errno = EPERM;
            return -1;
        }
    }

    if (orig_syscall) return orig_syscall(number, a1, a2, a3, a4, a5, a6);
    errno = ENOSYS;
    return -1;
}

// ponytail: ptrace hook - block PT_DENY_ATTACH anti-debug
static int (*orig_ptrace)(int request, pid_t pid, caddr_t addr, int data);
static int hook_ptrace(int request, pid_t pid, caddr_t addr, int data) {
    if (shouldBypass()) {
        if (request == PT_DENY_ATTACH) {
            logMsg("HOOK ptrace: BLOCKED PT_DENY_ATTACH");
            return 0;  // Pretend it worked, but don't actually deny
        }
        if (request == PT_ATTACHEXC) {
            logMsg("HOOK ptrace: BLOCKED PT_ATTACHEXC");
            errno = EPERM;
            return -1;
        }
    }
    if (orig_ptrace) return orig_ptrace(request, pid, addr, data);
    errno = ENOSYS;
    return -1;
}

// ponytail: csops hook - return valid code signature to bypass CS checks
static int (*orig_csops)(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
static int hook_csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize) {
    if (shouldBypass() && ops == CS_OPS_STATUS && useraddr && usersize >= sizeof(uint32_t)) {
        uint32_t *flags = (uint32_t *)useraddr;
        *flags = CS_VALID | CS_PLATFORM_BINARY;
        logMsg("HOOK csops: FAKE status -> valid platform binary");
        return 0;
    }
    if (orig_csops) return orig_csops(pid, ops, useraddr, usersize);
    return -1;
}

// ponytail: task_get_exception_ports - return empty to hide debugger/Frida exception handlers
static kern_return_t (*orig_task_get_exception_ports)(
    task_t task, exception_mask_t exception_mask,
    exception_mask_array_t masks, mach_msg_type_number_t *masksCnt,
    exception_handler_array_t handlers, exception_behavior_array_t behaviors,
    exception_flavor_array_t flavors);
static kern_return_t hook_task_get_exception_ports(
    task_t task, exception_mask_t exception_mask,
    exception_mask_array_t masks, mach_msg_type_number_t *masksCnt,
    exception_handler_array_t handlers, exception_behavior_array_t behaviors,
    exception_flavor_array_t flavors) {
    kern_return_t ret = orig_task_get_exception_ports(task, exception_mask, masks, masksCnt, handlers, behaviors, flavors);
    if (shouldBypass() && ret == KERN_SUCCESS && masksCnt && handlers) {
        for (mach_msg_type_number_t i = 0; i < *masksCnt; i++) {
            handlers[i] = MACH_PORT_NULL;
        }
        logMsg("HOOK task_get_exception_ports: cleared %u ports", *masksCnt);
    }
    return ret;
}

// ponytail: pthread_getname_np - hide Frida/gum thread names
static int (*orig_pthread_getname_np)(pthread_t thread, char *name, size_t len);
static int hook_pthread_getname_np(pthread_t thread, char *name, size_t len) {
    int ret = orig_pthread_getname_np(thread, name, len);
    if (!shouldBypass() || ret != 0 || !name) return ret;

    NSString *tname = @(name);
    NSString *lower = tname.lowercaseString;
    // ponytail: Frida thread names to hide
    if ([lower containsString:@"frida"] ||
        [lower containsString:@"gum-js"] ||
        [lower containsString:@"gmain"] ||
        [lower containsString:@"gdbus"] ||
        [lower containsString:@"pool-frida"] ||
        [lower hasPrefix:@"frida-"]) {
        logMsg("HOOK pthread_getname_np: HIDE thread %s", name);
        // Replace with generic name
        strlcpy(name, "com.apple.main-thread", len);
    }
    return ret;
}

// ponytail: Frida memory signatures to scrub from vm_read output
static const char *g_frida_sigs[] = {
    "frida", "FRIDA", "Frida",
    "gum-js", "GUM-JS", "gmain", "gdbus",
    "r2frida", "fridaagent", "FridaAgent",
    "pool-frida", "frida-agent",
    NULL
};

static void scrubFridaSignatures(void *buf, size_t size) {
    if (!buf || size < 4) return;
    char *data = (char *)buf;

    for (const char **sig = g_frida_sigs; *sig; sig++) {
        size_t siglen = strlen(*sig);
        if (siglen > size) continue;

        for (size_t i = 0; i <= size - siglen; i++) {
            if (memcmp(data + i, *sig, siglen) == 0) {
                memset(data + i, ' ', siglen);
                logMsg("HOOK vm_read: scrubbed '%s' at offset %zu", *sig, i);
            }
        }
    }
}

// ponytail: vm_read_overwrite - most commonly used for memory scanning
static kern_return_t (*orig_vm_read_overwrite)(vm_map_t, vm_address_t, vm_size_t, vm_address_t, vm_size_t *);
static kern_return_t hook_vm_read_overwrite(vm_map_t target_task, vm_address_t address,
                                             vm_size_t size, vm_address_t data,
                                             vm_size_t *outsize) {
    kern_return_t ret = orig_vm_read_overwrite(target_task, address, size, data, outsize);
    if (shouldBypass() && ret == KERN_SUCCESS && data && outsize && *outsize > 0) {
        scrubFridaSignatures((void *)data, (size_t)*outsize);
    }
    return ret;
}

// ponytail: mach_vm_read_overwrite - 64-bit variant
static kern_return_t (*orig_mach_vm_read_overwrite)(vm_map_t, mach_vm_address_t, mach_vm_size_t,
                                                      mach_vm_address_t, mach_vm_size_t *);
static kern_return_t hook_mach_vm_read_overwrite(vm_map_t target_task, mach_vm_address_t address,
                                                   mach_vm_size_t size, mach_vm_address_t data,
                                                   mach_vm_size_t *outsize) {
    kern_return_t ret = orig_mach_vm_read_overwrite(target_task, address, size, data, outsize);
    if (shouldBypass() && ret == KERN_SUCCESS && data && outsize && *outsize > 0) {
        scrubFridaSignatures((void *)data, (size_t)*outsize);
    }
    return ret;
}

// ponytail: isatty - debuggers attach to TTY, stock apps don't have one
static int (*orig_isatty)(int fd);
static int hook_isatty(int fd) {
    if (shouldBypass() && (fd == STDIN_FILENO || fd == STDOUT_FILENO || fd == STDERR_FILENO)) {
        // Stock apps: isatty returns 0 for standard fds (no terminal)
        // Debugged apps: might return 1 if debugger provides TTY
        logMsg("HOOK isatty: FAKE fd=%d -> 0", fd);
        return 0;
    }
    return orig_isatty(fd);
}

// ponytail: getppid - some detectors check if parent is launchd (ppid=1)
static pid_t (*orig_getppid)(void);
static pid_t hook_getppid(void) {
    if (shouldBypass()) {
        // Stock app always has launchd as parent (pid 1)
        // Debugged app might have debugger as parent
        logMsg("HOOK getppid: FAKE -> 1 (launchd)");
        return 1;
    }
    return orig_getppid();
}

// posix_spawnp - path-searching variant
static int (*orig_posix_spawnp)(pid_t *pid, const char *file, const posix_spawn_file_actions_t *file_actions,
                                 const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]);
static int hook_posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *file_actions,
                              const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]) {
    if (shouldBypass()) {
        logMsg("HOOK posix_spawnp: BLOCKED %s", file ? file : "(null)");
        errno = EPERM;
        return EPERM;
    }
    if (orig_posix_spawnp) return orig_posix_spawnp(pid, file, file_actions, attrp, argv, envp);
    errno = EPERM;
    return EPERM;
}

// getenv
static char* (*orig_getenv)(const char *name);
static char* hook_getenv(const char *name) {
    if (shouldBypass() && name) {
        if (strcmp(name, "DYLD_INSERT_LIBRARIES") == 0 ||
            strcmp(name, "DYLD_LIBRARY_PATH") == 0 ||
            strcmp(name, "_MSSafeMode") == 0 ||
            strcmp(name, "SUBSTRATE_LIBRARY_PATH") == 0) {
            logMsg("HOOK getenv: BLOCKED %s", name);
            return NULL;
        }
    }
    return orig_getenv(name);
}

// sysctl
static int (*orig_sysctl)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
static int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);

    if (!shouldBypass() || ret != 0 || namelen < 3) return ret;
    if (name[0] != CTL_KERN || name[1] != KERN_PROC) return ret;
    if (!oldp || !oldlenp) return ret;

    size_t entry_size = sizeof(struct kinfo_proc);
    size_t count = *oldlenp / entry_size;
    struct kinfo_proc *procs = (struct kinfo_proc *)oldp;

    // ponytail: anti-debug - hide P_TRACED flag (apps check this to detect debugger)
    // KERN_PROC_PID query for own process is the common detection pattern
    if (name[2] == KERN_PROC_PID && count == 1) {
        if (procs[0].kp_proc.p_flag & P_TRACED) {
            logMsg("HOOK sysctl: HIDE P_TRACED flag for pid %d", procs[0].kp_proc.p_pid);
            procs[0].kp_proc.p_flag &= ~P_TRACED;
        }
    }

    // Filter JB processes from KERN_PROC_ALL listings
    size_t write_idx = 0;
    for (size_t i = 0; i < count; i++) {
        // ponytail: also clear P_TRACED on all returned processes
        procs[i].kp_proc.p_flag &= ~P_TRACED;

        NSString *pname = @(procs[i].kp_proc.p_comm);
        BOOL isJB = NO;
        for (NSString *jbp in g_jb_procs) {
            if ([pname.lowercaseString containsString:jbp]) {
                isJB = YES;
                logMsg("HOOK sysctl: HIDE process %s", procs[i].kp_proc.p_comm);
                break;
            }
        }
        if (!isJB) {
            if (write_idx != i) procs[write_idx] = procs[i];
            write_idx++;
        }
    }
    *oldlenp = write_idx * entry_size;

    return ret;
}

// ponytail: sysctlbyname - commonly used for hw.machine, kern.boottime queries
static int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int ret = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    if (!shouldBypass() || ret != 0 || !name || !oldp || !oldlenp) return ret;

    // ponytail: kern.proc.pid filters same as sysctl KERN_PROC_PID - hide P_TRACED
    if (strncmp(name, "kern.proc.pid.", 14) == 0) {
        if (*oldlenp >= sizeof(struct kinfo_proc)) {
            struct kinfo_proc *proc = (struct kinfo_proc *)oldp;
            if (proc->kp_proc.p_flag & P_TRACED) {
                logMsg("HOOK sysctlbyname: HIDE P_TRACED for %s", name);
                proc->kp_proc.p_flag &= ~P_TRACED;
            }
        }
    }
    return ret;
}

// ponytail: helper to check JB ports
static BOOL isJBPort(uint16_t port) {
    // SSH=22, Cydia=44, reverse shell=4444, Frida=27042-27049
    return (port == 22 || port == 44 || port == 4444 || (port >= 27042 && port <= 27049));
}

// ponytail: check if address is localhost (127.0.0.1 or ::1)
static BOOL isLocalhost(const struct sockaddr *addr) {
    if (!addr) return NO;

    if (addr->sa_family == AF_INET) {
        uint32_t ip = ntohl(((const struct sockaddr_in *)addr)->sin_addr.s_addr);
        return (ip == 0x7F000001); // 127.0.0.1
    } else if (addr->sa_family == AF_INET6) {
        const struct sockaddr_in6 *addr6 = (const struct sockaddr_in6 *)addr;
        // Check for ::1
        static const uint8_t loopback6[16] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1};
        if (memcmp(&addr6->sin6_addr, loopback6, 16) == 0) return YES;
        // Check for ::ffff:127.0.0.1 (IPv4-mapped)
        static const uint8_t mapped_prefix[12] = {0,0,0,0,0,0,0,0,0,0,0xFF,0xFF};
        if (memcmp(&addr6->sin6_addr, mapped_prefix, 12) == 0) {
            uint8_t *ipv4 = ((uint8_t *)&addr6->sin6_addr) + 12;
            if (ipv4[0] == 127 && ipv4[1] == 0 && ipv4[2] == 0 && ipv4[3] == 1) return YES;
        }
    }
    return NO;
}

// ponytail: SMART detection - check if this looks like a detection scan vs real use
// Detection scans: localhost + short timeout (1-2s) + JB port
// Real connections: no timeout or long timeout
static BOOL isDetectionScan(int sockfd, const struct sockaddr *addr, uint16_t port) {
    // Must be JB port
    if (!isJBPort(port)) return NO;

    // Must be localhost - detection checks local services
    if (!isLocalhost(addr)) return NO;

    // Check socket timeout - detection scans use short timeouts (1-2s)
    struct timeval tv;
    socklen_t len = sizeof(tv);
    if (getsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, &tv, &len) == 0) {
        // Timeout is set and ≤ 3 seconds = likely detection scan
        if (tv.tv_sec > 0 && tv.tv_sec <= 3) {
            logMsg("isDetectionScan: port %u, timeout %lds = SCAN", port, (long)tv.tv_sec);
            return YES;
        }
    }

    // No timeout set or long timeout = real connection, allow it
    return NO;
}

// ponytail: SMART connect() hook - only block detection scans, allow real connections
static int (*orig_connect)(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
static int hook_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (shouldBypass() && addr) {
        uint16_t port = 0;
        if (addr->sa_family == AF_INET) {
            port = ntohs(((const struct sockaddr_in *)addr)->sin_port);
        } else if (addr->sa_family == AF_INET6) {
            port = ntohs(((const struct sockaddr_in6 *)addr)->sin6_port);
        }

        // Only block if it looks like a detection scan
        if (port && isDetectionScan(sockfd, addr, port)) {
            logMsg("HOOK connect: BLOCKED detection scan on port %u", port);
            errno = ECONNREFUSED;
            return -1;
        }
    }
    return orig_connect(sockfd, addr, addrlen);
}

// ponytail: bind() - don't block, just let it work
// Blocking bind() breaks services that need to listen
static int (*orig_bind)(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
static int hook_bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    // ponytail: no blocking - bind is for servers, not detection
    return orig_bind(sockfd, addr, addrlen);
}

// ponytail: getpeername - only fake for detection scans (already connected sockets)
static int (*orig_getpeername)(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
static int hook_getpeername(int sockfd, struct sockaddr *addr, socklen_t *addrlen) {
    int ret = orig_getpeername(sockfd, addr, addrlen);
    // ponytail: don't interfere - if connection succeeded, let it work
    return ret;
}

// ponytail: getsockname - don't hide, let normal operation work
static int (*orig_getsockname)(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
static int hook_getsockname(int sockfd, struct sockaddr *addr, socklen_t *addrlen) {
    int ret = orig_getsockname(sockfd, addr, addrlen);
    // ponytail: don't interfere
    return ret;
}

// ponytail: dladdr() hook - return Foundation path for hooked ObjC methods
static int (*orig_dladdr)(const void *addr, Dl_info *info);
static int hook_dladdr(const void *addr, Dl_info *info) {
    int ret = orig_dladdr(addr, info);
    if (!shouldBypass() || ret == 0 || !info || !info->dli_fname) return ret;

    NSString *path = @(info->dli_fname);
    NSString *lower = path.lowercaseString;
    // If dladdr resolves to our bypass or any hook library, fake it to Foundation
    if ([lower containsString:@"beerusjbbypass"] ||
        [lower containsString:@"substrate"] ||
        [lower containsString:@"substitute"] ||
        [lower containsString:@"ellekit"] ||
        [lower containsString:@"libhooker"]) {
        logMsg("HOOK dladdr: FAKE %s -> Foundation", info->dli_fname);
        info->dli_fname = "/System/Library/Frameworks/Foundation.framework/Foundation";
        info->dli_sname = NULL;
        info->dli_saddr = NULL;
    }
    return ret;
}

// ponytail: statfs() hook - hide /Developer mount and make root appear read-only
static int (*orig_statfs)(const char *path, struct statfs *buf);
static int hook_statfs(const char *path, struct statfs *buf) {
    int ret = orig_statfs(path, buf);
    if (shouldBypass() && ret == 0 && path) {
        // Make root appear read-only (stock iOS behavior)
        if (strcmp(path, "/") == 0) {
            buf->f_flags |= MNT_RDONLY;
            logMsg("HOOK statfs: added MNT_RDONLY for /");
        }
        // Hide /Developer
        if (strcmp(path, "/Developer") == 0 || strncmp(path, "/Developer/", 11) == 0) {
            logMsg("HOOK statfs: BLOCKED %s", path);
            errno = ENOENT;
            return -1;
        }
    }
    return ret;
}

// ponytail: getmntinfo hook - filter JB-related mount points
static int (*orig_getmntinfo)(struct statfs **mntbufp, int flags);
static int hook_getmntinfo(struct statfs **mntbufp, int flags) {
    int count = orig_getmntinfo(mntbufp, flags);
    if (!shouldBypass() || count <= 0 || !mntbufp || !*mntbufp) return count;

    struct statfs *buf = *mntbufp;
    int write_idx = 0;
    for (int i = 0; i < count; i++) {
        NSString *mount = @(buf[i].f_mntonname);
        NSString *fstype = @(buf[i].f_fstypename);
        // Hide /Developer, /var/jb, /cores/binpack mounts
        if ([mount isEqualToString:@"/Developer"] ||
            [mount hasPrefix:@"/var/jb"] ||
            [mount hasPrefix:@"/cores/binpack"] ||
            [mount hasPrefix:@"/private/preboot"]) {
            logMsg("HOOK getmntinfo: HIDE %s (%s)", buf[i].f_mntonname, buf[i].f_fstypename);
            continue;
        }
        // Also hide suspicious hfs mounts (normally iOS uses apfs)
        if ([fstype isEqualToString:@"hfs"] && ![mount isEqualToString:@"/"]) {
            logMsg("HOOK getmntinfo: HIDE hfs mount %s", buf[i].f_mntonname);
            continue;
        }
        if (write_idx != i) buf[write_idx] = buf[i];
        write_idx++;
    }
    return write_idx;
}

// ponytail: getfsstat variant for mount enumeration
static int (*orig_getfsstat)(struct statfs *buf, int bufsize, int flags);
static int hook_getfsstat(struct statfs *buf, int bufsize, int flags) {
    int count = orig_getfsstat(buf, bufsize, flags);
    if (!shouldBypass() || count <= 0 || !buf) return count;

    int write_idx = 0;
    for (int i = 0; i < count; i++) {
        NSString *mount = @(buf[i].f_mntonname);
        NSString *fstype = @(buf[i].f_fstypename);
        if ([mount isEqualToString:@"/Developer"] ||
            [mount hasPrefix:@"/var/jb"] ||
            [mount hasPrefix:@"/cores/binpack"] ||
            ([fstype isEqualToString:@"hfs"] && ![mount isEqualToString:@"/"])) {
            logMsg("HOOK getfsstat: HIDE %s", buf[i].f_mntonname);
            continue;
        }
        if (write_idx != i) buf[write_idx] = buf[i];
        write_idx++;
    }
    return write_idx;
}

// ponytail: open variants that fishhook might miss - $NOCANCEL versions
static int (*orig_open_nocancel)(const char *path, int flags, ...);
static int hook_open_nocancel(const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode = (mode_t)va_arg(args, int);
        va_end(args);
    }
    if (shouldBypass() && path && isJBPath(path)) {
        logMsg("HOOK open$NOCANCEL: BLOCKED %s", path);
        errno = ENOENT;
        return -1;
    }
    if (orig_open_nocancel) return orig_open_nocancel(path, flags, mode);
    return orig_open(path, flags, mode);
}

static int (*orig_openat_nocancel)(int dirfd, const char *path, int flags, ...);
static int hook_openat_nocancel(int dirfd, const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode = (mode_t)va_arg(args, int);
        va_end(args);
    }
    if (shouldBypass() && path && isJBPath(path)) {
        logMsg("HOOK openat$NOCANCEL: BLOCKED %s", path);
        errno = ENOENT;
        return -1;
    }
    if (orig_openat_nocancel) return orig_openat_nocancel(dirfd, path, flags, mode);
    if (orig_openat) return orig_openat(dirfd, path, flags, mode);
    return -1;
}

// dyld
static uint32_t (*orig_dyld_image_count)(void);
static const char* (*orig_dyld_get_image_name)(uint32_t idx);

static uint32_t g_filtered_count = 0;
static uint32_t *g_index_map = NULL;

static BOOL isDyldImageJB(const char *name) {
    if (!name) return NO;
    NSString *path = @(name);
    NSString *lower = path.lowercaseString;

    // ponytail: path prefixes for JB dylib locations
    if ([lower hasPrefix:@"/var/jb"] ||
        [lower hasPrefix:@"/cores/binpack"] ||
        [lower hasPrefix:@"/private/preboot"] ||
        [lower hasPrefix:@"/usr/lib/tweakinject"]) {
        return YES;
    }

    // ponytail: use shared substring set
    for (NSString *sub in g_jb_name_substrings) {
        if ([lower containsString:sub]) return YES;
    }
    return NO;
}

static void buildDyldIndexMap(void) {
    if (g_index_map) return;

    uint32_t real_count = orig_dyld_image_count();
    g_index_map = (uint32_t *)malloc(real_count * sizeof(uint32_t));
    g_filtered_count = 0;

    for (uint32_t i = 0; i < real_count; i++) {
        const char *name = orig_dyld_get_image_name(i);
        if (!isDyldImageJB(name)) {
            g_index_map[g_filtered_count++] = i;
        } else {
            logMsg("HOOK dyld: HIDE image %s", name);
        }
    }
    logMsg("HOOK dyld: %u -> %u images", real_count, g_filtered_count);
}

static uint32_t hook_dyld_image_count(void) {
    if (!shouldBypass()) return orig_dyld_image_count();
    buildDyldIndexMap();
    return g_filtered_count > STOCK_IOS_MAX_DYLD_IMAGES ? STOCK_IOS_MAX_DYLD_IMAGES : g_filtered_count;
}

static const char* hook_dyld_get_image_name(uint32_t idx) {
    if (!shouldBypass()) return orig_dyld_get_image_name(idx);
    buildDyldIndexMap();
    if (idx >= g_filtered_count) return NULL;
    return orig_dyld_get_image_name(g_index_map[idx]);
}

// ponytail: _dyld_get_image_header - alternate dyld enumeration method
static const struct mach_header* (*orig_dyld_get_image_header)(uint32_t idx);
static const struct mach_header* hook_dyld_get_image_header(uint32_t idx) {
    if (!shouldBypass()) return orig_dyld_get_image_header(idx);
    buildDyldIndexMap();
    if (idx >= g_filtered_count) return NULL;
    return orig_dyld_get_image_header(g_index_map[idx]);
}

// ponytail: _dyld_get_image_vmaddr_slide - ASLR slide per image
static intptr_t (*orig_dyld_get_image_vmaddr_slide)(uint32_t idx);
static intptr_t hook_dyld_get_image_vmaddr_slide(uint32_t idx) {
    if (!shouldBypass()) return orig_dyld_get_image_vmaddr_slide(idx);
    buildDyldIndexMap();
    if (idx >= g_filtered_count) return 0;
    return orig_dyld_get_image_vmaddr_slide(g_index_map[idx]);
}

// ponytail: dlopen - detectors probe for JB dylibs existence via dlopen()
static void* (*orig_dlopen)(const char *path, int mode);
static void* hook_dlopen(const char *path, int mode) {
    if (shouldBypass() && path && isDyldImageJB(path)) {
        logMsg("HOOK dlopen: BLOCKED %s", path);
        return NULL;
    }
    return orig_dlopen(path, mode);
}

#pragma mark - ObjC method swizzling

static IMP orig_fileExistsAtPath = NULL;
static IMP orig_fileExistsAtPathIsDirectory = NULL;
static IMP orig_contentsOfDirectoryAtPath = NULL;
static IMP orig_contentsAtPath = NULL;
static IMP orig_attributesOfItemAtPath = NULL;
static IMP orig_canOpenURL = NULL;

static BOOL swizzled_fileExistsAtPath(id self, SEL _cmd, NSString *path) {
    if (shouldBypass() && path && isJBPath(path.UTF8String)) {
        logMsg("HOOK fileExistsAtPath: BLOCKED %s", path.UTF8String);
        return NO;
    }
    return ((BOOL (*)(id, SEL, NSString *))orig_fileExistsAtPath)(self, _cmd, path);
}

static BOOL swizzled_fileExistsAtPathIsDirectory(id self, SEL _cmd, NSString *path, BOOL *isDir) {
    if (shouldBypass() && path && isJBPath(path.UTF8String)) {
        logMsg("HOOK fileExistsAtPath:isDirectory: BLOCKED %s", path.UTF8String);
        return NO;
    }
    return ((BOOL (*)(id, SEL, NSString *, BOOL *))orig_fileExistsAtPathIsDirectory)(self, _cmd, path, isDir);
}

static NSArray* swizzled_contentsOfDirectoryAtPath(id self, SEL _cmd, NSString *path, NSError **error) {
    NSArray *contents = ((NSArray* (*)(id, SEL, NSString *, NSError **))orig_contentsOfDirectoryAtPath)(self, _cmd, path, error);
    if (!shouldBypass() || !contents) return contents;

    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:contents.count];
    for (NSString *name in contents) {
        if (isJBName(name)) {
            logMsg("HOOK contentsOfDirectory: HIDE %s in %s", name.UTF8String, path.UTF8String);
        } else {
            [filtered addObject:name];
        }
    }
    return filtered;
}

// ponytail: contentsAtPath - THE main missing hook for /etc/passwd reads
static NSData* swizzled_contentsAtPath(id self, SEL _cmd, NSString *path) {
    if (shouldBypass() && path && isJBPath(path.UTF8String)) {
        logMsg("HOOK contentsAtPath: BLOCKED %s", path.UTF8String);
        return nil;
    }
    return ((NSData* (*)(id, SEL, NSString *))orig_contentsAtPath)(self, _cmd, path);
}

// ponytail: attributesOfItemAtPath can reveal file existence
static NSDictionary* swizzled_attributesOfItemAtPath(id self, SEL _cmd, NSString *path, NSError **error) {
    if (shouldBypass() && path && isJBPath(path.UTF8String)) {
        logMsg("HOOK attributesOfItemAtPath: BLOCKED %s", path.UTF8String);
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:nil];
        return nil;
    }
    return ((NSDictionary* (*)(id, SEL, NSString *, NSError **))orig_attributesOfItemAtPath)(self, _cmd, path, error);
}

static BOOL swizzled_canOpenURL(id self, SEL _cmd, NSURL *url) {
    if (shouldBypass() && url.scheme) {
        if ([g_jb_schemes containsObject:url.scheme.lowercaseString]) {
            logMsg("HOOK canOpenURL: BLOCKED %s", url.absoluteString.UTF8String);
            return NO;
        }
    }
    return ((BOOL (*)(id, SEL, NSURL *))orig_canOpenURL)(self, _cmd, url);
}

// ponytail: block ALL writes outside app sandbox - stock iOS behavior
static IMP orig_createFile = NULL;
static BOOL swizzled_createFile(id self, SEL _cmd, NSString *path, NSData *data, NSDictionary *attr) {
    if (shouldBypass() && path && !isInSandbox(path.UTF8String)) {
        logMsg("HOOK createFile: BLOCKED sandbox escape %s", path.UTF8String);
        return NO;
    }
    return ((BOOL (*)(id, SEL, NSString *, NSData *, NSDictionary *))orig_createFile)(self, _cmd, path, data, attr);
}

// Also hook writeToFile for NSData
static IMP orig_writeToFile = NULL;
static BOOL swizzled_writeToFile(id self, SEL _cmd, NSString *path, BOOL atomically) {
    if (shouldBypass() && path && !isInSandbox(path.UTF8String)) {
        logMsg("HOOK writeToFile: BLOCKED sandbox escape %s", path.UTF8String);
        return NO;
    }
    return ((BOOL (*)(id, SEL, NSString *, BOOL))orig_writeToFile)(self, _cmd, path, atomically);
}

// ponytail: NSData file reading - detectors use these to read /etc/passwd
static IMP orig_dataWithContentsOfFile = NULL;
static NSData* swizzled_dataWithContentsOfFile(id self, SEL _cmd, NSString *path) {
    if (shouldBypass() && path && isJBPath(path.UTF8String)) {
        logMsg("HOOK dataWithContentsOfFile: BLOCKED %s", path.UTF8String);
        return nil;
    }
    return ((NSData* (*)(id, SEL, NSString *))orig_dataWithContentsOfFile)(self, _cmd, path);
}

static IMP orig_dataWithContentsOfFileOptions = NULL;
static NSData* swizzled_dataWithContentsOfFileOptions(id self, SEL _cmd, NSString *path, NSDataReadingOptions opts, NSError **error) {
    if (shouldBypass() && path && isJBPath(path.UTF8String)) {
        logMsg("HOOK dataWithContentsOfFile:options: BLOCKED %s", path.UTF8String);
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:nil];
        return nil;
    }
    return ((NSData* (*)(id, SEL, NSString *, NSDataReadingOptions, NSError **))orig_dataWithContentsOfFileOptions)(self, _cmd, path, opts, error);
}

static IMP orig_initWithContentsOfFile = NULL;
static id swizzled_initWithContentsOfFile(id self, SEL _cmd, NSString *path) {
    if (shouldBypass() && path && isJBPath(path.UTF8String)) {
        logMsg("HOOK initWithContentsOfFile: BLOCKED %s", path.UTF8String);
        return nil;
    }
    return ((id (*)(id, SEL, NSString *))orig_initWithContentsOfFile)(self, _cmd, path);
}

// ponytail: NSString file reading
static IMP orig_stringWithContentsOfFile = NULL;
static NSString* swizzled_stringWithContentsOfFile(id self, SEL _cmd, NSString *path, NSStringEncoding enc, NSError **error) {
    if (shouldBypass() && path && isJBPath(path.UTF8String)) {
        logMsg("HOOK stringWithContentsOfFile: BLOCKED %s", path.UTF8String);
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:nil];
        return nil;
    }
    return ((NSString* (*)(id, SEL, NSString *, NSStringEncoding, NSError **))orig_stringWithContentsOfFile)(self, _cmd, path, enc, error);
}

static IMP orig_initStringWithContentsOfFile = NULL;
static id swizzled_initStringWithContentsOfFile(id self, SEL _cmd, NSString *path, NSStringEncoding enc, NSError **error) {
    if (shouldBypass() && path && isJBPath(path.UTF8String)) {
        logMsg("HOOK initWithContentsOfFile:encoding: BLOCKED %s", path.UTF8String);
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:nil];
        return nil;
    }
    return ((id (*)(id, SEL, NSString *, NSStringEncoding, NSError **))orig_initStringWithContentsOfFile)(self, _cmd, path, enc, error);
}

// ponytail: NSFileHandle - another common file reading API
static IMP orig_fileHandleForReadingAtPath = NULL;
static NSFileHandle* swizzled_fileHandleForReadingAtPath(id self, SEL _cmd, NSString *path) {
    if (shouldBypass() && path && isJBPath(path.UTF8String)) {
        logMsg("HOOK fileHandleForReadingAtPath: BLOCKED %s", path.UTF8String);
        return nil;
    }
    return ((NSFileHandle* (*)(id, SEL, NSString *))orig_fileHandleForReadingAtPath)(self, _cmd, path);
}

static IMP orig_fileHandleForReadingFromURL = NULL;
static NSFileHandle* swizzled_fileHandleForReadingFromURL(id self, SEL _cmd, NSURL *url, NSError **error) {
    if (shouldBypass() && url.isFileURL && isJBPath(url.path.UTF8String)) {
        logMsg("HOOK fileHandleForReadingFromURL: BLOCKED %s", url.path.UTF8String);
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:nil];
        return nil;
    }
    return ((NSFileHandle* (*)(id, SEL, NSURL *, NSError **))orig_fileHandleForReadingFromURL)(self, _cmd, url, error);
}

static IMP orig_initForReadingAtPath = NULL;
static id swizzled_initForReadingAtPath(id self, SEL _cmd, NSString *path) {
    if (shouldBypass() && path && isJBPath(path.UTF8String)) {
        logMsg("HOOK initForReadingAtPath: BLOCKED %s", path.UTF8String);
        return nil;
    }
    return ((id (*)(id, SEL, NSString *))orig_initForReadingAtPath)(self, _cmd, path);
}

// ponytail: URL-based reading - file:// URLs can read local files
static IMP orig_dataWithContentsOfURL = NULL;
static NSData* swizzled_dataWithContentsOfURL(id self, SEL _cmd, NSURL *url) {
    if (shouldBypass() && url.isFileURL && isJBPath(url.path.UTF8String)) {
        logMsg("HOOK dataWithContentsOfURL: BLOCKED %s", url.path.UTF8String);
        return nil;
    }
    return ((NSData* (*)(id, SEL, NSURL *))orig_dataWithContentsOfURL)(self, _cmd, url);
}

static IMP orig_dataWithContentsOfURLOptions = NULL;
static NSData* swizzled_dataWithContentsOfURLOptions(id self, SEL _cmd, NSURL *url, NSDataReadingOptions opts, NSError **error) {
    if (shouldBypass() && url.isFileURL && isJBPath(url.path.UTF8String)) {
        logMsg("HOOK dataWithContentsOfURL:options: BLOCKED %s", url.path.UTF8String);
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:nil];
        return nil;
    }
    return ((NSData* (*)(id, SEL, NSURL *, NSDataReadingOptions, NSError **))orig_dataWithContentsOfURLOptions)(self, _cmd, url, opts, error);
}

static IMP orig_stringWithContentsOfURL = NULL;
static NSString* swizzled_stringWithContentsOfURL(id self, SEL _cmd, NSURL *url, NSStringEncoding enc, NSError **error) {
    if (shouldBypass() && url.isFileURL && isJBPath(url.path.UTF8String)) {
        logMsg("HOOK stringWithContentsOfURL: BLOCKED %s", url.path.UTF8String);
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:nil];
        return nil;
    }
    return ((NSString* (*)(id, SEL, NSURL *, NSStringEncoding, NSError **))orig_stringWithContentsOfURL)(self, _cmd, url, enc, error);
}

// ponytail: NSInputStream - common file reading API that bypasses NSData/NSString hooks
static IMP orig_inputStreamWithFileAtPath = NULL;
static NSInputStream* swizzled_inputStreamWithFileAtPath(id self, SEL _cmd, NSString *path) {
    if (shouldBypass() && path && isJBPath(path.UTF8String)) {
        logMsg("HOOK inputStreamWithFileAtPath: BLOCKED %s", path.UTF8String);
        return nil;
    }
    return ((NSInputStream* (*)(id, SEL, NSString *))orig_inputStreamWithFileAtPath)(self, _cmd, path);
}

static IMP orig_inputStreamWithURL = NULL;
static NSInputStream* swizzled_inputStreamWithURL(id self, SEL _cmd, NSURL *url) {
    if (shouldBypass() && url.isFileURL && isJBPath(url.path.UTF8String)) {
        logMsg("HOOK inputStreamWithURL: BLOCKED %s", url.path.UTF8String);
        return nil;
    }
    return ((NSInputStream* (*)(id, SEL, NSURL *))orig_inputStreamWithURL)(self, _cmd, url);
}

static IMP orig_initInputStreamWithFileAtPath = NULL;
static id swizzled_initInputStreamWithFileAtPath(id self, SEL _cmd, NSString *path) {
    if (shouldBypass() && path && isJBPath(path.UTF8String)) {
        logMsg("HOOK initWithFileAtPath (NSInputStream): BLOCKED %s", path.UTF8String);
        return nil;
    }
    return ((id (*)(id, SEL, NSString *))orig_initInputStreamWithFileAtPath)(self, _cmd, path);
}

static IMP orig_initInputStreamWithURL = NULL;
static id swizzled_initInputStreamWithURL(id self, SEL _cmd, NSURL *url) {
    if (shouldBypass() && url.isFileURL && isJBPath(url.path.UTF8String)) {
        logMsg("HOOK initWithURL (NSInputStream): BLOCKED %s", url.path.UTF8String);
        return nil;
    }
    return ((id (*)(id, SEL, NSURL *))orig_initInputStreamWithURL)(self, _cmd, url);
}

// ponytail: NSBundle.bundlePath - hide sideload install paths (TrollStore, AltStore, etc)
static IMP orig_bundlePath = NULL;
static NSString* swizzled_bundlePath(id self, SEL _cmd) {
    NSString *realPath = ((NSString* (*)(id, SEL))orig_bundlePath)(self, _cmd);
    if (!shouldBypass() || self != [NSBundle mainBundle]) return realPath;

    // If already in stock location, return as-is
    if ([realPath hasPrefix:@"/var/containers/Bundle/Application/"] ||
        [realPath hasPrefix:@"/private/var/containers/Bundle/Application/"]) {
        return realPath;
    }

    // Fake a standard App Store path using stable UUID from bundle ID
    NSString *appName = realPath.lastPathComponent;
    if (!appName.length) appName = @"App.app";

    // ponytail: deterministic fake UUID from bundle ID hash
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"com.unknown.app";
    unsigned long hash = 5381;
    for (NSUInteger i = 0; i < bundleID.length; i++) {
        hash = ((hash << 5) + hash) + [bundleID characterAtIndex:i];
    }
    NSString *fakeUUID = [NSString stringWithFormat:@"%08lX-%04lX-%04lX-%04lX-%012lX",
                          (hash & 0xFFFFFFFF),
                          ((hash >> 16) & 0xFFFF),
                          ((hash >> 8) & 0xFFFF),
                          (hash & 0xFFFF),
                          (hash ^ 0xDEADBEEF)];

    NSString *fakePath = [NSString stringWithFormat:@"/var/containers/Bundle/Application/%@/%@",
                          fakeUUID, appName];
    logMsg("HOOK bundlePath: %s -> %s", realPath.UTF8String, fakePath.UTF8String);
    return fakePath;
}

// ponytail: NSProcessInfo.environment - bypasses getenv hook, returns full dict
static IMP orig_processInfoEnvironment = NULL;
static NSDictionary* swizzled_processInfoEnvironment(id self, SEL _cmd) {
    NSDictionary *env = ((NSDictionary* (*)(id, SEL))orig_processInfoEnvironment)(self, _cmd);
    if (!shouldBypass() || !env) return env;

    // ponytail: filter out DYLD_* and substrate env vars
    NSMutableDictionary *filtered = [env mutableCopy];
    NSArray *keysToRemove = @[
        @"DYLD_INSERT_LIBRARIES", @"DYLD_LIBRARY_PATH", @"DYLD_FRAMEWORK_PATH",
        @"DYLD_FALLBACK_LIBRARY_PATH", @"DYLD_IMAGE_SUFFIX", @"DYLD_PRINT_LIBRARIES",
        @"_MSSafeMode", @"SUBSTRATE_LIBRARY_PATH"
    ];
    for (NSString *key in keysToRemove) {
        if (filtered[key]) {
            logMsg("HOOK environment: HIDE %s", key.UTF8String);
            [filtered removeObjectForKey:key];
        }
    }
    return filtered;
}

static void swizzleMethod(Class cls, SEL sel, IMP newImp, IMP *origImp) {
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) {
        logMsg("swizzle FAILED: method not found for %s", sel_getName(sel));
        return;
    }

    *origImp = method_getImplementation(method);
    method_setImplementation(method, newImp);
    logMsg("swizzle OK: %s", sel_getName(sel));
}

#pragma mark - Init helpers

static void initPathSets(void) {
    // Initialize path sets - comprehensive JB path detection
    g_jb_paths = [NSSet setWithObjects:
            // Rootless jailbreak paths
            @"/var/jb", @"/private/var/jb",
            // Legacy/rootful paths
            @"/var/containers/Bundle/iosbinpack64",
            @"/var/LIB", @"/var/ulb", @"/var/bin",
            @"/var/stash", @"/private/var/stash",
            @"/cores/binpack",
            // Package managers
            @"/Applications/Cydia.app", @"/Applications/Sileo.app",
            @"/Applications/Zebra.app", @"/Applications/Filza.app",
            @"/Applications/FlyJB.app",
            @"/var/jb/Applications/Cydia.app", @"/var/jb/Applications/Sileo.app",
            @"/var/jb/Applications/Zebra.app", @"/var/jb/Applications/Filza.app",
            // ponytail: additional JB apps
            @"/Applications/blackra1n.app", @"/Applications/FakeCarrier.app",
            @"/Applications/Icy.app", @"/Applications/IntelliScreen.app",
            @"/Applications/MxTube.app", @"/Applications/RockApp.app",
            @"/Applications/SBSettings.app", @"/Applications/WinterBoard.app",
            @"/Applications/Loader.app", @"/Applications/HideJB.app",
            @"/Applications/Snoop-itConfig.app", @"/Applications/palera1n.app",
            @"/Applications/flex3.app", @"/Applications/crackerxi.app",
            @"/Applications/LibertyLite.app", @"/Applications/excon.app",
            @"/Applications/Backgrounder.app", @"/Applications/Terminal.app",
            @"/Applications/Pirni.app", @"/Applications/iFile.app",
            @"/Applications/Liberty.app", @"/Applications/biteSMS.app",
            // Jailbreak markers
            @"/.installed_unc0ver", @"/.bootstrapped_electra",
            @"/.installed_dopamine", @"/.installed_palera1n",
            @"/var/jb/.installed_dopamine", @"/var/jb/.installed_palera1n",
            @"/.cydia_no_stash", @"/.file", @"/.mount_rw", @"/.bootstrapped",
            @"/pguntether", @"/private/jailbreak.txt",
            // Frida/Cycript
            @"/usr/sbin/frida-server", @"/var/jb/usr/sbin/frida-server",
            @"/usr/bin/cycript", @"/var/jb/usr/bin/cycript",
            @"/usr/local/bin/cycript",
            @"/usr/lib/frida", @"/usr/lib/frida/frida-agent.dylib",
            // Substrate/hooking frameworks
            @"/Library/MobileSubstrate",
            @"/Library/MobileSubstrate/MobileSubstrate.dylib",
            @"/Library/MobileSubstrate/CydiaSubstrate.dylib",
            @"/Library/MobileSubstrate/HideJB.dylib",
            @"/var/jb/Library/MobileSubstrate",
            @"/Library/Frameworks/CydiaSubstrate.framework",
            @"/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
            @"/var/jb/Library/Frameworks/CydiaSubstrate.framework",
            @"/Library/Frameworks/Shadow.framework/Shadow",
            @"/Library/Frameworks/HookKit.framework/HookKit",
            @"/Library/Frameworks/RootBridge.framework/RootBridge",
            @"/Library/Frameworks/Modulous.framework/Modulous",
            @"/usr/lib/libjailbreak.dylib", @"/var/jb/usr/lib/libjailbreak.dylib",
            @"/usr/lib/substrate", @"/usr/lib/substrate/SubstrateInserter.dylib",
            @"/usr/lib/substrate/SubstrateLoader.dylib",
            @"/usr/lib/substrate/SubstrateBootstrap.dylib",
            @"/usr/lib/tweakloader.dylib", @"/usr/lib/libsubstrate.dylib",
            @"/usr/lib/libcycript.dylib", @"/usr/lib/libapt-inst.dylib",
            @"/usr/lib/libmryipc.dylib", @"/usr/lib/libsandy.dylib",
            @"/usr/lib/libsparkapplist.dylib",
            @"/usr/lib/Cephei.framework/Cephei",
            @"/usr/lib/CepheiUI.framework/CepheiUI",
            @"/usr/lib/cycript0.9/", @"/usr/lib/apt",
            // APT/dpkg
            @"/etc/apt", @"/var/jb/etc/apt", @"/private/etc/apt",
            @"/var/lib/dpkg", @"/var/lib/dpkg/",
            @"/var/jb/var/lib/dpkg",
            @"/private/var/lib/apt", @"/private/var/lib/cydia",
            @"/var/lib/apt", @"/var/lib/cydia",
            @"/Library/dpkg/info/re.frida.server.list",
            @"/Library/dpkg/info/kjc.checkra1n.mobilesubstraterepo.list",
            // LaunchDaemons
            @"/Library/LaunchDaemons/com.openssh.sshd.plist",
            @"/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist",
            @"/Library/LaunchDaemons/re.frida.server.plist",
            @"/Library/LaunchDaemons/dhpdaemon.plist",
            @"/Library/LaunchDaemons/ai.akemi.asu_inject.plist",
            @"/Library/LaunchDaemons/com.rpetrich.rocketbootstrapd.plist",
            @"/Library/LaunchDaemons/com.tigisoftware.filza.helper.plist",
            @"/Library/LaunchDaemons/dropbear.plist",
            @"/System/Library/LaunchDaemons/com.ikey.bbot.plist",
            @"/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist",
            @"/System/Library/LaunchDaemons/com.bigboss.sbsettingsd.plist",
            // PreferenceBundles
            @"/Library/PreferenceBundles/ABypassPrefs.bundle",
            @"/Library/PreferenceBundles/FlyJBPrefs.bundle",
            @"/Library/PreferenceBundles/HideJBPrefs.bundle",
            @"/Library/PreferenceBundles/LibertyPref.bundle",
            @"/Library/PreferenceBundles/SubstitutePrefs.bundle",
            @"/Library/PreferenceBundles/libhbangprefs.bundle",
            @"/Library/PreferenceLoader/Preferences/SubstituteSettings.plist",
            // Shadow rulesets
            @"/Library/Shadow/Rulesets", @"/Library/Shadow/Rulesets/StandardRules.plist",
            @"/Library/Shadow/Rulesets/JailbreakMisc.plist",
            @"/Library/Shadow/Rulesets/dpkgInstalled.plist",
            @"/Library/Modulous/HookKit", @"/Library/Modulous/HookKit/HookKitSubstrateModule.bundle",
            @"/Library/Activator", @"/Library/Flipswitch",
            // SBSettings (legacy)
            @"/var/mobile/Library/SBSettings",
            @"/var/mobile/Library/SBSettingsThemes/",
            @"/private/var/mobileLibrary/SBSettingsThemes",
            @"/User/Library/SBSettings",
            // Shell/SSH/bin
            @"/bin/bash", @"/var/jb/bin/bash",
            @"/bin/sh", @"/bin/su", @"/bin/mv", @"/boot",
            @"/usr/bin/ssh", @"/var/jb/usr/bin/ssh",
            @"/usr/bin/sshd", @"/var/jb/usr/bin/sshd",
            @"/usr/bin/ssh-agent", @"/usr/bin/ssh-keygen",
            @"/usr/bin/ssh-add", @"/usr/bin/ssh-keyscan",
            @"/usr/bin/sftp", @"/usr/bin/scp",
            @"/usr/bin/sinject", @"/usr/bin/sbsettingsd",
            @"/usr/sbin/sshd", @"/var/jb/usr/sbin/sshd",
            @"/usr/libexec/sftp-server", @"/usr/libexec/ssh-keysign",
            @"/usr/libexec/sshd-keygen-wrapper",
            @"/usr/libexec/cydia", @"/usr/libexec/cydia/firmware.sh",
            @"/usr/libexec/substrated", @"/usr/libexec/substituted",
            @"/usr/libexec/filza/Filza", @"/usr/libexec/sinject-vpa",
            @"/usr/libexec/substrate",
            @"/usr/arm-apple-darwin9", @"/usr/include/substrate.h",
            // Cydia data
            @"/private/var/mobile/Library/Cydia",
            @"/var/mobile/Library/Cydia",
            @"/var/mobile/Library/Cydia/",
            @"/private/var/mobile/Library/Cydia/",
            @"/var/mobile/Library/Caches/com.saurik.Cydia/sources.list",
            @"/Cydia/Substrate",
            // Filza
            @"/var/mobile/Library/Filza/",
            @"/var/mobile/Library/Filza/pasteboard.plist",
            @"/private/var/mobile/Library/Filza/",
            @"/private/var/mobile/Library/Filza/pasteboard.plist",
            // Preference files
            @"/var/mobile/Library/Preferences/com.ex.substitute.plist",
            @"/var/mobile/Library/Preferences/com.rpgfarm.abypassprefs.plist",
            @"/private/var/mobile/Library/Preferences/com.ex.substitute.plist",
            @"/private/var/mobile/Library/Preferences/com.nablac0d3.SSLKillSwitchSettings.plist",
            // Var paths
            @"/var/checkra1n.dmg", @"/var/palera1n.dmg",
            @"/var/tmp/cydia.log", @"/var/cache/apt",
            @"/var/cache/clutch.plist", @"/var/cache/clutch_cracked.plist",
            @"/var/log/syslog", @"/var/log/apt", @"/var/binpack",
            @"/var/db/stash", @"/var/dropbear_rsa_host_key",
            @"/var/evasi0n", @"/var/mobile/Media/.evasi0n7_installed",
            @"/var/lib/dpkg/info/mobilesubstrate.dylib",
            @"/var/lib/dpkg/info/mobileterminal.postinst",
            @"/var/lib/dpkg/info/mobileterminal.list",
            @"/var/lib/dpkg/info/cydia.list",
            @"/var/lib/dpkg/info/cydia-sources.list",
            @"/var/lib/clutch/overdrive.dylib",
            @"/var/root/.bash_history",
            @"/var/root/Documents/Cracked/",
            // Private var paths
            @"/private/var/log/syslog", @"/private/var/cache/apt",
            @"/private/var/cache/clutch.plist", @"/private/var/cache/clutch_cracked.plist",
            @"/private/var/evasi0n", @"/private/var/Users",
            @"/private/var/root/Media/Cydia", @"/private/var/root/Documents/Cracked/",
            @"/private/var/db/stash", @"/private/var/lib/dpkg/",
            @"/private/var/lib/dpkg/info/cydia-sources.list",
            @"/private/var/lib/dpkg/info/cydia.list",
            // Private etc paths
            @"/private/etc/ssh/sshd_config", @"/private/etc/profile.d/terminal.sh",
            @"/private/etc/apt/sources.list.d/sileo.sources",
            @"/private/etc/apt/sources.list.d/procursus.sources",
            @"/private/etc/apt/preferences.d/cydia",
            @"/private/etc/apt/preferences.d/checkra1n",
            @"/private/etc/dpkg/origins/debian",
            @"/private/etc/clutch_cracked.plist", @"/private/etc/clutch.conf",
            @"/private/etc/alternatives/sh", @"/private/etc/rc.d/substitute-launcher",
            // Etc paths
            @"/etc/ssh/sshd_config", @"/etc/apt/preferences.d/checkra1n",
            @"/etc/apt/undecimus/undecimus.list",
            @"/etc/apt/sources.list.d/cydia.list",
            @"/etc/alternatives/sh", @"/etc/profile.d/terminal.sh",
            @"/etc/clutch.conf", @"/etc/clutch_cracked.plist",
            // System paths
            @"/System/Library/PreferenceBundles/CydiaSettings.bundle",
            // ponytail: additional paths from JBDetector
            @"/jb",
            @"/electra",
            @"/chimera",
            @"/Developer",
            // Archive additions - DynamicLibraries
            @"/Library/MobileSubstrate/DynamicLibraries/0Shadow.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/Shadow.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/Shadow.plist",
            @"/Library/MobileSubstrate/DynamicLibraries/Choicy.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/Choicy.plist",
            @"/Library/MobileSubstrate/DynamicLibraries/ChoicySB.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/AppSyncUnified-FrontBoard.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/AppSyncUnified-installd.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/RocketBootstrap.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/MobileSafety.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/MobileSafety.plist",
            @"/Library/MobileSubstrate/DynamicLibraries/PreferenceLoader.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/LiveClock.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/SBSettings.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/SBSettings.plist",
            @"/Library/MobileSubstrate/DynamicLibraries/SSLKillSwitch2.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/AAAInjectionFoundation.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/AAAInjectionFoundation.plist",
            @"/Library/MobileSubstrate/DynamicLibraries/!ABypass2.plist",
            @"/Library/MobileSubstrate/DynamicLibraries/Veency.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/afc2dService.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/afc2dSupport.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/cydiasubstrate.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/jjjj.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/libcolorpicker.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/libhdev.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/zzzzzLiberty.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries/zzzzzzzzzNotifyChroot.dylib",
            // Archive additions - Frameworks
            @"/Library/Frameworks/CydiaSubstrate.framework/Info.plist",
            @"/Library/Frameworks/CydiaSubstrate.framework/Headers/CydiaSubstrate.h",
            // Archive additions - usr/lib
            @"/usr/lib/FridaGadget.dylib",
            @"/usr/lib/pspawn_hook.dylib",
            @"/usr/lib/rocketbootstrap_stubs.dylib",
            @"/usr/lib/libblackjack.dylib",
            @"/usr/lib/libcycript.0.dylib",
            @"/usr/lib/libffi.dylib",
            @"/usr/lib/libresolv.9.dylib",
            @"/usr/lib/libsubstitute.0.dylib",
            @"/usr/lib/libsubstrate.0.dylib",
            @"/usr/lib/substitute-inserter.dylib",
            @"/usr/lib/substitute-loader.dylib",
            // Archive additions - var paths
            @"/var/MobileSoftwareUpdate/mnt1",
            @"/var/mobile/Library/Preferences/0Shadow.plist",
            @"/var/mobile/Library/Preferences/com.creaturecoding.shadow.plist",
            @"/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist",
            // Archive additions - misc
            @"/Applications/Lite.app",
            @"/Applications/SBSetttings.app",
            @"/Applications/exconflex3.app",
            @"/private/etc/apt/trusted.gpg.d",
            @"/private/etc/dpkg",
            @"/private/var/tmp/frida",
            @"/System/Library/LaunchDaemons/com.saurik.Cy@dia.Startup.plist",
            @"/Systetem/Library/LaunchDaemons/com.ikey.bbot.plist",
            @"/bin.sh",
            nil];

        // ponytail: all schemes from JBDetector + extras
        g_jb_schemes = [NSSet setWithObjects:
            @"cydia", @"sileo", @"zebra", @"zbra", @"filza",
            @"undecimus", @"odyssey", @"electra", @"chimera",
            @"checkra1n", @"taurine", @"palera1n", @"dopamine",
            @"activator", @"unc0ver", @"jailbreak",
            nil];

        // ponytail: expanded substrings + dyld keywords from JBDetector (NSSet for O(1) containsObject)
        g_jb_substrings = [NSSet setWithObjects:
                           @"substrate", @"substitute", @"frida", @"cycript",
                           @"libhooker", @"ellekit", @"jailbreak", @"cydia",
                           @"sileo", @"zebra", @"tweakinject", @"pspawn",
                           @"systemhook", @"dopamine", @"palera1n",
                           @"liveclock", @"veency", @"protectmyprivacy",
                           @"weeloader", @"xcon", @"afc2d", @"shadow",
                           @"rocketbootstrap", @"overdrive", @"zorro",
                           @"choicy", @"appsyncunified", @"mrybootstrap",
                           @"sparkapplist", @"sslkillswitch", @"crane",
                           @"heibaolib", @"mobilesafety", @"sbsettings",
                           @"liberty", @"hidejb", @"abypass", @"flyjb", nil];

        // ponytail: shared set for dir/dyld name filtering (superset of g_jb_substrings + extras)
        g_jb_name_substrings = [NSSet setWithObjects:
                                @"substrate", @"substitute", @"frida", @"cycript",
                                @"libhooker", @"ellekit", @"jailbreak", @"cydia",
                                @"sileo", @"zebra", @"tweakinject", @"pspawn",
                                @"systemhook", @"dopamine", @"palera1n", @"procursus",
                                @"beerusjbbypass",
                                @"liveclock", @"veency", @"protectmyprivacy",
                                @"weeloader", @"xcon", @"afc2d", @"shadow",
                                @"rocketbootstrap", @"overdrive", @"zorro",
                                @"choicy", @"appsyncunified", @"mrybootstrap",
                                @"sparkapplist", @"sslkillswitch", @"crane",
                                @"heibaolib", @"mobilesafety", @"sbsettings",
                                @"liberty", @"hidejb", @"abypass", @"flyjb", nil];

        // ponytail: all processes from JBDetector + rootless additions
        g_jb_procs = [NSSet setWithObjects:
            @"cydia", @"sileo", @"zebra", @"frida", @"cycript",
            @"substrate", @"substrated", @"substitute", @"jailbreakd", @"amfid",
            @"sshd", @"dropbear", @"launchd_jb", @"jbd", @"ellekit",
            @"libhooker", @"tweakinjectd", @"pspawn", @"systemhook",
            nil];
}

static void initCFunctionHooks(void) {
    logMsg("Rebinding symbols...");
    struct rebinding rebindings[] = {
            {"stat", (void *)hook_stat, (void **)&orig_stat},
            {"lstat", (void *)hook_lstat, (void **)&orig_lstat},
            {"stat64", (void *)hook_stat64, (void **)&orig_stat64},
            {"lstat64", (void *)hook_lstat64, (void **)&orig_lstat64},
            {"access", (void *)hook_access, (void **)&orig_access},
            {"faccessat", (void *)hook_faccessat, (void **)&orig_faccessat},
            {"fstatat", (void *)hook_fstatat, (void **)&orig_fstatat},
            {"fopen", (void *)hook_fopen, (void **)&orig_fopen},
            {"freopen", (void *)hook_freopen, (void **)&orig_freopen},
            {"open", (void *)hook_open, (void **)&orig_open},
            {"openat", (void *)hook_openat, (void **)&orig_openat},
            {"readlink", (void *)hook_readlink, (void **)&orig_readlink},
            {"readlinkat", (void *)hook_readlinkat, (void **)&orig_readlinkat},
            {"realpath", (void *)hook_realpath, (void **)&orig_realpath},
            {"readdir", (void *)hook_readdir, (void **)&orig_readdir},
            {"fork", (void *)hook_fork, (void **)&orig_fork},
            {"vfork", (void *)hook_vfork, (void **)&orig_vfork},
            {"popen", (void *)hook_popen, (void **)&orig_popen},
            {"system", (void *)hook_system, (void **)&orig_system},
            {"posix_spawn", (void *)hook_posix_spawn, (void **)&orig_posix_spawn},
            {"posix_spawnp", (void *)hook_posix_spawnp, (void **)&orig_posix_spawnp},
            {"getenv", (void *)hook_getenv, (void **)&orig_getenv},
            {"sysctl", (void *)hook_sysctl, (void **)&orig_sysctl},
            {"sysctlbyname", (void *)hook_sysctlbyname, (void **)&orig_sysctlbyname},
            {"_dyld_image_count", (void *)hook_dyld_image_count, (void **)&orig_dyld_image_count},
            {"_dyld_get_image_name", (void *)hook_dyld_get_image_name, (void **)&orig_dyld_get_image_name},
            {"_dyld_get_image_header", (void *)hook_dyld_get_image_header, (void **)&orig_dyld_get_image_header},
            {"_dyld_get_image_vmaddr_slide", (void *)hook_dyld_get_image_vmaddr_slide, (void **)&orig_dyld_get_image_vmaddr_slide},
            {"dlsym", (void *)hook_dlsym, (void **)&orig_dlsym},
            {"dlopen", (void *)hook_dlopen, (void **)&orig_dlopen},
            // ponytail: ports, dladdr, mount detection
            {"connect", (void *)hook_connect, (void **)&orig_connect},
            {"bind", (void *)hook_bind, (void **)&orig_bind},
            {"getpeername", (void *)hook_getpeername, (void **)&orig_getpeername},
            {"getsockname", (void *)hook_getsockname, (void **)&orig_getsockname},
            {"dladdr", (void *)hook_dladdr, (void **)&orig_dladdr},
            {"statfs", (void *)hook_statfs, (void **)&orig_statfs},
            {"getmntinfo", (void *)hook_getmntinfo, (void **)&orig_getmntinfo},
            {"getfsstat", (void *)hook_getfsstat, (void **)&orig_getfsstat},
            {"syscall", (void *)hook_syscall, (void **)&orig_syscall},
            // ponytail: $NOCANCEL variants - detectors use these to bypass standard hooks
            {"fopen$NOCANCEL", (void *)hook_fopen_nocancel, (void **)&orig_fopen_nocancel},
            {"open$NOCANCEL", (void *)hook_open_nocancel, (void **)&orig_open_nocancel},
            {"openat$NOCANCEL", (void *)hook_openat_nocancel, (void **)&orig_openat_nocancel},
            // ponytail: anti-debug hooks
            {"ptrace", (void *)hook_ptrace, (void **)&orig_ptrace},
            // ponytail: code signature check
            {"csops", (void *)hook_csops, (void **)&orig_csops},
            // ponytail: Frida thread name hiding
            {"pthread_getname_np", (void *)hook_pthread_getname_np, (void **)&orig_pthread_getname_np},
            // ponytail: debugger environment detection
            {"isatty", (void *)hook_isatty, (void **)&orig_isatty},
            {"getppid", (void *)hook_getppid, (void **)&orig_getppid},
            // ponytail: exception port/class introspection
            {"task_get_exception_ports", (void *)hook_task_get_exception_ports, (void **)&orig_task_get_exception_ports},
            {"objc_getClass", (void *)hook_objc_getClass, (void **)&orig_objc_getClass},
            // ponytail: Frida memory signature scrubbing
            {"vm_read_overwrite", (void *)hook_vm_read_overwrite, (void **)&orig_vm_read_overwrite},
            {"mach_vm_read_overwrite", (void *)hook_mach_vm_read_overwrite, (void **)&orig_mach_vm_read_overwrite},
        };

        int result = rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
        if (result != 0) {
            logMsg("CRITICAL: rebind_symbols FAILED code %d - hooks may not work!", result);
        }
        logMsg("rebind_symbols: %d (0=OK)", result);

        // Log which hooks were bound
        logMsg("orig_stat = %p", (void*)orig_stat);
        logMsg("orig_fork = %p", (void*)orig_fork);
        logMsg("orig_access = %p", (void*)orig_access);
}

static void initObjCSwizzles(void) {
    logMsg("Swizzling ObjC methods...");
    swizzleMethod([NSFileManager class],
                     @selector(fileExistsAtPath:),
                     (IMP)swizzled_fileExistsAtPath,
                     &orig_fileExistsAtPath);

        swizzleMethod([NSFileManager class],
                     @selector(fileExistsAtPath:isDirectory:),
                     (IMP)swizzled_fileExistsAtPathIsDirectory,
                     &orig_fileExistsAtPathIsDirectory);

        swizzleMethod([NSFileManager class],
                     @selector(contentsOfDirectoryAtPath:error:),
                     (IMP)swizzled_contentsOfDirectoryAtPath,
                     &orig_contentsOfDirectoryAtPath);

        // ponytail: contentsAtPath is the primary /etc/passwd read vector
        swizzleMethod([NSFileManager class],
                     @selector(contentsAtPath:),
                     (IMP)swizzled_contentsAtPath,
                     &orig_contentsAtPath);

        swizzleMethod([NSFileManager class],
                     @selector(attributesOfItemAtPath:error:),
                     (IMP)swizzled_attributesOfItemAtPath,
                     &orig_attributesOfItemAtPath);

        swizzleMethod([UIApplication class],
                     @selector(canOpenURL:),
                     (IMP)swizzled_canOpenURL,
                     &orig_canOpenURL);

        // ponytail: block sandbox escape test
        swizzleMethod([NSFileManager class],
                     @selector(createFileAtPath:contents:attributes:),
                     (IMP)swizzled_createFile,
                     &orig_createFile);

        swizzleMethod([NSData class],
                     @selector(writeToFile:atomically:),
                     (IMP)swizzled_writeToFile,
                     &orig_writeToFile);

        // ponytail: NSData/NSString file reading - blocks /etc/passwd reads
        swizzleMethod(object_getClass([NSData class]),
                     @selector(dataWithContentsOfFile:),
                     (IMP)swizzled_dataWithContentsOfFile,
                     &orig_dataWithContentsOfFile);

        swizzleMethod(object_getClass([NSData class]),
                     @selector(dataWithContentsOfFile:options:error:),
                     (IMP)swizzled_dataWithContentsOfFileOptions,
                     &orig_dataWithContentsOfFileOptions);

        swizzleMethod([NSData class],
                     @selector(initWithContentsOfFile:),
                     (IMP)swizzled_initWithContentsOfFile,
                     &orig_initWithContentsOfFile);

        swizzleMethod(object_getClass([NSString class]),
                     @selector(stringWithContentsOfFile:encoding:error:),
                     (IMP)swizzled_stringWithContentsOfFile,
                     &orig_stringWithContentsOfFile);

        swizzleMethod([NSString class],
                     @selector(initWithContentsOfFile:encoding:error:),
                     (IMP)swizzled_initStringWithContentsOfFile,
                     &orig_initStringWithContentsOfFile);

        // ponytail: NSFileHandle file reading
        swizzleMethod(object_getClass([NSFileHandle class]),
                     @selector(fileHandleForReadingAtPath:),
                     (IMP)swizzled_fileHandleForReadingAtPath,
                     &orig_fileHandleForReadingAtPath);

        swizzleMethod(object_getClass([NSFileHandle class]),
                     @selector(fileHandleForReadingFromURL:error:),
                     (IMP)swizzled_fileHandleForReadingFromURL,
                     &orig_fileHandleForReadingFromURL);

        swizzleMethod([NSFileHandle class],
                     @selector(initForReadingAtPath:),
                     (IMP)swizzled_initForReadingAtPath,
                     &orig_initForReadingAtPath);

        // ponytail: URL-based file reading
        swizzleMethod(object_getClass([NSData class]),
                     @selector(dataWithContentsOfURL:),
                     (IMP)swizzled_dataWithContentsOfURL,
                     &orig_dataWithContentsOfURL);

        swizzleMethod(object_getClass([NSData class]),
                     @selector(dataWithContentsOfURL:options:error:),
                     (IMP)swizzled_dataWithContentsOfURLOptions,
                     &orig_dataWithContentsOfURLOptions);

        swizzleMethod(object_getClass([NSString class]),
                     @selector(stringWithContentsOfURL:encoding:error:),
                     (IMP)swizzled_stringWithContentsOfURL,
                     &orig_stringWithContentsOfURL);

        // ponytail: NSInputStream - catches file reads that bypass NSData/NSString
        swizzleMethod(object_getClass([NSInputStream class]),
                     @selector(inputStreamWithFileAtPath:),
                     (IMP)swizzled_inputStreamWithFileAtPath,
                     &orig_inputStreamWithFileAtPath);

        swizzleMethod(object_getClass([NSInputStream class]),
                     @selector(inputStreamWithURL:),
                     (IMP)swizzled_inputStreamWithURL,
                     &orig_inputStreamWithURL);

        swizzleMethod([NSInputStream class],
                     @selector(initWithFileAtPath:),
                     (IMP)swizzled_initInputStreamWithFileAtPath,
                     &orig_initInputStreamWithFileAtPath);

        swizzleMethod([NSInputStream class],
                     @selector(initWithURL:),
                     (IMP)swizzled_initInputStreamWithURL,
                     &orig_initInputStreamWithURL);

        // ponytail: NSBundle path spoofing for sideloaded apps
        swizzleMethod([NSBundle class],
                     @selector(bundlePath),
                     (IMP)swizzled_bundlePath,
                     &orig_bundlePath);

        // ponytail: NSProcessInfo.environment bypasses getenv hook
        swizzleMethod([NSProcessInfo class],
                     @selector(environment),
                     (IMP)swizzled_processInfoEnvironment,
                     &orig_processInfoEnvironment);
}

#pragma mark - Constructor

__attribute__((constructor))
static void BeerusJBBypassInit(void) {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
        logMsg("=== INIT START for %s ===", bundleID.UTF8String);

        // Check allowlist - apps here never get bypass (e.g., Beerus, Sileo, Filza)
        NSString *allowlist = [NSString stringWithContentsOfFile:@ALLOWLIST_PATH
                                                        encoding:NSUTF8StringEncoding
                                                           error:nil];
        if (allowlist) {
            logMsg("Allowlist: %s", allowlist.UTF8String);
            NSArray *allowed = [allowlist componentsSeparatedByCharactersInSet:
                               [NSCharacterSet newlineCharacterSet]];
            for (NSString *bid in allowed) {
                NSString *trimmed = [bid stringByTrimmingCharactersInSet:
                                    [NSCharacterSet whitespaceCharacterSet]];
                if ([trimmed isEqualToString:bundleID] || [trimmed isEqualToString:@"*"]) {
                    logMsg("EXIT: %s is in allowlist (no hooks installed)", bundleID.UTF8String);
                    g_in_allowlist = YES;
                    return;
                }
            }
        } else {
            logMsg("No allowlist file");
        }

        // ponytail: always install hooks - bypass state checked dynamically via toggle file
        initPathSets();
        initCFunctionHooks();
        initObjCSwizzles();

        // Initial toggle state check
        g_bypass_active = [[NSFileManager defaultManager] fileExistsAtPath:@BYPASS_TOGGLE];
        logMsg("Hooks installed, bypass %s (toggle checked dynamically)",
               g_bypass_active ? "ON" : "OFF");

        logMsg("=== INIT COMPLETE for %s ===", bundleID.UTF8String);
    }
}
