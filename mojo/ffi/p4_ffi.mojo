# mojo/ffi/p4_ffi.mojo — thin, explicit bindings to the C ABI.
from sys import external_call
from memory import UnsafePointer, DType

alias P4_OK: Int32 = 0

struct P4Device:
    var _h: UnsafePointer[UInt8]
    fn __init__(inout self): self._h = UnsafePointer[UInt8]()
    fn __init__(inout self, h: UnsafePointer[UInt8]): self._h = h
    fn is_valid(self) -> Bool: return Bool(self._h)

struct P4Buffer:
    var _h: UnsafePointer[UInt8]
    var _bytes: UInt64
    var _dtype: Int32

struct P4Kernel:
    var _h: UnsafePointer[UInt8]
    var _id: Int32
    var _backend: Int32

struct P4Command:
    var _h: UnsafePointer[UInt8]

struct P4Event:
    var _h: UnsafePointer[UInt8]

# --- lifecycle ---
fn p4_init() -> Int32:
    return external_call["p4_init", Int32]()

fn p4_shutdown() -> Int32:
    return external_call["p4_shutdown", Int32]()

# --- device ---
fn p4_device_create(backend: Int32, index: UInt32, out_dev: UnsafePointer[UnsafePointer[UInt8]]) -> Int32:
    return external_call["p4_device_create", Int32](backend, index, out_dev)

fn p4_device_architecture(dev: P4Device, out_name: UnsafePointer[UnsafePointer[UInt8]]) -> Int32:
    return external_call["p4_device_architecture", Int32](dev._h, out_name)

# --- buffer ---
fn p4_buffer_create(dev: P4Device, bytes: UInt64, dt: Int32,
                    out_buf: UnsafePointer[UnsafePointer[UInt8]]) -> Int32:
    return external_call["p4_buffer_create", Int32](dev._h, bytes, dt, out_buf)

fn p4_buffer_upload(buf: P4Buffer, src: UnsafePointer[UInt8],
                    bytes: UInt64, offset: UInt64) -> Int32:
    return external_call["p4_buffer_upload", Int32](buf._h, src, bytes, offset)

fn p4_buffer_read(buf: P4Buffer, dst: UnsafePointer[UInt8],
                  bytes: UInt64, offset: UInt64) -> Int32:
    return external_call["p4_buffer_read", Int32](buf._h, dst, bytes, offset)

fn p4_buffer_destroy(buf: P4Buffer) -> Int32:
    return external_call["p4_buffer_destroy", Int32](buf._h)

# --- kernel ---
fn p4_kernel_create(dev: P4Device, id: Int32, dt: Int32,
                    source: UnsafePointer[UInt8], entry: UnsafePointer[UInt8],
                    out_k: UnsafePointer[UnsafePointer[UInt8]]) -> Int32:
    return external_call["p4_kernel_create", Int32](
        dev._h, id, dt, source, entry, out_k)

fn p4_kernel_backend(k: P4Kernel, out_b: UnsafePointer[Int32]) -> Int32:
    return external_call["p4_kernel_backend", Int32](k._h, out_b)

fn p4_kernel_capabilities(k: P4Kernel, out_caps: UnsafePointer[UInt8]) -> Int32:
    return external_call["p4_kernel_capabilities", Int32](k._h, out_caps)

# --- command / dispatch ---
fn p4_command_begin(dev: P4Device, out_cmd: UnsafePointer[UnsafePointer[UInt8]]) -> Int32:
    return external_call["p4_command_begin", Int32](dev._h, out_cmd)

fn p4_command_bind_buffer(cmd: P4Command, buf: P4Buffer, index: UInt32) -> Int32:
    return external_call["p4_command_bind_buffer", Int32](cmd._h, buf._h, index)

fn p4_command_dispatch(cmd: P4Command, k: P4Kernel,
                       gx: UInt32, gy: UInt32, gz: UInt32,
                       bx: UInt32, by: UInt32, bz: UInt32,
                       shared: UInt32) -> Int32:
    return external_call["p4_command_dispatch", Int32](
        cmd._h, k._h, gx, gy, gz, bx, by, bz, shared)

fn p4_command_commit(cmd: P4Command, out_evt: UnsafePointer[UnsafePointer[UInt8]]) -> Int32:
    return external_call["p4_command_commit", Int32](cmd._h, out_evt)

fn p4_event_wait(evt: P4Event, timeout_ns: UInt64) -> Int32:
    return external_call["p4_event_wait", Int32](evt._h, timeout_ns)

fn p4_command_destroy(cmd: P4Command) -> Int32:
    return external_call["p4_command_destroy", Int32](cmd._h)

# --- verification ---
fn p4_verify_against_reference(gpu: UnsafePointer[UInt8], ref: UnsafePointer[UInt8],
                               count: UInt64, dt: Int32,
                               atol: Float64, rtol: Float64,
                               out_rep: UnsafePointer[UInt8]) -> Int32:
    return external_call["p4_verify_against_reference", Int32](
        gpu, ref, count, dt, atol, rtol, out_rep)
