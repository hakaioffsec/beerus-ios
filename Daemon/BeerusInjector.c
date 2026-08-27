// BeerusInjector.c - Runtime dylib injection via mach APIs
// ponytail: Full implementation with ARM64 shellcode

#include "BeerusInjector.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <mach/thread_act.h>
#include <mach/arm/thread_status.h>
#include <mach-o/dyld_images.h>
#include <pthread.h>
#include <dispatch/dispatch.h>
#include <sys/sysctl.h>
#include <sys/stat.h>

#define PROC_PIDPATHINFO_MAXSIZE 4096
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

static int g_injector_ready = 0;
static char g_dylib_path[512] = {0};
static volatile int g_watcher_active = 0;

#define ALLOWLIST_PATH "/var/mobile/.beerus_jb_allowlist"

// ARM64 shellcode to call dlopen(path, RTLD_NOW)
// Registers on entry:
//   x0 = pointer to dylib path string
//   x1 = dlopen address
//
// Code:
//   mov x8, x1      ; save dlopen address
//   mov x1, #2      ; RTLD_NOW = 2
//   blr x8          ; call dlopen(x0, RTLD_NOW)
//   brk #0          ; trap to stop thread

static const uint32_t SHELLCODE[] = {
    0xaa0103e8,  // mov x8, x1
    0xd2800041,  // mov x1, #2 (RTLD_NOW)
    0xd63f0100,  // blr x8
    0xd4200000,  // brk #0
};
#define SHELLCODE_SIZE sizeof(SHELLCODE)

// Get our shared cache base address
static uint64_t get_local_cache_base(void) {
    struct task_dyld_info dyld_info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;

    if (task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&dyld_info, &count) != KERN_SUCCESS) {
        return 0;
    }

    // Read dyld_all_image_infos to get shared cache slide
    struct dyld_all_image_infos *infos = (struct dyld_all_image_infos *)dyld_info.all_image_info_addr;
    if (!infos) return 0;

    // sharedCacheBaseAddress is the actual base (slide already applied)
    return (uint64_t)infos->sharedCacheBaseAddress;
}

// Get target process shared cache base via reading its dyld_all_image_infos
static uint64_t get_remote_cache_base(task_t task) {
    struct task_dyld_info dyld_info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;

    if (task_info(task, TASK_DYLD_INFO, (task_info_t)&dyld_info, &count) != KERN_SUCCESS) {
        fprintf(stderr, "injector: task_info(TASK_DYLD_INFO) failed\n");
        return 0;
    }

    // Read dyld_all_image_infos from target
    struct dyld_all_image_infos remote_infos;
    vm_size_t out_size = sizeof(remote_infos);

    kern_return_t kr = vm_read_overwrite(task, dyld_info.all_image_info_addr,
                                          sizeof(remote_infos),
                                          (vm_address_t)&remote_infos, &out_size);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "injector: vm_read dyld_all_image_infos failed: %s\n", mach_error_string(kr));
        return 0;
    }

    return (uint64_t)remote_infos.sharedCacheBaseAddress;
}

// Get dlopen address in target process
// ponytail: dlopen is in shared cache, calculate offset from our cache base and apply to target's
static uint64_t get_remote_dlopen_addr(task_t task) {
    void *local_dlopen = dlsym(RTLD_DEFAULT, "dlopen");
    if (!local_dlopen) {
        fprintf(stderr, "injector: cannot find local dlopen\n");
        return 0;
    }

    uint64_t local_base = get_local_cache_base();
    if (local_base == 0) {
        fprintf(stderr, "injector: cannot get local cache base\n");
        return 0;
    }

    uint64_t remote_base = get_remote_cache_base(task);
    if (remote_base == 0) {
        fprintf(stderr, "injector: cannot get remote cache base\n");
        return 0;
    }

    // Calculate offset and apply to remote base
    uint64_t offset = (uint64_t)local_dlopen - local_base;
    uint64_t remote_dlopen = remote_base + offset;

    fprintf(stderr, "injector: local_dlopen=%p local_base=0x%llx remote_base=0x%llx offset=0x%llx remote_dlopen=0x%llx\n",
            local_dlopen, local_base, remote_base, offset, remote_dlopen);

    return remote_dlopen;
}

// Get dlopen address - local, for init check only
static void* get_dlopen_addr(void) {
    return dlsym(RTLD_DEFAULT, "dlopen");
}

static int is_allowed_bundle(const char *bundle_id) {
    if (!bundle_id) return 0;

    FILE *f = fopen(ALLOWLIST_PATH, "r");
    if (!f) return 0;

    char line[256];
    while (fgets(line, sizeof(line), f)) {
        line[strcspn(line, "\n")] = 0;
        if (strlen(line) == 0) continue;
        if (strcmp(line, bundle_id) == 0 || strcmp(line, "*") == 0) {
            fclose(f);
            return 1;
        }
    }
    fclose(f);
    return 0;
}

static int get_bundle_id(pid_t pid, char *out, size_t out_size) {
    char path[PROC_PIDPATHINFO_MAXSIZE];
    if (proc_pidpath(pid, path, sizeof(path)) <= 0) return -1;

    char *app = strstr(path, ".app/");
    if (!app) return -1;
    app[4] = '\0';

    char plist_path[PROC_PIDPATHINFO_MAXSIZE + 32];
    snprintf(plist_path, sizeof(plist_path), "%s/Info.plist", path);

    char cmd[PROC_PIDPATHINFO_MAXSIZE + 128];
    snprintf(cmd, sizeof(cmd), "defaults read '%s' CFBundleIdentifier 2>/dev/null", plist_path);

    FILE *p = popen(cmd, "r");
    if (!p) return -1;

    if (fgets(out, out_size, p) != NULL) {
        out[strcspn(out, "\n")] = 0;
        pclose(p);
        return 0;
    }
    pclose(p);
    return -1;
}

int injector_init(void) {
    // Verify we can use mach APIs
    task_t self_task = mach_task_self();
    if (self_task == MACH_PORT_NULL) {
        fprintf(stderr, "injector: cannot get self task\n");
        return -1;
    }

    // Check dlopen is available
    if (!get_dlopen_addr()) {
        fprintf(stderr, "injector: cannot find dlopen\n");
        return -1;
    }

    g_injector_ready = 1;
    fprintf(stderr, "injector: initialized, dlopen=%p\n", get_dlopen_addr());
    return 0;
}

int injector_inject(pid_t pid, const char *dylib_path) {
    if (!g_injector_ready) {
        if (injector_init() != 0) return -1;
    }
    if (!dylib_path || strlen(dylib_path) == 0) return -1;

    kern_return_t kr;
    task_t target_task = MACH_PORT_NULL;
    thread_act_t remote_thread = MACH_PORT_NULL;
    vm_address_t remote_code = 0;
    vm_address_t remote_stack = 0;
    vm_address_t remote_path = 0;
    int ret = -1;

    // Get task port
    kr = task_for_pid(mach_task_self(), pid, &target_task);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "injector: task_for_pid(%d) failed: %s\n", pid, mach_error_string(kr));
        return -1;
    }
    fprintf(stderr, "injector: got task port for pid %d\n", pid);

    // Allocate memory for dylib path
    vm_size_t path_len = strlen(dylib_path) + 1;
    kr = vm_allocate(target_task, &remote_path, path_len, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "injector: vm_allocate(path) failed: %s\n", mach_error_string(kr));
        goto cleanup;
    }

    // Write dylib path
    kr = vm_write(target_task, remote_path, (vm_offset_t)dylib_path, (mach_msg_type_number_t)path_len);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "injector: vm_write(path) failed: %s\n", mach_error_string(kr));
        goto cleanup;
    }
    fprintf(stderr, "injector: wrote dylib path at 0x%lx\n", (unsigned long)remote_path);

    // Allocate stack (64KB, 16-byte aligned)
    vm_size_t stack_size = 0x10000;
    kr = vm_allocate(target_task, &remote_stack, stack_size, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "injector: vm_allocate(stack) failed: %s\n", mach_error_string(kr));
        goto cleanup;
    }
    kr = vm_protect(target_task, remote_stack, stack_size, FALSE, VM_PROT_READ | VM_PROT_WRITE);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "injector: vm_protect(stack) failed: %s\n", mach_error_string(kr));
        goto cleanup;
    }
    fprintf(stderr, "injector: allocated stack at 0x%lx\n", (unsigned long)remote_stack);

    // Allocate memory for shellcode
    kr = vm_allocate(target_task, &remote_code, SHELLCODE_SIZE, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "injector: vm_allocate(code) failed: %s\n", mach_error_string(kr));
        goto cleanup;
    }

    // Write shellcode
    kr = vm_write(target_task, remote_code, (vm_offset_t)SHELLCODE, SHELLCODE_SIZE);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "injector: vm_write(code) failed: %s\n", mach_error_string(kr));
        goto cleanup;
    }

    // Make shellcode executable
    kr = vm_protect(target_task, remote_code, SHELLCODE_SIZE, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "injector: vm_protect(code) failed: %s\n", mach_error_string(kr));
        goto cleanup;
    }
    fprintf(stderr, "injector: wrote shellcode at 0x%lx\n", (unsigned long)remote_code);

    // Get dlopen address in TARGET process (not ours!)
    uint64_t remote_dlopen = get_remote_dlopen_addr(target_task);
    if (remote_dlopen == 0) {
        fprintf(stderr, "injector: cannot resolve remote dlopen\n");
        goto cleanup;
    }

    // Create remote thread with ARM64 state
    arm_thread_state64_t state;
    memset(&state, 0, sizeof(state));

    // Set registers
    // x0 = dylib path pointer
    // x1 = dlopen address (in TARGET's address space)
    // sp = stack top (stack grows down)
    // pc = shellcode address
    // lr = 0 (will trap on return anyway)

    state.__x[0] = remote_path;     // x0 = path
    state.__x[1] = remote_dlopen;   // x1 = dlopen in target's space
    state.__sp = remote_stack + stack_size - 16;   // sp = top of stack, aligned
    state.__pc = remote_code;                       // pc = shellcode
    state.__lr = 0;                                 // lr = 0
    state.__cpsr = 0;                               // cpsr = 0

    fprintf(stderr, "injector: creating thread x0=0x%llx x1=0x%llx sp=0x%llx pc=0x%llx\n",
            state.__x[0], state.__x[1], state.__sp, state.__pc);

    // Create the thread
    kr = thread_create_running(target_task, ARM_THREAD_STATE64,
                               (thread_state_t)&state,
                               ARM_THREAD_STATE64_COUNT,
                               &remote_thread);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "injector: thread_create_running failed: %s\n", mach_error_string(kr));
        goto cleanup;
    }
    fprintf(stderr, "injector: created remote thread\n");

    // Wait for thread to execute dlopen
    usleep(100000); // ponytail: 100ms should be enough for dlopen

    // Thread should have hit brk #0 and stopped
    // Terminate it
    thread_terminate(remote_thread);
    fprintf(stderr, "injector: terminated thread\n");

    ret = 0;
    fprintf(stderr, "injector: injection complete for pid %d\n", pid);

cleanup:
    // ponytail: Skip port deallocation - guarded ports on iOS 16+ can SIGKILL on dealloc
    // Leaking ports is acceptable since daemon is long-lived
    (void)remote_thread;
    (void)target_task;

    return ret;
}

int injector_is_loaded(pid_t pid, const char *dylib_path) {
    // TODO: Check if dylib already loaded via reading dyld info
    (void)pid;
    (void)dylib_path;
    return 0;
}

static void on_process_launch(pid_t pid) {
    if (!g_watcher_active) return;
    if (pid <= 100) return;

    char bundle_id[256] = {0};
    if (get_bundle_id(pid, bundle_id, sizeof(bundle_id)) != 0) {
        return;
    }

    if (is_allowed_bundle(bundle_id)) {
        fprintf(stderr, "injector: %s (pid %d) allowed, skip\n", bundle_id, pid);
        return;
    }

    if (injector_is_loaded(pid, g_dylib_path)) {
        return;
    }

    fprintf(stderr, "injector: injecting into %s (pid %d)\n", bundle_id, pid);

    // ponytail: inject IMMEDIATELY - no delay, must beat main()
    // usleep(200000); // REMOVED - was letting detection code run first

    if (injector_inject(pid, g_dylib_path) == 0) {
        fprintf(stderr, "injector: success %s\n", bundle_id);
    } else {
        fprintf(stderr, "injector: failed %s\n", bundle_id);
    }
}

// Simple process watcher using polling
// ponytail: kqueue EVFILT_PROC needs specific PIDs, polling is simpler for catching all
static void *watcher_thread(void *arg) {
    (void)arg;
    fprintf(stderr, "injector: watcher started\n");

    pid_t last_pids[1024] = {0};
    int last_count = 0;

    while (g_watcher_active) {
        // Get current process list
        int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
        size_t size = 0;

        if (sysctl(mib, 4, NULL, &size, NULL, 0) < 0) {
            sleep(1);
            continue;
        }

        struct kinfo_proc *procs = malloc(size);
        if (!procs) {
            sleep(1);
            continue;
        }

        if (sysctl(mib, 4, procs, &size, NULL, 0) < 0) {
            free(procs);
            sleep(1);
            continue;
        }

        int count = size / sizeof(struct kinfo_proc);

        // Find new processes
        for (int i = 0; i < count && i < 1024; i++) {
            pid_t pid = procs[i].kp_proc.p_pid;
            if (pid <= 100) continue;

            // Check if this is a new pid
            int found = 0;
            for (int j = 0; j < last_count; j++) {
                if (last_pids[j] == pid) {
                    found = 1;
                    break;
                }
            }

            if (!found) {
                // New process, try to inject
                on_process_launch(pid);
            }
        }

        // Update last seen pids
        last_count = 0;
        for (int i = 0; i < count && last_count < 1024; i++) {
            last_pids[last_count++] = procs[i].kp_proc.p_pid;
        }

        free(procs);
        usleep(50000); // ponytail: Poll every 50ms - must catch apps before main()
    }

    fprintf(stderr, "injector: watcher stopped\n");
    return NULL;
}

int injector_start_watcher(const char *dylib_path) {
    if (!g_injector_ready) {
        if (injector_init() != 0) return -1;
    }

    if (!dylib_path) return -1;
    strncpy(g_dylib_path, dylib_path, sizeof(g_dylib_path) - 1);

    struct stat st;
    if (stat(dylib_path, &st) != 0) {
        fprintf(stderr, "injector: dylib not found: %s\n", dylib_path);
        return -1;
    }

    g_watcher_active = 1;

    pthread_t tid;
    if (pthread_create(&tid, NULL, watcher_thread, NULL) != 0) {
        g_watcher_active = 0;
        return -1;
    }
    pthread_detach(tid);

    return 0;
}

void injector_stop_watcher(void) {
    g_watcher_active = 0;
}

int injector_inject_all(const char *dylib_path) {
    if (!g_injector_ready) {
        if (injector_init() != 0) return -1;
    }
    if (!dylib_path) return -1;

    struct stat st;
    if (stat(dylib_path, &st) != 0) {
        fprintf(stderr, "injector: dylib not found: %s\n", dylib_path);
        return -1;
    }

    // Get current process list
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size = 0;

    if (sysctl(mib, 4, NULL, &size, NULL, 0) < 0) return -1;

    struct kinfo_proc *procs = malloc(size);
    if (!procs) return -1;

    if (sysctl(mib, 4, procs, &size, NULL, 0) < 0) {
        free(procs);
        return -1;
    }

    int count = size / sizeof(struct kinfo_proc);
    int injected = 0;

    for (int i = 0; i < count; i++) {
        pid_t pid = procs[i].kp_proc.p_pid;
        if (pid <= 100) continue;  // skip system processes

        char bundle_id[256] = {0};
        if (get_bundle_id(pid, bundle_id, sizeof(bundle_id)) != 0) {
            continue;  // not an app
        }

        if (is_allowed_bundle(bundle_id)) {
            fprintf(stderr, "injector: skip allowed %s (pid %d)\n", bundle_id, pid);
            continue;
        }

        fprintf(stderr, "injector: injecting into %s (pid %d)\n", bundle_id, pid);
        if (injector_inject(pid, dylib_path) == 0) {
            injected++;
        }
    }

    free(procs);
    fprintf(stderr, "injector: inject_all complete, %d apps\n", injected);
    return injected;
}
