# LLVM/clang for the AArch64 GNU ILP32 ABI

Patches for [LLVM](https://github.com/llvm/llvm-project) that make clang a
working compiler for `aarch64-linux-gnu_ilp32` (AArch64 with 32-bit `long` and
pointers, as GCC's `-mabi=ilp32`), interoperable with GCC-built code such as an
ILP32 glibc.

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

### Notes

- Use `-fwrapv`, not `-fno-strict-overflow` (`-fwrapv` plus `-fwrapv-pointer`),
  when a project needs wrapping signed arithmetic (e.g. CPython). With wrapping
  pointer arithmetic every address has to be computed modulo 2^32 before the
  access, so constant offsets cannot be folded into loads and stores: on the
  SQLite amalgamation at -O2 the ILP32 code grows by 21% (LP64: unchanged).
  Since clang 20 `-fwrapv` alone no longer affects pointer arithmetic.
- lld does not support AArch64 ILP32: link with GNU ld (the driver picks the
  toolchain's `ld`).
- compiler-rt, libunwind, libc++ and the sanitizers are not built or tested for
  ILP32; use the GCC runtime libraries (libgcc, libstdc++).

## Testing

- New lit tests: `clang/test/CodeGen/AArch64/aarch64-gnu-ilp32.c`,
  `clang/test/Driver/aarch64-gnu-ilp32.c`,
  `llvm/test/CodeGen/AArch64/ilp32-gnu-pointer-extend.ll`.
- `llvm/test/CodeGen/AArch64`, `llvm/test/MC/AArch64`,
  `clang/test/CodeGen/AArch64` and `clang/test/Driver` pass (in an
  AArch64-only build the tests that use the host's default triple fail with
  "unknown target triple", unrelated to these patches).
- Predefined type macros compared with GCC 14 `-mabi=ilp32`; GCC 10.5, 13 and
  14 checked for their pointer passing (unchanged across versions).
- Not yet run on hardware.

## License

The patches are contributions to LLVM and are under the same license, Apache
License v2.0 with LLVM Exceptions (see `LICENSE`).
