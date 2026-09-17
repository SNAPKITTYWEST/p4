# mojo/device/p4_device.mojo — backend-neutral device API. Does not hide the backend.
from ffi.p4_ffi import *
from memory import UnsafePointer, memset_zero

alias BACKEND_APPLE:  Int32 = 1
alias BACKEND_NVIDIA: Int32 = 2
alias BACKEND_CPU:    Int32 = 3

alias DTYPE_F16: Int32 = 1
alias DTYPE_BF16: Int32 = 2
alias DTYPE_F32: Int32 = 3

struct Device:
    var _inner: P4Device
    var _backend: Int32
    var _arch: String

    fn __init__(inout self, backend: Int32, index: UInt32 = 0) raises:
        var h = UnsafePointer[UnsafePointer[UInt8]].alloc(1)
        let st = p4_device_create(backend, index, h)
        if st != P4_OK:
            h.free()
            raise Error("p4_device_create failed: " + String(st))
        self._inner = P4Device(h[])
        self._backend = backend
        h.free()
        self._arch = _query_arch(self._inner)

    fn backend(self) -> Int32: return self._backend
    fn architecture(self) -> String: return self._arch

    fn buffer(self, bytes: UInt64, dtype: Int32 = DTYPE_F32) raises -> Buffer:
        return Buffer(self._inner, bytes, dtype)

struct Buffer:
    var _inner: P4Buffer
    var _device: P4Device

    fn __init__(inout self, dev: P4Device, bytes: UInt64, dtype: Int32) raises:
        var h = UnsafePointer[UnsafePointer[UInt8]].alloc(1)
        let st = p4_buffer_create(dev, bytes, dtype, h)
        if st != P4_OK:
            h.free()
            raise Error("p4_buffer_create failed: " + String(st))
        self._inner = P4Buffer(h[], bytes, dtype)
        self._device = dev
        h.free()

fn _query_arch(dev: P4Device) -> String:
    var p = UnsafePointer[UnsafePointer[UInt8]].alloc(1)
    _ = p4_device_architecture(dev, p)
    let name = p[]
    p.free()
    return String(name)
