/* apple/msl/p4_kernels.metal
   Hand-written MSL. Explicit bindings, explicit thread geometry, bounds checks. */
#include <metal_stdlib>
using namespace metal;

// ---- 0. elementwise: vector_add (F32) ------------------------------------
kernel void p4_vector_add_f32(
    device const float* a   [[buffer(0)]],
    device const float* b   [[buffer(1)]],
    device       float* out [[buffer(2)]],
    constant     uint&  n   [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= n) return;
    out[gid] = a[gid] + b[gid];
}

// ---- 1. vector_mul ------------------------------------------------------
kernel void p4_vector_mul_f32(
    device const float* a   [[buffer(0)]],
    device const float* b   [[buffer(1)]],
    device       float* out [[buffer(2)]],
    constant     uint&  n   [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= n) return;
    out[gid] = a[gid] * b[gid];
}

// ---- 2. matmul: tiled 16x16, F32 ----------------------------------------
#define P4_TILE 16
kernel void p4_matrix_mul_f32(
    device const float* A  [[buffer(0)]],
    device const float* B  [[buffer(1)]],
    device       float* C  [[buffer(2)]],
    constant     uint&  M  [[buffer(3)]],
    constant     uint&  N  [[buffer(4)]],
    constant     uint&  K  [[buffer(5)]],
    uint2 tp [[thread_position_in_threadgroup]],
    uint2 tg [[threadgroup_position_in_grid]])
{
    threadgroup float As[P4_TILE][P4_TILE];
    threadgroup float Bs[P4_TILE][P4_TILE];

    uint row = tg.y * P4_TILE + tp.y;
    uint col = tg.x * P4_TILE + tp.x;
    float acc = 0.0f;

    for (uint k0 = 0; k0 < K; k0 += P4_TILE) {
        uint ar = row, ac = k0 + tp.x;
        uint br = k0 + tp.y, bc = col;
        As[tp.y][tp.x] = (ar < M && ac < K) ? A[ar * K + ac] : 0.0f;
        Bs[tp.y][tp.x] = (br < K && bc < N) ? B[br * N + bc] : 0.0f;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for (uint k = 0; k < P4_TILE; ++k)
            acc += As[tp.y][k] * Bs[k][tp.x];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (row < M && col < N) C[row * N + col] = acc;
}

// ---- 3. reduction: sum over length, one threadgroup per row ------------
kernel void p4_reduction_sum_f32(
    device const float* x    [[buffer(0)]],
    device       float* out  [[buffer(1)]],
    constant     uint&  len  [[buffer(2)]],
    uint gid [[threadgroup_position_in_grid]],
    uint lid [[thread_position_in_threadgroup]],
    uint lsize [[threads_per_threadgroup]])
{
    threadgroup float scratch[1024];
    float acc = 0.0f;
    for (uint i = lid; i < len; i += lsize) acc += x[gid * len + i];
    scratch[lid] = acc;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint s = lsize >> 1; s > 0; s >>= 1) {
        if (lid < s) scratch[lid] += scratch[lid + s];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (lid == 0) out[gid] = scratch[0];
}

// ---- 4. softmax (row-wise, max-subtracted, deterministic) ---------------
kernel void p4_softmax_f32(
    device const float* x    [[buffer(0)]],
    device       float* y    [[buffer(1)]],
    constant     uint&  cols [[buffer(2)]],
    uint row [[threadgroup_position_in_grid]],
    uint lid [[thread_position_in_threadgroup]],
    uint lsize [[threads_per_threadgroup]])
{
    threadgroup float red[1024];
    device const float* xr = x + row * cols;
    device       float* yr = y + row * cols;

    float m = -INFINITY;
    for (uint i = lid; i < cols; i += lsize) m = max(m, xr[i]);
    red[lid] = m;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint s = lsize >> 1; s > 0; s >>= 1) {
        if (lid < s) red[lid] = max(red[lid], red[lid + s]);
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    m = red[0];

    float s = 0.0f;
    for (uint i = lid; i < cols; i += lsize) s += exp(xr[i] - m);
    red[lid] = s;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint k = lsize >> 1; k > 0; k >>= 1) {
        if (lid < k) red[lid] += red[lid + k];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    float inv = 1.0f / red[0];

    for (uint i = lid; i < cols; i += lsize) yr[i] = exp(xr[i] - m) * inv;
}

// ---- 5. rmsnorm ---------------------------------------------------------
kernel void p4_rmsnorm_f32(
    device const float* x     [[buffer(0)]],
    device const float* gamma [[buffer(1)]],
    device       float* y     [[buffer(2)]],
    constant     uint&  cols  [[buffer(3)]],
    constant     float& eps   [[buffer(4)]],
    uint row [[threadgroup_position_in_grid]],
    uint lid [[thread_position_in_threadgroup]],
    uint lsize [[threads_per_threadgroup]])
{
    threadgroup float red[1024];
    device const float* xr = x + row * cols;
    device       float* yr = y + row * cols;

    float ss = 0.0f;
    for (uint i = lid; i < cols; i += lsize) ss += xr[i] * xr[i];
    red[lid] = ss;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint s = lsize >> 1; s > 0; s >>= 1) {
        if (lid < s) red[lid] += red[lid + s];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    float rms = rsqrt(red[0] / float(cols) + eps);
    for (uint i = lid; i < cols; i += lsize) yr[i] = xr[i] * rms * gamma[i];
}

// ---- 6. layer_norm ------------------------------------------------------
kernel void p4_layer_norm_f32(
    device const float* x     [[buffer(0)]],
    device const float* gamma [[buffer(1)]],
    device const float* beta  [[buffer(2)]],
    device       float* y     [[buffer(3)]],
    constant     uint&  cols  [[buffer(4)]],
    constant     float& eps   [[buffer(5)]],
    uint row [[threadgroup_position_in_grid]],
    uint lid [[thread_position_in_threadgroup]],
    uint lsize [[threads_per_threadgroup]])
{
    threadgroup float red[1024];
    device const float* xr = x + row * cols;
    device       float* yr = y + row * cols;

    float s = 0.0f;
    for (uint i = lid; i < cols; i += lsize) s += xr[i];
    red[lid] = s;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint k = lsize >> 1; k > 0; k >>= 1) {
        if (lid < k) red[lid] += red[lid + k];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    float mean = red[0] / float(cols);

    float v = 0.0f;
    for (uint i = lid; i < cols; i += lsize) {
        float d = xr[i] - mean; v += d * d;
    }
    red[lid] = v;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint k = lsize >> 1; k > 0; k >>= 1) {
        if (lid < k) red[lid] += red[lid + k];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    float inv = rsqrt(red[0] / float(cols) + eps);
    for (uint i = lid; i < cols; i += lsize)
        yr[i] = (xr[i] - mean) * inv * gamma[i] + beta[i];
}

// ---- 7. rope (rotary position embedding, interleaved pairs) -------------
kernel void p4_rope_f32(
    device const float* x     [[buffer(0)]],
    device const float* cos_t [[buffer(1)]],
    device const float* sin_t [[buffer(2)]],
    device       float* y     [[buffer(3)]],
    constant     uint&  head_dim [[buffer(4)]],
    constant     uint&  pos      [[buffer(5)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint pair = gid.x, row = gid.y;
    uint half = head_dim >> 1;
    if (pair >= half) return;
    uint base = row * head_dim;
    float x0 = x[base + 2 * pair];
    float x1 = x[base + 2 * pair + 1];
    float c  = cos_t[pos * half + pair];
    float s  = sin_t[pos * half + pair];
    y[base + 2 * pair]     = x0 * c - x1 * s;
    y[base + 2 * pair + 1] = x0 * s + x1 * c;
}

// ---- 8. silu ------------------------------------------------------------
kernel void p4_silu_f32(
    device const float* x   [[buffer(0)]],
    device       float* y   [[buffer(1)]],
    constant     uint&  n   [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= n) return;
    float v = x[gid];
    y[gid] = v / (1.0f + exp(-v));
}

// ---- 9. swiglu ----------------------------------------------------------
kernel void p4_swiglu_f32(
    device const float* gate [[buffer(0)]],
    device const float* up   [[buffer(1)]],
    device       float* y    [[buffer(2)]],
    constant     uint&  n    [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= n) return;
    float g = gate[gid];
    y[gid] = (g / (1.0f + exp(-g))) * up[gid];
}

// ---- 10. attention (single head, single query row per threadgroup) ------
kernel void p4_attention_f32(
    device const float* Q  [[buffer(0)]],
    device const float* K  [[buffer(1)]],
    device const float* V  [[buffer(2)]],
    device       float* O  [[buffer(3)]],
    constant     uint&  S  [[buffer(4)]],
    constant     uint&  D  [[buffer(5)]],
    constant     float& scale [[buffer(6)]],
    constant     uint&  causal [[buffer(7)]],
    uint q [[threadgroup_position_in_grid]],
    uint lid [[thread_position_in_threadgroup]],
    uint lsize [[threads_per_threadgroup]])
{
    threadgroup float red[1024];

    float m = -INFINITY;
    for (uint k = lid; k < S; k += lsize) {
        if (causal && k > q) continue;
        float dot = 0.0f;
        for (uint d = 0; d < D; ++d) dot += Q[q * D + d] * K[k * D + d];
        dot *= scale;
        m = max(m, dot);
    }
    red[lid] = m;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint s = lsize >> 1; s > 0; s >>= 1) {
        if (lid < s) red[lid] = max(red[lid], red[lid + s]);
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    m = red[0];

    float sum = 0.0f;
    for (uint k = lid; k < S; k += lsize) {
        if (causal && k > q) continue;
        float dot = 0.0f;
        for (uint d = 0; d < D; ++d) dot += Q[q * D + d] * K[k * D + d];
        sum += exp(dot * scale - m);
    }
    red[lid] = sum;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint s = lsize >> 1; s > 0; s >>= 1) {
        if (lid < s) red[lid] += red[lid + s];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    float inv = 1.0f / red[0];

    for (uint d = lid; d < D; d += lsize) {
        float o = 0.0f;
        for (uint k = 0; k < S; ++k) {
            if (causal && k > q) continue;
            float dot = 0.0f;
            for (uint dd = 0; dd < D; ++dd) dot += Q[q * D + dd] * K[k * D + dd];
            o += exp(dot * scale - m) * inv * V[k * D + d];
        }
        O[q * D + d] = o;
    }
}

// ---- 11. gqa (grouped-query attention, n_q heads : n_kv heads) ----------
kernel void p4_gqa_f32(
    device const float* Q  [[buffer(0)]],
    device const float* K  [[buffer(1)]],
    device const float* V  [[buffer(2)]],
    device       float* O  [[buffer(3)]],
    constant     uint&  S  [[buffer(4)]],
    constant     uint&  D  [[buffer(5)]],
    constant     uint&  n_q  [[buffer(6)]],
    constant     uint&  n_kv [[buffer(7)]],
    constant     float& scale [[buffer(8)]],
    uint2 tg [[threadgroup_position_in_grid]],
    uint lid [[thread_position_in_threadgroup]],
    uint lsize [[threads_per_threadgroup]])
{
    uint row = tg.x, hq = tg.y;
    uint group = n_q / n_kv;
    uint hk = hq / group;

    device const float* Qh = Q + (row * n_q + hq) * D;
    device const float* Kh = K + hk * S * D;
    device const float* Vh = V + hk * S * D;
    device       float* Oh = O + (row * n_q + hq) * D;

    threadgroup float red[1024];
    float m = -INFINITY;
    for (uint k = lid; k < S; k += lsize) {
        float dot = 0.0f;
        for (uint d = 0; d < D; ++d) dot += Qh[d] * Kh[k * D + d];
        m = max(m, dot * scale);
    }
    red[lid] = m;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint s = lsize >> 1; s > 0; s >>= 1) {
        if (lid < s) red[lid] = max(red[lid], red[lid + s]);
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    m = red[0];

    float sum = 0.0f;
    for (uint k = lid; k < S; k += lsize) {
        float dot = 0.0f;
        for (uint d = 0; d < D; ++d) dot += Qh[d] * Kh[k * D + d];
        sum += exp(dot * scale - m);
    }
    red[lid] = sum;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint s = lsize >> 1; s > 0; s >>= 1) {
        if (lid < s) red[lid] += red[lid + s];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    float inv = 1.0f / red[0];

    for (uint d = lid; d < D; d += lsize) {
        float o = 0.0f;
        for (uint k = 0; k < S; ++k) {
            float dot = 0.0f;
            for (uint dd = 0; dd < D; ++dd) dot += Qh[dd] * Kh[k * D + dd];
            o += exp(dot * scale - m) * inv * Vh[k * D + d];
        }
        Oh[d] = o;
    }
}

// ---- 12. elementwise fusion (a*b + c, with an op-code branch) -----------
kernel void p4_elementwise_fusion_f32(
    device const float* a   [[buffer(0)]],
    device const float* b   [[buffer(1)]],
    device const float* c   [[buffer(2)]],
    device       float* y   [[buffer(3)]],
    constant     uint&  n   [[buffer(4)]],
    constant     uint&  op  [[buffer(5)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= n) return;
    float av = a[gid], bv = b[gid], cv = c[gid];
    switch (op) {
        case 0: y[gid] = av * bv + cv; break;
        case 1: y[gid] = max(av * bv + cv, 0.0f); break;
        case 2: y[gid] = tanh(av * bv + cv); break;
        default: y[gid] = av + bv + cv; break;
    }
}

// ---- 13. tensor_copy ----------------------------------------------------
kernel void p4_tensor_copy_f32(
    device const float* src [[buffer(0)]],
    device       float* dst [[buffer(1)]],
    constant     uint&  n   [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= n) return;
    dst[gid] = src[gid];
}
