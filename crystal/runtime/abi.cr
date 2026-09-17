# crystal/runtime/abi.cr — stable C ABI bindings for Crystal.
@[Link(ldflags: "-L./build -lp4")]
lib LibP4
  enum Status
    OK               =  0
    InvalidArg       = -1
    NoDevice         = -2
    OOM              = -3
    Compile          = -4
    Dispatch         = -5
    Unsupported      = -6
    NoFallback       = -7
    NotFound         = -8
    State            = -9
    Numerical        = -10

    def ok? : Bool
      self == Status::OK
    end

    def error? : Bool
      !ok?
    end
  end

  struct Extent3
    x : UInt32
    y : UInt32
    z : UInt32
  end

  struct Launch
    grid : Extent3
    block : Extent3
    shared_bytes : UInt32
    flags : UInt32
  end

  struct ErrorReport
    max_absolute_error : Float64
    max_relative_error : Float64
    mean_absolute_error : Float64
    nan_count : UInt64
    inf_count : UInt64
  end

  fun p4_init : Status
  fun p4_shutdown : Status

  fun p4_device_enumerate(backend : Int32, out : Void**, count : UInt32*) : Status
  fun p4_device_create(backend : Int32, index : UInt32, out : Void**) : Status
  fun p4_device_architecture(dev : Void*, out_name : UInt8**) : Status
  fun p4_device_capabilities(dev : Void*, out : Void*) : Status
  fun p4_device_destroy(dev : Void*) : Status

  fun p4_buffer_create(dev : Void*, bytes : UInt64, dt : Int32, out : Void**) : Status
  fun p4_buffer_upload(buf : Void*, src : Void*, bytes : UInt64, offset : UInt64) : Status
  fun p4_buffer_read(buf : Void*, dst : Void*, bytes : UInt64, offset : UInt64) : Status
  fun p4_buffer_bytes(buf : Void*, out : UInt64*) : Status
  fun p4_buffer_destroy(buf : Void*) : Status

  fun p4_kernel_create(dev : Void*, id : Int32, dt : Int32,
                       source : UInt8*, entry : UInt8*, out : Void**) : Status
  fun p4_kernel_source(k : Void*, out_src : UInt8**, out_len : UInt64*) : Status
  fun p4_kernel_backend(k : Void*, out : Int32*) : Status
  fun p4_kernel_destroy(k : Void*) : Status

  fun p4_command_begin(dev : Void*, out : Void**) : Status
  fun p4_command_bind_buffer(cmd : Void*, buf : Void*, index : UInt32) : Status
  fun p4_command_dispatch(cmd : Void*, k : Void*,
                          grid : Extent3*, block : Extent3*,
                          shared : UInt32) : Status
  fun p4_command_commit(cmd : Void*, out_evt : Void**) : Status
  fun p4_command_sync(cmd : Void*) : Status
  fun p4_command_destroy(cmd : Void*) : Status

  fun p4_event_wait(evt : Void*, timeout_ns : UInt64) : Status
  fun p4_event_query(evt : Void*, complete : UInt32*) : Status
  fun p4_event_destroy(evt : Void*) : Status

  fun p4_registry_register(rec : Void*) : Status
  fun p4_registry_lookup(id : Int32, backend : Int32, dt : Int32, out : Void*) : Status
  fun p4_registry_dump(out : Void**, count : UInt32*) : Status

  fun p4_verify_against_reference(gpu : Void*, ref : Void*,
                                  count : UInt64, dt : Int32,
                                  atol : Float64, rtol : Float64,
                                  out : ErrorReport*) : Status
end

module P4::ABI
  BACKEND_APPLE  = 1_i32
  BACKEND_NVIDIA = 2_i32
  BACKEND_CPU    = 3_i32
end
