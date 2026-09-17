/* nvidia/cuda/p4_cuda.cu */
#include "p4_cuda.h"
#include <cuda_runtime.h>
#include <nvrtc.h>
#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <string>

struct p4_device_s  { int ordinal; cudaDeviceProp prop; char arch[64]; };
struct p4_buffer_s  { void* ptr; uint64_t bytes; p4_dtype dt; };
struct p4_kernel_s  { CUfunction fn; CUmodule mod; p4_kernel_id id; p4_dtype dt;
                      char entry[128]; uint64_t src_hash; };
struct p4_command_s { CUstream stream; p4_buffer bound[32]; uint32_t bound_n;
                      p4_kernel kernel; };
struct p4_event_s   { cudaEvent_t ev; };

static uint64_t fnv1a(const void* p, size_t n) {
    const uint8_t* b = (const uint8_t*)p; uint64_t h = 1469598103934665603ull;
    for (size_t i = 0; i < n; i++) { h ^= b[i]; h *= 1099511628211ull; }
    return h;
}

extern "C" p4_status p4_cuda_init(void) {
    return cudaFree(0) == cudaSuccess ? P4_OK : P4_ERR_STATE;
}
extern "C" p4_status p4_cuda_shutdown(void) { cudaDeviceReset(); return P4_OK; }

extern "C" p4_status p4_cuda_device_create(uint32_t index, p4_device* out) {
    int n = 0;
    if (cudaGetDeviceCount(&n) != cudaSuccess || (int)index >= n) return P4_ERR_NO_DEVICE;
    struct p4_device_s* h = (struct p4_device_s*)calloc(1, sizeof(*h));
    h->ordinal = (int)index;
    cudaGetDeviceProperties(&h->prop, h->ordinal);
    snprintf(h->arch, sizeof(h->arch), "sm_%d%d", h->prop.major, h->prop.minor);
    *out = h;
    return P4_OK;
}

extern "C" p4_status p4_cuda_device_architecture(p4_device dev, const char** out_name) {
    if (!dev || !out_name) return P4_ERR_INVALID_ARG;
    *out_name = dev->arch;
    return P4_OK;
}

extern "C" p4_status p4_cuda_device_capabilities(p4_device dev, p4_capabilities* out) {
    if (!dev || !out) return P4_ERR_INVALID_ARG;
    memset(out, 0, sizeof(*out));
    out->name = dev->prop.name;
    out->backend = P4_BACKEND_NVIDIA_CUDA;
    out->max_threads_per_block = (uint32_t)dev->prop.maxThreadsPerBlock;
    out->max_threads_per_grid_dim[0] = dev->prop.maxGridSize[0];
    out->max_threads_per_grid_dim[1] = dev->prop.maxGridSize[1];
    out->max_threads_per_grid_dim[2] = dev->prop.maxGridSize[2];
    out->warp_or_simd_width = (uint32_t)dev->prop.warpSize;
    out->shared_memory_bytes = dev->prop.sharedMemPerBlock;
    out->global_memory_bytes  = dev->prop.totalGlobalMem;
    out->tensor_alignment = 256;
    out->max_registers_per_thread = dev->prop.regsPerBlock / dev->prop.maxThreadsPerBlock;
    out->supports_f16 = (dev->prop.major >= 5);
    out->supports_bf16 = (dev->prop.major >= 8);
    out->supports_f64 = (dev->prop.major >= 2);
    out->unified_memory = (dev->prop.unifiedAddressing != 0) ? 1 : 0;
    out->synchronization_model =
        "CUDA streams; __syncthreads() within block; grid sync via cooperative groups";
    return P4_OK;
}

extern "C" p4_status p4_cuda_device_destroy(p4_device dev) {
    if (!dev) return P4_ERR_INVALID_ARG;
    free(dev); return P4_OK;
}

extern "C" p4_status p4_cuda_buffer_create(p4_device dev, uint64_t bytes, p4_dtype dt, p4_buffer* out) {
    if (!dev || !out || !bytes) return P4_ERR_INVALID_ARG;
    cudaSetDevice(dev->ordinal);
    void* p = nullptr;
    if (cudaMalloc(&p, bytes) != cudaSuccess) return P4_ERR_OOM;
    struct p4_buffer_s* h = (struct p4_buffer_s*)calloc(1, sizeof(*h));
    h->ptr = p; h->bytes = bytes; h->dt = dt;
    *out = h;
    return P4_OK;
}

extern "C" p4_status p4_cuda_buffer_upload(p4_buffer buf, const void* src, uint64_t bytes, uint64_t offset) {
    if (!buf || !src || offset + bytes > buf->bytes) return P4_ERR_INVALID_ARG;
    if (cudaMemcpy((uint8_t*)buf->ptr + offset, src, bytes, cudaMemcpyHostToDevice) != cudaSuccess)
        return P4_ERR_DISPATCH;
    return P4_OK;
}

extern "C" p4_status p4_cuda_buffer_read(p4_buffer buf, void* dst, uint64_t bytes, uint64_t offset) {
    if (!buf || !dst || offset + bytes > buf->bytes) return P4_ERR_INVALID_ARG;
    if (cudaMemcpy(dst, (uint8_t*)buf->ptr + offset, bytes, cudaMemcpyDeviceToHost) != cudaSuccess)
        return P4_ERR_DISPATCH;
    return P4_OK;
}

extern "C" p4_status p4_cuda_buffer_destroy(p4_buffer buf) {
    if (!buf) return P4_ERR_INVALID_ARG;
    cudaFree(buf->ptr); free(buf); return P4_OK;
}

extern "C" p4_status p4_cuda_pipeline_create(p4_device dev, p4_kernel_id id, p4_dtype dt,
                                             const char* source, const char* entry_point,
                                             p4_kernel* out) {
    if (!dev || !source || !entry_point || !out) return P4_ERR_INVALID_ARG;
    cudaSetDevice(dev->ordinal);

    nvrtcProgram prog;
    if (nvrtcCreateProgram(&prog, source, "p4_kernel.cu", 0, nullptr, nullptr) != NVRTC_SUCCESS)
        return P4_ERR_COMPILE;

    char arch_opt[32];
    snprintf(arch_opt, sizeof(arch_opt), "--gpu-architecture=compute_%d%d",
             dev->prop.major, dev->prop.minor);
    const char* opts[] = { arch_opt, "--std=c++17", "-default-device" };
    nvrtcResult cr = nvrtcCompileProgram(prog, 3, opts);
    if (cr != NVRTC_SUCCESS) {
        size_t log_sz; nvrtcGetProgramLogSize(prog, &log_sz);
        std::string log(log_sz, '\0'); nvrtcGetProgramLog(prog, &log[0]);
        fprintf(stderr, "P4 NVRTC error:\n%s\n", log.c_str());
        nvrtcDestroyProgram(&prog);
        return P4_ERR_COMPILE;
    }
    size_t ptx_sz; nvrtcGetPTXSize(prog, &ptx_sz);
    std::string ptx(ptx_sz, '\0'); nvrtcGetPTX(prog, &ptx[0]);
    nvrtcDestroyProgram(&prog);

    CUmodule mod; CUfunction fn;
    if (cuModuleLoadData(&mod, ptx.c_str()) != CUDA_SUCCESS) return P4_ERR_COMPILE;
    if (cuModuleGetFunction(&fn, mod, entry_point) != CUDA_SUCCESS) return P4_ERR_NOT_FOUND;

    struct p4_kernel_s* h = (struct p4_kernel_s*)calloc(1, sizeof(*h));
    h->fn = fn; h->mod = mod; h->id = id; h->dt = dt;
    snprintf(h->entry, sizeof(h->entry), "%s", entry_point);
    h->src_hash = fnv1a(source, strlen(source));
    *out = h;
    return P4_OK;
}

extern "C" p4_status p4_cuda_pipeline_destroy(p4_kernel k) {
    if (!k) return P4_ERR_INVALID_ARG;
    cuModuleUnload(k->mod); free(k); return P4_OK;
}

extern "C" p4_status p4_cuda_command_buffer_create(p4_device dev, p4_command* out) {
    if (!dev || !out) return P4_ERR_INVALID_ARG;
    struct p4_command_s* h = (struct p4_command_s*)calloc(1, sizeof(*h));
    cudaSetDevice(dev->ordinal);
    if (cudaStreamCreate(&h->stream) != cudaSuccess) { free(h); return P4_ERR_STATE; }
    *out = h;
    return P4_OK;
}

extern "C" p4_status p4_cuda_dispatch(p4_command cmd, p4_kernel k,
                                      const p4_extent3* grid, const p4_extent3* block,
                                      uint32_t shared_bytes) {
    if (!cmd || !k || !grid || !block) return P4_ERR_INVALID_ARG;
    void* args[32] = {0};
    for (uint32_t i = 0; i < cmd->bound_n; i++) {
        args[i] = &cmd->bound[i]->ptr;
    }
    CUresult r = cuLaunchKernel(k->fn,
        grid->x, grid->y, grid->z,
        block->x, block->y, block->z,
        shared_bytes, cmd->stream, args, nullptr);
    return r == CUDA_SUCCESS ? P4_OK : P4_ERR_DISPATCH;
}

extern "C" p4_status p4_cuda_commit(p4_command cmd, p4_event* out_evt) {
    if (!cmd) return P4_ERR_INVALID_ARG;
    if (out_evt) {
        struct p4_event_s* e = (struct p4_event_s*)calloc(1, sizeof(*e));
        cudaEventCreateWithFlags(&e->ev, cudaEventDisableTiming);
        cudaEventRecord(e->ev, cmd->stream);
        *out_evt = e;
    }
    return P4_OK;
}

extern "C" p4_status p4_cuda_wait(p4_event evt, uint64_t timeout_ns) {
    if (!evt) return P4_ERR_INVALID_ARG;
    (void)timeout_ns;
    return cudaEventSynchronize(evt->ev) == cudaSuccess ? P4_OK : P4_ERR_STATE;
}

extern "C" p4_status p4_cuda_destroy(p4_command cmd) {
    if (!cmd) return P4_ERR_INVALID_ARG;
    cudaStreamDestroy(cmd->stream); free(cmd); return P4_OK;
}
