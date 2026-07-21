// BeerusInjector.h - Runtime dylib injection using mach APIs
// Requires tfp0/libkrw for task_for_pid on arbitrary processes

#ifndef BEERUS_INJECTOR_H
#define BEERUS_INJECTOR_H

#include <stdint.h>
#include <sys/types.h>

// Initialize injector (call once at daemon startup)
// Returns 0 on success, -1 if tfp0 not available
int injector_init(void);

// Inject dylib into target process
// Returns 0 on success, negative on error
int injector_inject(pid_t pid, const char *dylib_path);

// Start watching for new app launches and auto-inject
// Uses notify_register for SpringBoard launch notifications
int injector_start_watcher(const char *dylib_path);

// Stop the watcher
void injector_stop_watcher(void);

// Check if process already has dylib loaded
int injector_is_loaded(pid_t pid, const char *dylib_path);

// Inject into all running non-allowlisted apps
// Returns count of successful injections, negative on error
int injector_inject_all(const char *dylib_path);

#endif // BEERUS_INJECTOR_H
