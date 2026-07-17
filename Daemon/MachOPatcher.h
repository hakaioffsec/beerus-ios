#ifndef MACHO_PATCHER_H
#define MACHO_PATCHER_H

// ponytail: stub for missing patcher implementation
int patch_binary(const char *binary_path, const char *dylib_path);
int unpatch_binary(const char *binary_path);
int resign_binary(const char *binary_path, int rootless);

#endif
