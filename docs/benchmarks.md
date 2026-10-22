# Benchmarks

## CPython on a Cortex-A35 board

Board: Cortex-A35, 2 cores at 700 MHz, 512 MB RAM, the board's own glibc 2.41.
CPython 3.14.9, all builds with PGO trained on the board (`-m test --pgo`) and
LTO (clang: ThinLTO), `-fwrapv -mcpu=cortex-a35 -mno-outline-atomics` (GCC:
`+crypto`). Nine small benchmarks (nbody, fannkuch, spectral_norm, calls,
sorting, generators, strings and dicts, regex, json), 5 runs each, geometric
mean of the medians (2026-10-23).

| CPython 3.14.9 | Speed vs LP64 | Max RSS | SQLite speedtest1 vs LP64 |
|---|---:|---:|---:|
| LP64, GCC 14.2, PGO + LTO | 1.000 | 17.0 MB | 1.000 (15.52 s) |
| ILP32, GCC 14.3, PGO + LTO | 1.018 | 11.4 MB (-33%) | 1.013 |
| ILP32, clang 22 + these patches, PGO + ThinLTO + tail-calling interpreter (default import limit 100) | 1.089 | 13.0 MB (-23%) | 0.958 |
| ILP32, the same, linked with `-Wl,-plugin-opt=-import-instr-limit=30` | 1.09¹ | 12.7 MB (-25%) | 0.958² |
| armhf (Thumb-2), GCC 14.2, PGO + LTO | 1.004 | 10.6 MB (-38%) | 0.859 |

¹ Measured against the ILP32 GCC build in a separate run (1.075 × 1.018);
within noise of the default limit.

² SQLite is a separate `-O2` build without PGO or LTO, so the import limit
does not apply; there clang is 5% slower than GCC.

- ILP32 keeps the AArch64 speed and comes close to armhf in memory; armhf is
  14% slower on SQLite. `/proc/self/smaps` shows where the memory goes: the
  heap is 67% and other anonymous memory 49% smaller than with LP64.
- The clang build uses 1.6 MB more than the GCC ILP32 build (1.3 MB with
  limit 30), almost all of it code: its `.text` is 4.05 MB (3.82 MB) against
  2.88 MB. The cause is ThinLTO's cross-module importing: without LTO, clang's
  code is 7% smaller than GCC's, and ThinLTO adds 23%. Limit 30 saves about
  0.3 MB of resident code at no speed cost; a limit of 10 saves a little more
  but is 4% slower.
- The GCC ILP32 toolchain used here does not default to PIE; the others do.
  PIE costs about 130 KB (RELRO) in this test.
- Per benchmark, with either import limit, clang is best on regex (+15% vs GCC
  ILP32) and worst on json (-6%).

## Static code size

Static instruction counts (`llvm-objdump`), clang with these patches:

| Code | Before 0009/0010 | With 0009/0010 |
|---|---:|---:|
| SQLite amalgamation, `-O2 -fwrapv`, ILP32 vs LP64 | +2.0% | +1.4% |
| SQLite amalgamation, `-O2 -fno-strict-overflow`, ILP32 vs LP64 | +20.7% | +2.7% |
| CPython 3.14.9 (`-O3 -fwrapv`, tail-calling interpreter), ILP32 | 731,977 | 719,029 |

For comparison, GCC 14 `-mabi=ilp32` is 1.9% larger than `-mabi=lp64` on the
SQLite amalgamation (`-O2 -fwrapv`, same headers).

### Why `-fwrapv` and not `-fno-strict-overflow`

`-fno-strict-overflow` is `-fwrapv` plus `-fwrapv-pointer`. With wrapping
pointer arithmetic every address has to be computed modulo 2^32 before the
access. Patch 0010 still folds offsets of less than a page, but indexed
addresses cost extra instructions: 2.7% larger than LP64 on SQLite, against
1.4% with `-fwrapv`. Since clang 20, `-fwrapv` alone no longer affects pointer
arithmetic.
