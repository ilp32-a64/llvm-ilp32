# clang for AArch64 ILP32

Patches that make clang 22 compile AArch64 ILP32 code (32-bit `long` and
pointers) for glibc (`aarch64-linux-gnu_ilp32`) and musl
(`aarch64-linux-musl_ilp32`). The code links and runs with libraries built by
GCC.

Upstream LLVM supports ILP32 only in the back end: the clang front end was
never finished, and the back end passes pointers in a way that is not
compatible with GCC. These patches fill both gaps.

On a Cortex-A35 board, CPython built for ILP32 with this clang is **9% faster**
than the LP64 build and uses **23–25% less memory**.

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
- With ThinLTO, link with `-Wl,-plugin-opt=-import-instr-limit=30`: same speed,
  about 0.3 MB less memory.
- For the Cortex-A35 use `-mcpu=cortex-a35`.

## Performance (Cortex-A35 board, CPython 3.14.9)

| Build | Speed | Memory |
|---|---:|---:|
| LP64, GCC 14 | 1.00 | 17.0 MB |
| ILP32, GCC 14 | 1.02 | 11.4 MB (-33%) |
| ILP32, clang (PGO + ThinLTO + tail calls) | 1.09 | 13.0 MB (-23%) |
| ILP32, clang, with `-import-instr-limit=30` | 1.09 | 12.7 MB (-25%) |
| armhf, GCC 14 | 1.00 | 10.6 MB (-38%) |

All builds use PGO and LTO; geometric mean of 9 benchmarks. Method, SQLite,
per-benchmark results and a code size analysis:
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
