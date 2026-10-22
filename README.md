# LLVM/clang for the AArch64 GNU ILP32 ABI

Patches for [LLVM](https://github.com/llvm/llvm-project) that make clang a
working compiler for `aarch64-linux-gnu_ilp32` and `aarch64-linux-musl_ilp32`
(AArch64 with 32-bit `long` and pointers, as GCC's `-mabi=ilp32`),
interoperable with GCC-built code such as an ILP32 glibc or musl, plus code
generation improvements for the ABI.

LLVM's AArch64 back end has supported the GNU ILP32 ABI since 2021 (review
D94143). The clang front end and driver never got the matching support (review
D104931 was not merged), and the back end follows Apple arm64_32 rules for
pointer extension that differ from GCC and AAPCS64.

## Patches (LLVM 22.1.8)

| Patch | Change |
|---|---|
| `0001` | clang: GNU ILP32 data model. 32-bit `long`/pointers, `int64_t` and `intmax_t` are `long long`, `intptr_t` is `int`, `wchar_t` is `unsigned int`, as with GCC 14 `-mabi=ilp32`. Based on D104931, which made `wchar_t` signed by mistake. |
| `0002` | AArch64: zero-extend received pointers. With AAPCS64 and GCC the upper 32 bits of a pointer in an X register or an 8-byte stack slot are unspecified and the receiver clears them; LLVM assumed the sender had done it (the arm64_32 rule). Without this, code built by LLVM can use garbage address bits when called from GCC-built code or when using a pointer returned by it. |
| `0003` | Driver: `-mabi=ilp32`/`-mabi=lp64`, dynamic linker `/lib/ld-linux-aarch64[_be]_ilp32.so.1`, GNU ld emulation `aarch64linux32[b]`, `libilp32` library directories. clang can compile and link against a GCC `aarch64-linux-gnu_ilp32` toolchain on its own. |
| `0004` | AArch64: no pointer extension for local functions whose address is not taken, and for results of direct calls to local functions (all producers are compiled by LLVM). |
| `0005` | AArch64: no pointer extension for LLVM-only calling conventions (`preserve_none`/`_most`/`_all`, `fastcc`, `tailcc`, `coldcc`, GHC, Swift), which GCC does not implement. CPython 3.14's tail-calling interpreter: 685 of 693 `mov wN, wN` in `ceval.c` go away. |
| `0006` | `musl_ilp32` environment (`aarch64[_be]-*-linux-musl_ilp32`, as in OpenWrt's ILP32 toolchain) with the same ABI as `gnu_ilp32`. Driver: `-mabi=ilp32`/`-mabi=lp64` with musl, dynamic linker `/lib/ld-musl-aarch64[_be]_ilp32.so.1`, libraries in `lib`. |
| `0007` | Cortex-A35 tuning: the Cortex-A53 features (fusions, scheduling options), as GCC does. `-mcpu=cortex-a35` had none. |
| `0008` | AArch64 FastISel: leave GNU ILP32 arguments to SelectionDAG, which zero-extends pointers. Fixes pointer arguments at `-O0`. |
| `0009` | SelectionDAG: a pointer read from another block is known to be zero-extended (32-bit pointers in 64-bit registers), so it is not extended again. |
| `0010` | AArch64: fold constant offsets of less than a page into load and store addresses also for GEPs without `inbounds` (computed modulo 2^32), on Linux. Off with `-mllvm -aarch64-ilp32-fold-address-offsets=false`. |

## Build

Needs git, cmake, ninja, a host C++ compiler, and `binutils-dev` for the
LLVMgold plugin (LTO through GNU ld). The build's default target is
`aarch64-linux-gnu_ilp32`, so `--target` can be left out.

```
./build.sh                      # clang + tools, about 1 hour on 4 cores
TESTS=ON ./build.sh llc FileCheck not count split-file   # for lit tests
```

`git am` needs a git identity (`user.name`/`user.email`).

## Use

With a GCC ILP32 toolchain installed under `$T` (target triple directory
`aarch64-linux-gnu_ilp32`, sysroot with `libilp32`):

```
clang --target=aarch64-linux-gnu_ilp32 --gcc-toolchain=$T \
      --sysroot=$T/aarch64-linux-gnu_ilp32/sysroot -O2 hello.c -o hello
# or: clang --target=aarch64-linux-gnu -mabi=ilp32 ...
```

The result is an ELF32 AArch64 executable for `/lib/ld-linux-aarch64_ilp32.so.1`.

With an OpenWrt aarch64 ILP32 musl toolchain
(`staging_dir/toolchain-aarch64_*_ilp32_*_musl`) in `$O`:

```
clang --target=aarch64-openwrt-linux-musl_ilp32 --gcc-toolchain=$O --sysroot=$O \
      -O2 hello.c -o hello
```

### Notes

- Use `-fwrapv`, not `-fno-strict-overflow` (`-fwrapv` plus `-fwrapv-pointer`),
  when a project needs wrapping signed arithmetic (e.g. CPython). With wrapping
  pointer arithmetic every address has to be computed modulo 2^32 before the
  access. Patch 0010 still folds offsets of less than a page, but indexed
  addresses cost extra instructions: on the SQLite amalgamation at -O2 the
  ILP32 code is 2.7% larger than LP64 (21% before 0010), against 1.4% with
  `-fwrapv`. Since clang 20 `-fwrapv` alone no longer affects pointer
  arithmetic.
- For the Cortex-A35 use `-mcpu=cortex-a35` (with patch 0007). clang enables
  the crypto extension for it by default; GCC needs `-mcpu=cortex-a35+crypto`.
- lld does not support AArch64 ILP32: link with GNU ld (the driver picks the
  toolchain's `ld`).
- compiler-rt, libunwind, libc++ and the sanitizers are not built or tested for
  ILP32; use the GCC runtime libraries (libgcc, libstdc++).

## Results

Static instruction counts (`llvm-objdump`), clang with these patches:

| Code | Before 0009/0010 | With 0009/0010 |
|---|---:|---:|
| SQLite amalgamation, `-O2 -fwrapv`, ILP32 vs LP64 | +2.0% | +1.4% |
| SQLite amalgamation, `-O2 -fno-strict-overflow`, ILP32 vs LP64 | +20.7% | +2.7% |
| CPython 3.14.9 (`-O3 -fwrapv`, tail-calling interpreter), ILP32 | 731,977 | 719,029 |

For comparison, GCC 14 `-mabi=ilp32` is 1.9% larger than `-mabi=lp64` on the
SQLite amalgamation (`-O2 -fwrapv`, same headers). Run time has not been
measured on hardware yet.

## Testing

- New lit tests: `clang/test/CodeGen/AArch64/aarch64-gnu-ilp32.c`,
  `clang/test/Driver/aarch64-gnu-ilp32.c`, `clang/test/Driver/aarch64-musl-ilp32.c`,
  `llvm/test/CodeGen/AArch64/ilp32-gnu-pointer-extend.ll`,
  `ilp32-gnu-fastisel-args.ll`, `ilp32-gnu-cross-block-pointer.ll`,
  `ilp32-gnu-address-offset-fold.ll`; additions to `TripleTest.cpp`,
  `llvm/test/MC/AArch64/arm64-ilp32.s` and the `misched-fusion` tests.
- `llvm/test/CodeGen/AArch64`, `llvm/test/MC/AArch64`,
  `clang/test/CodeGen/AArch64` and `clang/test/Driver` pass (in an
  AArch64-only build the tests that use the host's default triple fail with
  "unknown target triple", unrelated to these patches).
- Predefined type macros compared with GCC 14 `-mabi=ilp32`; GCC 10.5, 13 and
  14 checked for their pointer passing (unchanged across versions).
- `tests/qemu/run.sh` runs programs under QEMU system emulation with an ILP32
  kernel (from [test-ilp32](https://github.com/ilp32-a64/test-ilp32)):
  - `llvm-abi-O0`, `llvm-abi-O2`: GCC-compiled code passes clang-compiled code
    pointers with garbage in the upper 32 bits (in a register, as a ninth
    argument on the stack, as a return value), and glibc `qsort` calls a clang
    comparator. Control: the same calls into code shaped like the output of
    LLVM before patch 0002 must crash with SIGSEGV.
  - `sqlite-cmp`: the sqlite3 shell built by clang alone (compile and link) and
    the one built by GCC must print identical output for `workload.sql`.

  All pass with the ilp32-6.6 kernel (2026-10-22).
- `tests/qemu/run-musl.sh` runs the same tests with musl: the GCC side and the
  runtime come from an OpenWrt aarch64 ILP32 musl toolchain, clang uses
  `--target=aarch64-openwrt-linux-musl_ilp32`. All pass (2026-10-22).
- CPython 3.14.9 cross-built by clang (tail-calling interpreter; also with PGO
  and ThinLTO) passes the same regrtest subset under QEMU as the GCC build:
  65 of 68 test files, the 3 failures (`test_os`, `test_posix`, `test_sys`)
  come from the minimal test system.
- Not yet run on hardware.

## License

The patches are contributions to LLVM and are under the same license, Apache
License v2.0 with LLVM Exceptions (see `LICENSE`).
