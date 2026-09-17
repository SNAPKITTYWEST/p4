/* abi/version.h — P4 version and ABI version. */
#ifndef P4_VERSION_H
#define P4_VERSION_H

#include <stdint.h>

#define P4_VERSION_MAJOR 0
#define P4_VERSION_MINOR 1
#define P4_VERSION_PATCH 0
#define P4_VERSION_STRING "0.1.0"
#define P4_ABI_VERSION 1

#ifdef __cplusplus
extern "C" {
#endif

const char* p4_version_string(void);
uint32_t p4_version_major(void);
uint32_t p4_version_minor(void);
uint32_t p4_version_patch(void);
uint32_t p4_abi_version(void);

#ifdef __cplusplus
}
#endif

#endif /* P4_VERSION_H */
