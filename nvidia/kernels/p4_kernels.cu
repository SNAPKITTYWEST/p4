/* nvidia/kernels/p4_kernels.cu — mirrors MSL signatures, same math contract. */
#include <cuda_runtime.h>
#include <math.h>

extern "C" __global__ void p4_vector_add_f32(const float* __restrict__ a,
                                             const float* __restrict__ b,
                                             float* __restrict__ y, unsigned n) {
    unsigned i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) y[i] = a[i] + b[i];
}

extern "C" __global__ void p4_vector_mul_f32(const float* __restrict__ a,
                                             const float* __restrict__ b,
                                             float* __restrict__ y, unsigned n) {
    unsigned i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) y[i] = a[i] * b[i];
}

#define P4_TILE 16
extern "C" __global__ void p4_matrix_mul_f32(const float* __restrict__ A,
                                             const float* __restrict__ B,
                                             float* __restrict__ C,
                                             unsigned M, unsigned N, unsigned K) {
    __shared__ float As[P4_TILE][P4_TILE];
    __shared__ float Bs[P4_TILE][P4_TILE];
    unsigned row = blockIdx.y * P4_TILE + threadIdx.y;
    unsigned col = blockIdx.x * P4_TILE + threadIdx.x;
    float acc = 0.f;
    for (unsigned k0 = 0; k0 < K; k0 += P4_TILE) {
        unsigned ar = row, ac = k0 + threadIdx.x;
        unsigned br = k0 + threadIdx.y, bc = col;
        As[threadIdx.y][threadIdx.x] = (ar < M && ac < K) ? A[ar * K + ac] : 0.f;
        Bs[threadIdx.y][threadIdx.x] = (br < K && bc < N) ? B[br * N + bc] : 0.f;
        __syncthreads();
        #pragma unroll
        for (int k = 0; k < P4_TILE; ++k) acc += As[threadIdx.y][k] * Bs[k][threadIdx.x];
        __syncthreads();
    }
    if (row < M && col < N) C[row * N + col] = acc;
}

extern "C" __global__ void p4_reduction_sum_f32(const float* __restrict__ x,
                                                float* __restrict__ out,
                                                unsigned len) {
    extern __shared__ float sh[];
    unsigned row = blockIdx.x;
    unsigned lid = threadIdx.x, lsz = blockDim.x;
    float acc = 0.f;
    for (unsigned i = lid; i < len; i += lsz) acc += x[row * len + i];
    sh[lid] = acc;
    __syncthreads();
    for (unsigned s = lsz >> 1; s > 0; s >>= 1) {
        if (lid < s) sh[lid] += sh[lid + s];
        __syncthreads();
    }
    if (lid == 0) out[row] = sh[0];
}

extern "C" __global__ void p4_softmax_f32(const float* __restrict__ x,
                                          float* __restrict__ y, unsigned cols) {
    extern __shared__ float sh[];
    unsigned row = blockIdx.x, lid = threadIdx.x, lsz = blockDim.x;
    const float* xr = x + (size_t)row * cols;
    float*       yr = y + (size_t)row * cols;
    float m = -INFINITY;
    for (unsigned i = lid; i < cols; i += lsz) m = fmaxf(m, xr[i]);
    sh[lid] = m; __syncthreads();
    for (unsigned s = lsz >> 1; s > 0; s >>= 1) {
        if (lid < s) sh[lid] = fmaxf(sh[lid], sh[lid + s]);
        __syncthreads();
    }
    m = sh[0];
    float sum = 0.f;
    for (unsigned i = lid; i < cols; i += lsz) sum += __expf(xr[i] - m);
    sh[lid] = sum; __syncthreads();
    for (unsigned s = lsz >> 1; s > 0; s >>= 1) {
        if (lid < s) sh[lid] += sh[lid + s];
        __syncthreads();
    }
    float inv = 1.f / sh[0];
    for (unsigned i = lid; i < cols; i += lsz) yr[i] = __expf(xr[i] - m) * inv;
}

extern "C" __global__ void p4_rmsnorm_f32(const float* __restrict__ x,
                                          const float* __restrict__ g,
                                          float* __restrict__ y,
                                          unsigned cols, float eps) {
    extern __shared__ float sh[];
    unsigned row = blockIdx.x, lid = threadIdx.x, lsz = blockDim.x;
    const float* xr = x + (size_t)row * cols;
    float*       yr = y + (size_t)row * cols;
    float ss = 0.f;
    for (unsigned i = lid; i < cols; i += lsz) ss += xr[i] * xr[i];
    sh[lid] = ss; __syncthreads();
    for (unsigned s = lsz >> 1; s > 0; s >>= 1) {
        if (lid < s) sh[lid] += sh[lid + s];
        __syncthreads();
    }
    float rms = rsqrtf(sh[0] / (float)cols + eps);
    for (unsigned i = lid; i < cols; i += lsz) yr[i] = xr[i] * rms * g[i];
}

extern "C" __global__ void p4_layer_norm_f32(const float* __restrict__ x,
                                             const float* __restrict__ g,
                                             const float* __restrict__ b,
                                             float* __restrict__ y,
                                             unsigned cols, float eps) {
    extern __shared__ float sh[];
    unsigned row = blockIdx.x, lid = threadIdx.x, lsz = blockDim.x;
    const float* xr = x + (size_t)row * cols;
    float*       yr = y + (size_t)row * cols;
    float s = 0.f;
    for (unsigned i = lid; i < cols; i += lsz) s += xr[i];
    sh[lid] = s; __syncthreads();
    for (unsigned k = lsz >> 1; k > 0; k >>= 1) {
        if (lid < k) sh[lid] += sh[lid + k];
        __syncthreads();
    }
    float mean = sh[0] / (float)cols;
    float v = 0.f;
    for (unsigned i = lid; i < cols; i += lsz) { float d = xr[i] - mean; v += d * d; }
    sh[lid] = v; __syncthreads();
    for (unsigned k = lsz >> 1; k > 0; k >>= 1) {
        if (lid < k) sh[lid] += sh[lid + k];
        __syncthreads();
    }
    float inv = rsqrtf(sh[0] / (float)cols + eps);
    for (unsigned i = lid; i < cols; i += lsz)
        yr[i] = (xr[i] - mean) * inv * g[i] + b[i];
}

extern "C" __global__ void p4_rope_f32(const float* __restrict__ x,
                                       const float* __restrict__ c,
                                       const float* __restrict__ s,
                                       float* __restrict__ y,
                                       unsigned head_dim, unsigned pos) {
    unsigned pair = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned row  = blockIdx.y;
    unsigned half = head_dim >> 1;
    if (pair >= half) return;
    size_t base = (size_t)row * head_dim;
    float x0 = x[base + 2 * pair], x1 = x[base + 2 * pair + 1];
    float cc = c[pos * half + pair], ss = s[pos * half + pair];
    y[base + 2 * pair]     = x0 * cc - x1 * ss;
    y[base + 2 * pair + 1] = x0 * ss + x1 * cc;
}

extern "C" __global__ void p4_silu_f32(const float* __restrict__ x,
                                       float* __restrict__ y, unsigned n) {
    unsigned i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) { float v = x[i]; y[i] = v / (1.f + __expf(-v)); }
}

extern "C" __global__ void p4_swiglu_f32(const float* __restrict__ g,
                                         const float* __restrict__ u,
                                         float* __restrict__ y, unsigned n) {
    unsigned i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) { float gv = g[i]; y[i] = (gv / (1.f + __expf(-gv))) * u[i]; }
}

extern "C" __global__ void p4_tensor_copy_f32(const float* __restrict__ s,
                                              float* __restrict__ d, unsigned n) {
    unsigned i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) d[i] = s[i];
}

extern "C" __global__ void p4_elementwise_fusion_f32(const float* __restrict__ a,
                                                     const float* __restrict__ b,
                                                     const float* __restrict__ c,
                                                     float* __restrict__ y,
                                                     unsigned n, unsigned op) {
    unsigned i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    float av = a[i], bv = b[i], cv = c[i];
    switch (op) {
        case 0: y[i] = fmaf(av, bv, cv); break;
        case 1: y[i] = fmaxf(fmaf(av, bv, cv), 0.f); break;
        case 2: y[i] = tanhf(fmaf(av, bv, cv)); break;
        default: y[i] = av + bv + cv;
    }
}
