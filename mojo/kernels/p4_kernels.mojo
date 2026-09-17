# mojo/kernels/p4_kernels.mojo — kernel-facing API + source inspection.
from ffi.p4_ffi import *
from device.p4_device import Device, Buffer, DTYPE_F32

struct Kernel:
    var _inner: P4Kernel
    var _id: Int32
    var _backend: Int32

    fn backend(self) -> Int32: return self._backend

    fn source(self) -> String raises:
        var p = UnsafePointer[UnsafePointer[UInt8]].alloc(1)
        var n = UnsafePointer[UInt64].alloc(1)
        let st = external_call["p4_kernel_source", Int32](self._inner._h, p, n)
        if st != P4_OK: raise Error("kernel source unavailable")
        let s = String(p[])
        p.free(); n.free()
        return s

    fn capabilities(self) raises:
        var raw = UnsafePointer[UInt8].alloc(256)
        let st = p4_kernel_capabilities(self._inner, raw)
        if st != P4_OK: raise Error("capabilities unavailable")

fn load(dev: Device, id: Int32, dtype: Int32, source: String, entry: String) raises -> Kernel:
    var kh = UnsafePointer[UnsafePointer[UInt8]].alloc(1)
    var sb = source.unsafe_ptr()
    var eb = entry.unsafe_ptr()
    let st = p4_kernel_create(dev._inner, id, dtype, sb, eb, kh)
    if st != P4_OK: raise Error("p4_kernel_create failed for " + entry)
    var b = UnsafePointer[Int32].alloc(1)
    _ = p4_kernel_backend(P4Kernel(kh[], id, -1), b)
    var k = Kernel(P4Kernel(kh[], id, b[]), id, b[])
    kh.free(); b.free()
    return k

# --- named kernel constructors (backend-neutral) --------------------------
alias K_VECTOR_ADD: Int32 = 0x0101
alias K_VECTOR_MUL: Int32 = 0x0102
alias K_MATRIX_MUL: Int32 = 0x0103
alias K_REDUCTION:  Int32 = 0x0104
alias K_SOFTMAX:    Int32 = 0x0105
alias K_RMSNORM:    Int32 = 0x0106
alias K_LAYER_NORM: Int32 = 0x0107
alias K_ROPE:       Int32 = 0x0108
alias K_SILU:       Int32 = 0x0109
alias K_SWIGLU:     Int32 = 0x010A
alias K_ATTENTION:  Int32 = 0x010B
alias K_GQA:        Int32 = 0x010C

fn vector_add(dev: Device, dtype: Int32 = DTYPE_F32) raises -> Kernel:
    let src = _backend_source(dev.backend(), "vector_add")
    return load(dev, K_VECTOR_ADD, dtype, src, "p4_vector_add_f32")

fn rmsnorm(dev: Device, dtype: Int32 = DTYPE_F32) raises -> Kernel:
    let src = _backend_source(dev.backend(), "rmsnorm")
    return load(dev, K_RMSNORM, dtype, src, "p4_rmsnorm_f32")

fn softmax(dev: Device, dtype: Int32 = DTYPE_F32) raises -> Kernel:
    let src = _backend_source(dev.backend(), "softmax")
    return load(dev, K_SOFTMAX, dtype, src, "p4_softmax_f32")

fn rope(dev: Device, dtype: Int32 = DTYPE_F32) raises -> Kernel:
    let src = _backend_source(dev.backend(), "rope")
    return load(dev, K_ROPE, dtype, src, "p4_rope_f32")

fn swiglu(dev: Device, dtype: Int32 = DTYPE_F32) raises -> Kernel:
    let src = _backend_source(dev.backend(), "swiglu")
    return load(dev, K_SWIGLU, dtype, src, "p4_swiglu_f32")

fn gqa(dev: Device, dtype: Int32 = DTYPE_F32) raises -> Kernel:
    let src = _backend_source(dev.backend(), "gqa")
    return load(dev, K_GQA, dtype, src, "p4_gqa_f32")

fn _backend_source(backend: Int32, kernel_name: String) -> String:
    # Reads from the embedded source store so both MSL and CUDA text
    # travel with the binary and are hashable.
    return ""  # Populated by build system from msl/ and kernels/ directories
