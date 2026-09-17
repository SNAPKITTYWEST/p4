# crystal/registry/p4_registry.cr — kernel registry. No GPU logic here.
require "../runtime/abi"

module P4
  enum Origin
    MSL            = 1
    CUDA           = 2
    CPU_REFERENCE  = 3
  end

  record KernelRecord,
    kernel_id : UInt32,
    kernel_name : String,
    backend : Int32,
    architecture : String,
    source_hash : UInt64,
    binary_hash : UInt64,
    dtype : Int32,
    input_signature : String,
    output_signature : String,
    launch : {grid: {UInt32, UInt32, UInt32}, block: {UInt32, UInt32, UInt32}, shared: UInt32},
    version : UInt32,
    origin : Origin

  class Registry
    @records = {} of {UInt32, Int32, Int32} => KernelRecord

    def register(rec : KernelRecord) : Nil
      key = {rec.kernel_id, rec.backend, rec.dtype}
      raise "duplicate kernel: #{rec.kernel_name} backend=#{rec.backend}" if @records.has_key?(key)
      @records[key] = rec
    end

    def lookup(id : UInt32, backend : Int32, dtype : Int32) : KernelRecord
      @records[{id, backend, dtype}]? ||
        raise "P4_ERR_NOT_FOUND: kernel 0x#{id.to_s(16)} backend=#{backend} dtype=#{dtype}"
    end

    def dump : Array(KernelRecord)
      @records.values
    end

    def verify_hashes!(id : UInt32, backend : Int32, dtype : Int32, source : String) : Nil
      rec = lookup(id, backend, dtype)
      h = fnv1a(source)
      raise "P4 source hash mismatch for #{rec.kernel_name}" unless h == rec.source_hash
    end

    private def fnv1a(s : String) : UInt64
      h = 1469598103934665603_u64
      s.each_byte { |b| h ^= b.to_u64; h &*= 1099511628211_u64 }
      h
    end
  end
end
