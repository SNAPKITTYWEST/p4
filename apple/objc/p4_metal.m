/* apple/objc/p4_metal.m
   Direct Metal. No MPS. No MetalKit. Hand-rolled pipeline compile + dispatch. */
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#include "p4_metal.h"
#include <string.h>
#include <stdlib.h>

/* ---- internal state ------------------------------------------------------ */
struct p4_device_s  { __unsafe_unretained id<MTLDevice> dev;
                      __unsafe_unretained id<MTLCommandQueue> queue;
                      char arch[64]; };
struct p4_buffer_s  { __unsafe_unretained id<MTLBuffer> buf; uint64_t bytes; p4_dtype dt; };
struct p4_kernel_s  { __unsafe_unretained id<MTLComputePipelineState> pso;
                      p4_kernel_id id; p4_dtype dt; char entry[128]; uint64_t src_hash; };
struct p4_command_s { __unsafe_unretained id<MTLCommandBuffer> cb;
                      __unsafe_unretained id<MTLComputeCommandEncoder> enc;
                      p4_kernel bound_kernel;
                      p4_buffer bound[32]; uint32_t bound_count; };
struct p4_event_s   { __unsafe_unretained id<MTLCommandBuffer> cb; };

static uint64_t fnv1a(const void* p, size_t n) {
    const uint8_t* b = (const uint8_t*)p; uint64_t h = 1469598103934665603ull;
    for (size_t i = 0; i < n; i++) { h ^= b[i]; h *= 1099511628211ull; }
    return h;
}

p4_status p4_metal_init(void)   { @autoreleasepool { return P4_OK; } }
p4_status p4_metal_shutdown(void){ return P4_OK; }

p4_status p4_metal_device_create(uint32_t index, p4_device* out) {
    @autoreleasepool {
        NSArray<id<MTLDevice>>* all = MTLCopyAllDevices();
        if (index >= all.count) return P4_ERR_NO_DEVICE;
        id<MTLDevice> d = all[index];
        id<MTLCommandQueue> q = [d newCommandQueue];
        if (!q) return P4_ERR_STATE;

        struct p4_device_s* h = calloc(1, sizeof(*h));
        h->dev = d; h->queue = q;
        snprintf(h->arch, sizeof(h->arch), "%s", [[d name] UTF8String]);
        *out = h;
        return P4_OK;
    }
}

p4_status p4_metal_device_architecture(p4_device dev, const char** out_name) {
    if (!dev || !out_name) return P4_ERR_INVALID_ARG;
    *out_name = dev->arch;
    return P4_OK;
}

p4_status p4_metal_device_capabilities(p4_device dev, p4_capabilities* out) {
    if (!dev || !out) return P4_ERR_INVALID_ARG;
    id<MTLDevice> d = dev->dev;
    memset(out, 0, sizeof(*out));
    out->name = [[d name] UTF8String];
    out->backend = P4_BACKEND_APPLE_METAL;
    out->max_threads_per_block = (uint32_t)[d maxThreadsPerThreadgroup].width;
    out->max_threads_per_grid_dim[0] = (uint32_t)[d maxThreadsPerThreadgroup].width;
    out->max_threads_per_grid_dim[1] = (uint32_t)[d maxThreadsPerThreadgroup].height;
    out->max_threads_per_grid_dim[2] = (uint32_t)[d maxThreadsPerThreadgroup].depth;
    out->warp_or_simd_width = 32;
#if TARGET_OS_OSX
    out->shared_memory_bytes = [d maxThreadgroupMemoryLength];
    out->max_registers_per_thread = 0;
    out->unified_memory = 0;
#else
    out->shared_memory_bytes = [d maxThreadgroupMemoryLength];
    out->unified_memory = 1;
#endif
    out->global_memory_bytes = [d recommendedMaxWorkingSetSize];
    out->tensor_alignment = 256;
    out->supports_f16 = 1;
    out->supports_bf16 = 0;
    out->supports_f64 = 0;
    out->synchronization_model = "MTLCommandBuffer in-order commit; events via MTLSharedEvent";
    return P4_OK;
}

p4_status p4_metal_device_destroy(p4_device dev) {
    if (!dev) return P4_ERR_INVALID_ARG;
    dev->queue = nil; dev->dev = nil;
    free(dev);
    return P4_OK;
}

p4_status p4_metal_buffer_create(p4_device dev, uint64_t bytes, p4_dtype dt, p4_buffer* out) {
    if (!dev || !out || bytes == 0) return P4_ERR_INVALID_ARG;
    id<MTLBuffer> b = [dev->dev newBufferWithLength:bytes
                                           options:MTLResourceStorageModeShared];
    if (!b) return P4_ERR_OOM;
    struct p4_buffer_s* h = calloc(1, sizeof(*h));
    h->buf = b; h->bytes = bytes; h->dt = dt;
    *out = h;
    return P4_OK;
}

p4_status p4_metal_buffer_upload(p4_buffer buf, const void* src, uint64_t bytes, uint64_t offset) {
    if (!buf || !src || offset + bytes > buf->bytes) return P4_ERR_INVALID_ARG;
    memcpy((uint8_t*)[buf->buf contents] + offset, src, bytes);
    return P4_OK;
}

p4_status p4_metal_buffer_read(p4_buffer buf, void* dst, uint64_t bytes, uint64_t offset) {
    if (!buf || !dst || offset + bytes > buf->bytes) return P4_ERR_INVALID_ARG;
    memcpy(dst, (uint8_t*)[buf->buf contents] + offset, bytes);
    return P4_OK;
}

p4_status p4_metal_buffer_destroy(p4_buffer buf) {
    if (!buf) return P4_ERR_INVALID_ARG;
    buf->buf = nil; free(buf); return P4_OK;
}

p4_status p4_metal_pipeline_create(p4_device dev, p4_kernel_id id, p4_dtype dt,
                                   const char* source, const char* entry_point,
                                   p4_kernel* out) {
    if (!dev || !source || !entry_point || !out) return P4_ERR_INVALID_ARG;
    @autoreleasepool {
        NSError* err = nil;
        MTLCompileOptions* opts = [MTLCompileOptions new];
        opts.languageVersion = MTLLanguageVersion3_0;
        opts.fastMathEnabled = NO;
        id<MTLLibrary> lib = [dev->dev newLibraryWithSource:
                              [NSString stringWithUTF8String:source]
                                                   options:opts error:&err];
        if (!lib) {
            NSLog(@"P4 MSL compile error: %@", err);
            return P4_ERR_COMPILE;
        }
        id<MTLFunction> fn = [lib newFunctionWithName:
                              [NSString stringWithUTF8String:entry_point]];
        if (!fn) return P4_ERR_NOT_FOUND;

        id<MTLComputePipelineState> pso =
            [dev->dev newComputePipelineStateWithFunction:fn error:&err];
        if (!pso) return P4_ERR_COMPILE;

        struct p4_kernel_s* h = calloc(1, sizeof(*h));
        h->pso = pso; h->id = id; h->dt = dt;
        snprintf(h->entry, sizeof(h->entry), "%s", entry_point);
        h->src_hash = fnv1a(source, strlen(source));
        *out = h;
        return P4_OK;
    }
}

p4_status p4_metal_pipeline_destroy(p4_kernel k) {
    if (!k) return P4_ERR_INVALID_ARG;
    k->pso = nil; free(k); return P4_OK;
}

p4_status p4_metal_command_buffer_create(p4_device dev, p4_command* out) {
    if (!dev || !out) return P4_ERR_INVALID_ARG;
    id<MTLCommandBuffer> cb = [dev->queue commandBuffer];
    if (!cb) return P4_ERR_STATE;
    struct p4_command_s* h = calloc(1, sizeof(*h));
    h->cb = cb; h->enc = nil; h->bound_kernel = NULL; h->bound_count = 0;
    *out = h;
    return P4_OK;
}

p4_status p4_metal_dispatch(p4_command cmd, p4_kernel k,
                            const p4_extent3* grid, const p4_extent3* block,
                            uint32_t shared_bytes) {
    if (!cmd || !k || !grid || !block) return P4_ERR_INVALID_ARG;

    if (!cmd->enc) {
        cmd->enc = [cmd->cb computeCommandEncoder];
        if (!cmd->enc) return P4_ERR_STATE;
        for (uint32_t i = 0; i < cmd->bound_count; i++) {
            [cmd->enc setBuffer:cmd->bound[i]->buf offset:0 atIndex:i];
        }
    }
    if (cmd->bound_kernel != k) {
        [cmd->enc setComputePipelineState:k->pso];
        cmd->bound_kernel = k;
    }
    if (shared_bytes) {
        [cmd->enc setThreadgroupMemoryLength:shared_bytes atIndex:0];
    }
    [cmd->enc dispatchThreads:MTLSizeMake(grid->x, grid->y, grid->z)
        threadsPerThreadgroup:MTLSizeMake(block->x, block->y, block->z)];
    return P4_OK;
}

p4_status p4_metal_commit(p4_command cmd, p4_event* out_evt) {
    if (!cmd) return P4_ERR_INVALID_ARG;
    if (cmd->enc) { [cmd->enc endEncoding]; cmd->enc = nil; }
    [cmd->cb commit];
    if (out_evt) {
        struct p4_event_s* e = calloc(1, sizeof(*e));
        e->cb = cmd->cb;
        *out_evt = e;
    }
    return P4_OK;
}

p4_status p4_metal_wait(p4_event evt, uint64_t timeout_ns) {
    if (!evt) return P4_ERR_INVALID_ARG;
    [evt->cb waitUntilCompleted];
    if (evt->cb.status == MTLCommandBufferStatusError) return P4_ERR_DISPATCH;
    return P4_OK;
}

p4_status p4_metal_destroy(p4_command cmd) {
    if (!cmd) return P4_ERR_INVALID_ARG;
    if (cmd->enc) { [cmd->enc endEncoding]; cmd->enc = nil; }
    cmd->cb = nil; free(cmd); return P4_OK;
}
