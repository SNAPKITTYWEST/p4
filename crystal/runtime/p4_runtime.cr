# crystal/runtime/p4_runtime.cr — systems layer. Talks only through the C ABI.
require "./abi"
require "../registry/p4_registry"

module P4
  class Runtime
    getter registry : Registry
    @devices = {} of Int32 => Pointer(Void)

    def initialize
      status = LibP4.p4_init
      raise "p4_init failed: #{status}" unless status.ok?
      @registry = Registry.new
    end

    def discover_devices(backends : Array(Int32) = [ABI::BACKEND_APPLE, ABI::BACKEND_NVIDIA])
      backends.each do |b|
        ptr = Pointer(Pointer(Void)).malloc(1)
        count = uninitialized UInt32
        st = LibP4.p4_device_enumerate(b, ptr, pointerof(count))
        if st.ok? && count > 0
          @devices[b] = ptr.value
          Log.info { "P4 device discovered backend=#{b}" }
        elsif st.error?
          Log.warn { "P4 backend #{b} unavailable: #{st}" }
        end
      end
    end

    def route(kernel_id : UInt32, dtype : Int32, preferred_backend : Int32) : {Pointer(Void), KernelRecord}
      dev = @devices[preferred_backend]?
      raise "P4_ERR_NO_DEVICE: backend #{preferred_backend} not initialized" unless dev
      rec = @registry.lookup(kernel_id, preferred_backend, dtype)
      {dev, rec}
    end

    def shutdown
      @devices.each_value do |dev|
        LibP4.p4_device_destroy(dev)
      end
      LibP4.p4_shutdown
    end
  end
end
