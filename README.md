# clang for AArch64 ILP32

Patches that make clang 22 compile AArch64 ILP32 code (32-bit `long` and
pointers) for glibc (`aarch64-linux-gnu_ilp32`) and musl
(`aarch64-linux-musl_ilp32`). The code links and runs with libraries built by
GCC.

Upstream LLVM supports ILP32 only in the back end: the clang front end was
never finished, and the back end passes pointers in a way that is not
compatible with GCC. These patches fill both gaps.

On Cortex-A53 and Cortex-A35 boards, CPython 3.13 built for ILP32 with this
clang runs at **97–99% of the speed** of Debian's own LP64 `python3.13` and uses
**about 20% less memory**. Built the same way, ILP32 uses 30% less memory than
LP64. Patch `0010` alone makes it 2.6–3.6% faster.

## Build clang

Needs git, cmake, ninja, a C++ compiler and `binutils-dev`.

```
./build.sh        # applies the patches and builds clang, about 1 hour on 4 cores
```

## Use

With a GCC ILP32 toolchain in `$T` (for example the one built by
[test-ilp32](https://github.com/ilp32-a64/test-ilp32)):

```
clang --target=aarch64-linux-gnu_ilp32 --gcc-toolchain=$T \
      --sysroot=$T/aarch64-linux-gnu_ilp32/sysroot -O2 hello.c -o hello
```

With an OpenWrt ILP32 musl toolchain in `$O`:

```
clang --target=aarch64-openwrt-linux-musl_ilp32 --gcc-toolchain=$O --sysroot=$O \
      -O2 hello.c -o hello
```

### Notes

- Link with GNU ld; lld does not support ILP32.
- Use the GCC runtime libraries (libgcc, libstdc++); compiler-rt and libc++ do
  not support ILP32 yet.
- For wrapping signed arithmetic use `-fwrapv`, not `-fno-strict-overflow`,
  which also wraps pointer arithmetic and makes the code larger.
- With ThinLTO, keep the default import limit: `-import-instr-limit=30` saved
  1–2% memory on CPython but cost 1.0–1.3% speed.
- Pass back-end options (`-mllvm ...`) to an LTO link as
  `-Wl,-plugin-opt=...`; at compile time they do not reach LTO code generation.
- Known problems in upstream LLVM that these patches do not fix are listed in
  the [issues](https://github.com/ilp32-a64/llvm-ilp32/issues).

## Performance (CPython, Cortex-A53 and Cortex-A35)

Speed relative to Debian 13's own `python3.13` (LP64, GCC); memory is the max RSS.

| Build | A53 | A35 | Memory |
|---|---:|---:|---:|
| Debian `python3.13`, LP64, GCC | 1.000 | 1.000 | 15.7 MiB |
| 3.13, LP64, GCC, made like Debian's | 1.002 | 0.997 | 15.5 MiB |
| 3.13, ILP32, GCC | 0.976 | 0.940 | 10.9 MiB (-31%) |
| 3.13, ILP32, clang with these patches | 0.991 | 0.968 | 12.6 MiB (-20%) |
| 3.14, ILP32, GCC | 1.035 | 0.988 | 11.5 MiB (-27%) |
| 3.14, ILP32, clang with these patches | 1.041 | 0.984 | 12.9 MiB (-18%) |

All builds are non-PIE, like Debian's `python3.13`, and are made the way Debian
builds that interpreter (PGO + LTO, the same flags); geometric mean of 9
benchmarks. Method, per-patch effects and a code size analysis:
[docs/benchmarks.md](docs/benchmarks.md).

## Patches (LLVM 22.1.8)

| Patch | Change |
|---|---|
| `0001` | ILP32 data types, as in GCC |
| `0002` | Clear the upper 32 bits of received pointers (the key to working with GCC code) |
| `0003` | Driver: `-mabi=ilp32`, dynamic linker, library paths |
| `0004`–`0005` | Skip pointer extensions that are not needed |
| `0006` | musl ILP32 target |
| `0007` | Cortex-A35 tuning |
| `0008` | Pointer arguments at `-O0` |
| `0009`–`0010` | Smaller ILP32 code |
| `0011` | BTI/PAC markings for ILP32 (ELF32 layout) |
| `0012` | Keep 32x32→64 multiplies (`smull`/`smaddl`) when promoting extensions; not ILP32-specific |

Each patch's commit message has the details.

## Testing

- The LLVM and clang AArch64 tests and the new ILP32 tests pass.
- In QEMU, code built by clang and by GCC works together, with glibc and with musl.
- CPython built by clang passes the same tests as the GCC build in QEMU, and
  selected tests on the board.

Details: [tests/README.md](tests/README.md).

## Upstreaming

The author does not plan to submit these patches upstream. Anyone is welcome
to submit them under their own name; please keep the original
`Signed-off-by`. Maintainers are welcome too, including for Rust's ILP32
target. `0007` does not depend on ILP32 and can go on its own.

## License

Apache License v2.0 with LLVM Exceptions (see `LICENSE`).
