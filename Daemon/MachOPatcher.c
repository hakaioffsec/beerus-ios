#include "MachOPatcher.h"
#include <stdio.h>

// ponytail: stub implementations - JB bypass uses different approach now
int patch_binary(const char *binary_path, const char *dylib_path) {
    (void)binary_path;
    (void)dylib_path;
    fprintf(stderr, "patch_binary: not implemented\n");
    return -1;
}

int unpatch_binary(const char *binary_path) {
    (void)binary_path;
    fprintf(stderr, "unpatch_binary: not implemented\n");
    return -1;
}

int resign_binary(const char *binary_path, int rootless) {
    (void)binary_path;
    (void)rootless;
    fprintf(stderr, "resign_binary: not implemented\n");
    return -1;
}
