/* abi/types.h — P4 primitive types. No language-specific objects cross this line. */
#ifndef P4_TYPES_H
#define P4_TYPES_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    P4_OK                = 0,
    P4_ERR_INVALID_ARG   = -1,
    P4_ERR_NO_DEVICE     = -2,
    P4_ERR_OOM           = -3,
    P4_ERR_COMPILE       = -4,
    P4_ERR_DISPATCH      = -5,
    P4_ERR_UNSUPPORTED   = -6,
    P4_ERR_NO_FALLBACK   = -7,   /* P4-15: never silently fall back */
    P4_ERR_NOT_FOUND     = -8,
    P4_ERR_STATE         = -9,
    P4_ERR_NUMERICAL     = -10,
} p4_status;

typedef enum {
    P4_BACKEND_NONE           = 0,
    P4_BACKEND_APPLE_METAL    = 1,
    P4_BACKEND_NVIDIA_CUDA    = 2,
    P4_BACKEND_CPU_REFERENCE  = 3,
} p4_backend;

typedef enum {
    P4_DTYPE_UNKNOWN = 0,
    P4_DTYPE_F16     = 1,
    P4_DTYPE_BF16    = 2,
    P4_DTYPE_F32     = 3,
    P4_DTYPE_F64     = 4,
    P4_DTYPE_I8      = 5,
    P4_DTYPE_I32     = 6,
    P4_DTYPE_U32     = 7,
} p4_dtype;

typedef enum {
    P4_LAYOUT_ROW_MAJOR = 0,
    P4_LAYOUT_COL_MAJOR = 1,
} p4_layout;

typedef enum {
    P4_KERNEL_ORIGIN_MSL           = 1,
    P4_KERNEL_ORIGIN_CUDA          = 2,
    P4_KERNEL_ORIGIN_CPU_REFERENCE = 3,
} p4_kernel_origin;

/* Stable kernel identifiers — never renumber, only append. */
typedef enum {
    P4_K_VECTOR_ADD          = 0x0101,
    P4_K_VECTOR_MUL          = 0x0102,
    P4_K_MATRIX_MUL          = 0x0103,
    P4_K_REDUCTION           = 0x0104,
    P4_K_SOFTMAX             = 0x0105,
    P4_K_RMSNORM             = 0x0106,
    P4_K_LAYER_NORM          = 0x0107,
    P4_K_ROPE                = 0x0108,
    P4_K_SILU                = 0x0109,
    P4_K_SWIGLU              = 0x010A,
    P4_K_ATTENTION           = 0x010B,
    P4_K_GQA                 = 0x010C,
    P4_K_ELEMENTWISE_FUSION  = 0x010D,
    P4_K_TENSOR_COPY         = 0x010E,
} p4_kernel_id;

typedef struct { uint32_t x, y, z; } p4_extent3;

typedef struct {
    p4_extent3 grid;
    p4_extent3 block;
    uint32_t   shared_bytes;
    uint32_t   flags;         /* P4_LAUNCH_* */
} p4_launch;

#define P4_LAUNCH_F_NONE        0u
#define P4_LAUNCH_F_REQUIRE_F16 1u
#define P4_LAUNCH_F_STRICT_FP32 2u

typedef struct {
    const char* name;
    p4_backend  backend;
    uint32_t    max_threads_per_block;
    uint32_t    max_threads_per_grid_dim[3];
    uint32_t    warp_or_simd_width;
    uint64_t    shared_memory_bytes;
    uint64_t    global_memory_bytes;
    uint32_t    tensor_alignment;
    uint32_t    max_registers_per_thread;
    uint32_t    supports_f16;
    uint32_t    supports_bf16;
    uint32_t    supports_f64;
    uint32_t    unified_memory;
    const char* synchronization_model;
} p4_capabilities;

/* Opaque handles — never expose Objective-C, CUDA, or Mojo objects. */
typedef struct p4_device_s*  p4_device;
typedef struct p4_buffer_s*  p4_buffer;
typedef struct p4_kernel_s*  p4_kernel;
typedef struct p4_command_s* p4_command;
typedef struct p4_event_s*   p4_event;
typedef struct p4_tensor_s*  p4_tensor;

typedef struct {
    uint32_t kernel_id;
    const char* kernel_name;
    p4_backend  backend;
    const char* architecture;
    uint64_t    source_hash;     /* FNV-1a over source text */
    uint64_t    binary_hash;     /* FNV-1a over compiled artifact */
    p4_dtype    dtype;
    const char* input_signature;
    const char* output_signature;
    p4_launch   default_launch;
    uint32_t    version;
    p4_kernel_origin origin;
} p4_kernel_record;

typedef struct {
    double max_absolute_error;
    double max_relative_error;
    double mean_absolute_error;
    uint64_t nan_count;
    uint64_t inf_count;
} p4_error_report;

#ifdef __cplusplus
}
#endif
#endif /* P4_TYPES_H */
