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

For reference, the same workload shape as Java (HeapTouch3) measured earlier:
native ARM64 JVM 0.06 s vs x86_64 JVM under Rosetta in the x86_64 engine
2.17 s — a 36× translation tax. Executing native aarch64 PE code under the
ARM64 Wine engine removes ≈99% of that gap at the execution-engine level
(residual 25% = wineserver round-trips + PE loader paths).

Build commands:

    # native
    clang -O2 cpuloop.c -o cpuloop-native

    # PE (64K-aligned)
    llvm-mingw/bin/aarch64-w64-mingw32-clang -O2 \
        -Wl,--section-alignment=65536 -Wl,--file-alignment=65536 \
        cpuloop.c -o cpuloop-64k.exe

Run the PE build in a prefix of the ARM64 engine (`wine C:\\bench\\cpuloop-64k.exe`).
