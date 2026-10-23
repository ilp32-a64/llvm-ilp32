# Tests

## LLVM and clang

- New lit tests: `clang/test/CodeGen/AArch64/aarch64-gnu-ilp32.c`,
  `clang/test/Driver/aarch64-gnu-ilp32.c`, `clang/test/Driver/aarch64-musl-ilp32.c`,
  `llvm/test/CodeGen/AArch64/ilp32-gnu-pointer-extend.ll`,
  `ilp32-gnu-fastisel-args.ll`, `ilp32-gnu-cross-block-pointer.ll`,
  `ilp32-gnu-address-offset-fold.ll`, `note-gnu-property-ilp32.ll`; additions
  to `TripleTest.cpp`, `llvm/test/MC/AArch64/arm64-ilp32.s` and the
  `misched-fusion` tests.
- `llvm/test/CodeGen/AArch64`, `llvm/test/MC/AArch64`,
  `clang/test/CodeGen/AArch64` and `clang/test/Driver` pass (in an
  AArch64-only build the tests that use the host's default triple fail with
  "unknown target triple", unrelated to these patches).
- To run them, configure a separate build with the test tools (`TESTS` only
  takes effect when a build directory is configured), then run `llvm-lit`:

  ```
  TESTS=ON BUILD=build/llvm-tests ./build.sh clang llc FileCheck not count split-file
  build/llvm-tests/bin/llvm-lit -sv src/llvm-project-22.1.8/llvm/test/CodeGen/AArch64       src/llvm-project-22.1.8/clang/test/Driver
  ```
- Predefined type macros compared with GCC 14 `-mabi=ilp32`; GCC 10.5, 13 and
  14 checked for their pointer passing (unchanged across versions).

## QEMU

`qemu/run.sh` runs programs under QEMU system emulation with an ILP32 kernel
and the glibc ILP32 toolchain (GCC 14.3, glibc 2.41) from
[test-ilp32](https://github.com/ilp32-a64/test-ilp32):

- `llvm-abi-O0`, `llvm-abi-O2`: GCC-compiled code passes clang-compiled code
  pointers with garbage in the upper 32 bits (in a register, as a ninth
  argument on the stack, as a return value), and glibc `qsort` calls a clang
  comparator. Control: the same calls into code shaped like the output of LLVM
  before patch 0002 must crash with SIGSEGV.
- `sqlite-cmp`: the sqlite3 shell built by clang alone (compile and link) and
  the one built by GCC must print identical output for `workload.sql`.

All pass with the ilp32-6.12.y kernel and glibc 2.41 (2026-10-23).

`qemu/run-musl.sh` runs the same tests with musl: the GCC side and the runtime
come from an OpenWrt aarch64 ILP32 musl toolchain, clang uses
`--target=aarch64-openwrt-linux-musl_ilp32`. All pass with the ilp32-6.12.y
kernel (2026-10-23).

## CPython

- Cross-built by clang (tail-calling interpreter; also with PGO and ThinLTO),
  CPython 3.14.9 passes the same regrtest subset under QEMU as the GCC build:
  65 of 68 test files; the 3 failures (`test_os`, `test_posix`, `test_sys`)
  come from the minimal test system.
- On the Cortex-A35 board (see [benchmarks](../docs/benchmarks.md)), the
  clang-built CPython (default ThinLTO import limit) passes `test_json`,
  `test_re`, `test_math`, `test_float` and `test_struct`, and the PGO training
  run (`-m test --pgo`, 43 test files).

## Pointer authentication

- C++ exceptions through `pac-ret` frames (clang `-O2 -mbranch-protection=pac-ret`,
  dynamically linked PIE, 100 exceptions): with the libgcc ILP32 unwinder fix
  ([test-ilp32](https://github.com/ilp32-a64/test-ilp32) `glibc/toolchain/patches/`,
  OpenWrt patch 990) all pass, without it the program crashes with SIGSEGV.
  Checked on a Cortex-A35 board (without pointer authentication) and in QEMU
  (`-cpu max` and cortex-a35).
- Patch 0011: with `-mbranch-protection=standard`, GNU ld accepts the ELF32
  `.note.gnu.property` and keeps the BTI/PAC markings in the output when all
  input objects have them (before 0011 it reported "corrupt GNU_PROPERTY_TYPE"
  and dropped them).
