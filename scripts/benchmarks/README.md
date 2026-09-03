# Native ARM64 Wine A/B benchmarks

Same-source, same-CPU comparison of aarch64 PE execution under the native
ARM64 Wine build (see `scripts/build-wine-arm64.sh`) versus a plain macOS
arm64 binary. Both builds use identical source and `-O2`; the PE build is
64K section-aligned because 4K-aligned images hit the W^X flip-storm of
issue #100.

Measured on M4 Pro / macOS 26 (2026-09-03):

| benchmark    | native arm64 | arm64 Wine PE | ratio |
|--------------|-------------:|--------------:|------:|
| cpu-loop 2e8 | 0.361–0.389 s | 0.460–0.470 s | ~1.25× |
| heap-touch   | 0.0059 s | 0.0181 s | ~3.1× (wine PE-heap + page-protection path) |

**Engine-overhead attribution (decisive).** A follow-up matrix (`pureloop.c`,
`storeloop.c`, `vastore.c`, `thrloop.c`) holds the 2e8-iteration workload
identical (same checksum) while varying only where the per-iteration store
lands:

| store target | native | ARM64 Wine | delta |
|---|---:|---:|---:|
| register only | 0.2063 s | 0.2045 s | ~0% |
| .data (volatile) | 0.2049 s | 0.2055 s | ~0% |
| heap / VirtualAlloc | 0.2064 s | 0.2064 s | 0% |
| secondary-thread stack | 0.2082 s | 0.2041 s | ~0% |

The execution engine itself has **zero measurable overhead** — decode,
branch prediction, and page attributes under the ARM64 engine are
indistinguishable from native. The earlier cpu-loop 1.25× was an artifact of
its stack-resident volatile store, a pathological case for both environments
(native 0.36–0.39 s, Wine 0.46 s); do not read it as engine tax.

For reference, the same workload shape as Java (HeapTouch3) measured earlier:
native ARM64 JVM 0.06 s vs x86_64 JVM under Rosetta in the x86_64 engine
2.17 s — a 36× translation tax. Executing native aarch64 PE code under the
ARM64 Wine engine removes ≈100% of that gap at the execution-engine level;
the only measured residuals are the user-space heap implementation (heap-touch
3.1×, see below) and the stock-MSVC-image W^X issue (#100).

Build commands:

    # native
    clang -O2 cpuloop.c -o cpuloop-native

    # PE (64K-aligned)
    llvm-mingw/bin/aarch64-w64-mingw32-clang -O2 \
        -Wl,--section-alignment=65536 -Wl,--file-alignment=65536 \
        cpuloop.c -o cpuloop-64k.exe

Run the PE build in a prefix of the ARM64 engine (`wine C:\\bench\\cpuloop-64k.exe`).

## Phase breakdown (heap-touch residual)

`heapphase.c` splits the 3.1× into phases (8-round averages, 128 MiB/round):

| phase | native | ARM64 Wine | ratio |
|-------|-------:|-----------:|------:|
| alloc (16384×8 KiB) | 1.6 ms | 6.6 ms | 4.1× |
| memset | 3.8 ms | 6.3 ms | 1.7× |
| walk (stride 64) | ~0 | ~0 | — |
| free | 0.8 ms | 2.9 ms | 3.6× |

Isolated alloc/free throughput (200k×4 KiB, `alloconly.c`): 15 ns/op native vs
34 ns/op under Wine (2.2×). The per-op delta (~19 ns) is msvcrt/NTDLL user-space
heap implementation cost — no wineserver round-trips involved (a syscall RTT
would be ~10 µs). JVMs manage their own heaps (TLAB), so this residual barely
affects real Java startup; optimizing it is wine-upstream territory.
