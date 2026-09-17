```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   ██████╗ ██╗  ██╗                                                          │
│   ██╔══██╗██║  ██║                                                          │
│   ██████╔╝███████║                                                          │
│   ██╔═══╝ ╚════██║                                                          │
│   ██║          ██║                                                          │
│   ╚═╝          ╚═╝                                                          │
│                                                                             │
│   ███████╗ ██████╗ ██╗   ██╗███████╗██████╗ ███████╗██╗ ██████╗ ███╗   ██╗ │
│   ██╔════╝██╔═══██╗██║   ██║██╔════╝██╔══██╗██╔════╝██║██╔════╝ ████╗  ██║ │
│   ███████╗██║   ██║██║   ██║█████╗  ██████╔╝█████╗  ██║██║  ███╗██╔██╗ ██║ │
│   ╚════██║██║   ██║╚██╗ ██╔╝██╔══╝  ██╔══██╗██╔══╝  ██║██║   ██║██║╚██╗██║ │
│   ███████║╚██████╔╝ ╚████╔╝ ███████╗██║  ██║███████╗██║╚██████╔╝██║ ╚████║ │
│   ╚══════╝ ╚═════╝   ╚═══╝  ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝│
│                                                                             │
│   ██████╗ ██████╗ ██╗   ██╗    ███████╗███████╗██╗    ███████╗████████╗     │
│   ██╔════╝ ██╔══██╗██║   ██║    ██╔════╝██╔════╝██║    ██╔════╝╚══██╔══╝     │
│   ██║  ███╗██████╔╝██║   ██║    █████╗  █████╗  ██║    ███████╗   ██║        │
│   ██║   ██║██╔═══╝ ██║   ██║    ██╔══╝  ██╔══╝  ██║    ╚════██║   ██║        │
│   ╚██████╔╝██║     ╚██████╔╝    ██║     ██║     ██║    ███████║   ██║        │
│    ╚═════╝ ╚═╝      ╚═════╝     ╚═╝     ╚═╝     ╚═╝    ╚══════╝   ╚═╝        │
│                                                                             │
│   Hand-Rolled GPU Compute · Metal + CUDA · Unified C ABI                    │
│   No frameworks · No fallbacks · Deterministic dispatch                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

![Version](https://img.shields.io/badge/version-0.1.0-blue)
![ABI](https://img.shields.io/badge/ABI-v1%20stable-brightgreen)
![Backends](https://img.shields.io/badge/backends-Metal%20%7C%20CUDA%20%7C%20CPU-blueviolet)
![Kernels](https://img.shields.io/badge/kernels-14%20hand--written-critical)
![Status](https://img.shields.io/badge/status-production--architecture-orange)

---

## What is this?

P4 is a hand-rolled, low-level GPU compute stack that exposes native Apple Metal and NVIDIA CUDA kernels through a unified FFI architecture. Every kernel is hand-written. Every interface is explicit. Nothing is delegated to a framework.

Six layers, one stable C ABI boundary between them:

- **ABI** — Stable C types, opaque handles, kernel IDs. The line that nothing crosses except plain C.
- **Apple Metal** — Objective-C FFI to Metal runtime. Hand-written MSL kernels. No MPS. No MetalKit.
- **NVIDIA CUDA** — CUDA runtime + NVRTC compile. Hand-written CUDA kernels. No cuDNN. No cuBLAS.
- **Mojo** — Numerical layer. Device abstraction, buffer management, kernel dispatch. Owns the math API.
- **Crystal** — Systems orchestration. Process lifecycle, kernel registry, device discovery, job routing.
- **CPU Reference** — Scalar reference implementations for every kernel. Verification oracle.

15 constraints enforced. No cloud GPU dependency. No SaaS inference. No mandatory Python runtime. No silent backend fallback. Explicit failure on unsupported capabilities.

---

## Architecture

```mermaid
flowchart TD
    subgraph Application
        APP[Application Code]
    end

    subgraph "Crystal Systems Layer"
        CR1[Process Lifecycle]
        CR2[Kernel Registry]
        CR3[Device Discovery]
        CR4[Job Routing]
    end

    subgraph "Mojo Numerical Layer"
        MJ1[P4Device]
        MJ2[P4Buffer]
        MJ3[P4Kernel]
        MJ4[Dispatch]
    end

    subgraph "Stable C ABI"
        ABI[p4.h / types.h]
    end

    subgraph "Apple Metal"
        AM1[Objective-C FFI]
        AM2[Metal Runtime]
        AM3[MSL Kernels]
    end

    subgraph "NVIDIA CUDA"
        NC1[CUDA C FFI]
        NC2[NVRTC Compile]
        NC3[CUDA Kernels]
    end

    subgraph "CPU Reference"
        REF[Scalar Reference]
    end

    APP --> CR1 & CR2
    CR1 & CR4 --> MJ1 & MJ4
    MJ4 --> ABI
    ABI --> AM1
    ABI --> NC1
    ABI --> REF
    AM1 --> AM2 --> AM3
    NC1 --> NC2 --> NC3
```

## Kernel Dispatch Pipeline

```mermaid
flowchart LR
    REQ([Kernel Request]) --> REG[Registry Lookup<br/>kernel_id + backend + dtype]
    REG --> HASH{Source Hash<br/>Matches?}
    HASH -->|Yes| COMPILE[Compile Pipeline<br/>MSL or NVRTC]
    HASH -->|No| FAIL[P4_ERR_NUMERICAL]
    COMPILE --> BIND[Bind Buffers<br/>explicit index]
    BIND --> DISPATCH[Dispatch<br/>grid × block × shared]
    DISPATCH --> COMMIT[Commit + Event]
    COMMIT --> WAIT[Wait / Query]
    WAIT --> VERIFY{Verify Against<br/>Reference?}
    VERIFY -->|Pass| DONE[Result]
    VERIFY -->|Fail| REPORT[Error Report<br/>max_abs, max_rel, NaN count]
```

## Backend Capabilities

```mermaid
graph LR
    subgraph "Apple Metal"
        A1[fp16 ✓]
        A2[bf16 ✗]
        A3[fp64 ✗]
        A4[SIMD width: 32]
        A5[Shared storage mode]
    end

    subgraph "NVIDIA CUDA"
        N1[fp16 ✓ sm_50+]
        N2[bf16 ✓ sm_80+]
        N3[fp64 ✓ sm_20+]
        N4[Warp size: 32]
        N5[NVRTC runtime compile]
    end

    subgraph "CPU Reference"
        C1[All dtypes ✓]
        C2[Scalar only]
        C3[Verification oracle]
    end

    style A1 fill:#0d3320,stroke:#22c55e,color:#e2e8f0
    style A4 fill:#0d3320,stroke:#22c55e,color:#e2e8f0
    style N1 fill:#0d3320,stroke:#22c55e,color:#e2e8f0
    style N2 fill:#0d3320,stroke:#22c55e,color:#e2e8f0
    style N3 fill:#0d3320,stroke:#22c55e,color:#e2e8f0
    style N4 fill:#0d3320,stroke:#22c55e,color:#e2e8f0
    style C1 fill:#0d3320,stroke:#22c55e,color:#e2e8f0
    style C3 fill:#0d3320,stroke:#22c55e,color:#e2e8f0
```

## Kernel Matrix

```mermaid
graph TD
    subgraph "14 Hand-Written Kernels"
        subgraph "Vector Ops"
            K01[vector_add]
            K02[vector_mul]
        end
        subgraph "Matrix Ops"
            K03[matrix_mul<br/>16×16 tiled]
        end
        subgraph "Reductions"
            K04[reduction_sum]
            K05[softmax<br/>max-subtracted]
        end
        subgraph "Normalization"
            K06[rmsnorm]
            K07[layer_norm]
        end
        subgraph "Positional"
            K08[rope<br/>interleaved pairs]
        end
        subgraph "Activations"
            K09[silu]
            K10[swiglu]
        end
        subgraph "Attention"
            K11[attention<br/>causal optional]
            K12[gqa<br/>grouped query]
        end
        subgraph "Fusion"
            K13[elementwise_fusion<br/>fma/relu/tanh]
            K14[tensor_copy]
        end
    end

    style K01 fill:#1a1a2e,stroke:#60a5fa,color:#e2e8f0
    style K02 fill:#1a1a2e,stroke:#60a5fa,color:#e2e8f0
    style K03 fill:#1a1a2e,stroke:#60a5fa,color:#e2e8f0
    style K04 fill:#1a1a2e,stroke:#60a5fa,color:#e2e8f0
    style K05 fill:#1a1a2e,stroke:#60a5fa,color:#e2e8f0
    style K06 fill:#1a1a2e,stroke:#60a5fa,color:#e2e8f0
    style K07 fill:#1a1a2e,stroke:#60a5fa,color:#e2e8f0
    style K08 fill:#1a1a2e,stroke:#60a5fa,color:#e2e8f0
    style K09 fill:#1a1a2e,stroke:#60a5fa,color:#e2e8f0
    style K10 fill:#1a1a2e,stroke:#60a5fa,color:#e2e8f0
    style K11 fill:#1a1a2e,stroke:#60a5fa,color:#e2e8f0
    style K12 fill:#1a1a2e,stroke:#60a5fa,color:#e2e8f0
    style K13 fill:#1a1a2e,stroke:#60a5fa,color:#e2e8f0
    style K14 fill:#1a1a2e,stroke:#60a5fa,color:#e2e8f0
```

---

## Design Constraints

| ID | Constraint | Enforcement |
|----|-----------|-------------|
| P4-1 | No cloud GPU dependency | All compute is local hardware |
| P4-2 | No SaaS inference dependency | No external API calls |
| P4-3 | No mandatory Python runtime | C ABI + Mojo + Crystal |
| P4-4 | No high-level GPU framework in core | No MPS, cuDNN, cuBLAS |
| P4-5 | Objective-C handles Apple Metal boundary | Direct Metal API |
| P4-6 | MSL kernels are hand-written | 13 kernels in p4_kernels.metal |
| P4-7 | CUDA kernels are hand-written | 12 kernels in p4_kernels.cu |
| P4-8 | Mojo owns numerical/kernel API | Device, Buffer, Kernel structs |
| P4-9 | Crystal owns systems orchestration | Registry, Runtime, routing |
| P4-10 | C ABI is stable interop boundary | abi/p4.h + abi/types.h |
| P4-11 | Cross-backend mathematical contracts | FNV-1a source hashing |
| P4-12 | Every kernel independently testable | Per-kernel verification API |
| P4-13 | Reproducible version & source hashes | version.h + kernel_record |
| P4-14 | Explicit failure on unsupported caps | P4_ERR_UNSUPPORTED |
| P4-15 | No silent backend fallback | P4_ERR_NO_FALLBACK |

---

## Project Structure

```
p4/
├── abi/                          Stable C ABI
│   ├── p4.h                      Single interoperability boundary
│   ├── types.h                   Primitive types, opaque handles, kernel IDs
│   └── version.h                 Version and ABI version
│
├── apple/                        Apple Metal Backend
│   ├── objc/
│   │   ├── p4_metal.h            Public C header
│   │   └── p4_metal.m            Objective-C implementation
│   └── msl/
│       └── p4_kernels.metal      14 hand-written MSL kernels
│
├── nvidia/                       NVIDIA CUDA Backend
│   ├── cuda/
│   │   ├── p4_cuda.h             Public C header
│   │   └── p4_cuda.cu            CUDA runtime + NVRTC implementation
│   └── kernels/
│       └── p4_kernels.cu         12 hand-written CUDA kernels
│
├── mojo/                         Mojo Numerical Layer
│   ├── ffi/
│   │   └── p4_ffi.mojo           C ABI bindings
│   ├── device/
│   │   └── p4_device.mojo        Backend-neutral device API
│   └── kernels/
│       └── p4_kernels.mojo       Kernel dispatch + named constructors
│
├── crystal/                      Crystal Systems Layer
│   ├── registry/
│   │   └── p4_registry.cr        Kernel registry + hash verification
│   └── runtime/
│       ├── abi.cr                 Crystal C ABI bindings
│       └── p4_runtime.cr         Device discovery + job routing
│
├── reference/                    CPU Reference (verification oracle)
│   └── numerical/
│       └── ops/
│
├── tests/                        Verification suite
├── benchmarks/                   Performance layer
├── docs/                         Architecture documentation
└── scripts/                      Build scripts
```

---

## Build

Platform-specific. Metal backend requires macOS + Xcode. CUDA backend requires nvcc + NVRTC.

```bash
# Apple Metal (macOS)
clang -framework Metal -framework Foundation -c apple/objc/p4_metal.m -o build/p4_metal.o
xcrun metal -c apple/msl/p4_kernels.metal -o build/p4_kernels.air

# NVIDIA CUDA
nvcc -c nvidia/kernels/p4_kernels.cu -o build/p4_kernels.o
nvcc -c nvidia/cuda/p4_cuda.cu -o build/p4_cuda.o -lnvrtc

# Mojo
mojo build mojo/ffi/p4_ffi.mojo

# Crystal
crystal build crystal/runtime/p4_runtime.cr
```

---

## License

See [LICENSE](LICENSE) for details.
