#!/bin/bash
# The tests of run.sh with musl instead of glibc: GCC side and runtime from an
# OpenWrt aarch64 ILP32 musl toolchain (e.g. from
# https://github.com/ilp32-a64/openwrt-ilp32, branch ilp32-25.12), clang with
# --target=...-musl_ilp32. Kernel and init.c from test-ilp32
# (https://github.com/ilp32-a64/test-ilp32).
#   llvm-abi-O0/-O2  GCC <-> clang pointer passing (abi_gcc.c, abi_clang.c, abi_old.S)
#   sqlite-cmp       GCC-built vs clang-built sqlite3 shell on workload.sql
# Environment: SQLFLAGS (extra clang flags for the clang-built sqlite3)
# Usage: run-musl.sh [kernel name]   (default ilp32-6.6-a32, i.e. test-ilp32/qemu/out/Image-<name>)
# Environment: OPENWRT_TOOLCHAIN (OpenWrt staging_dir/toolchain-aarch64_*_ilp32_*_musl,
#              default: the first one in ~/work/openwrt-ilp32),
#              ILP32_TEST (test-ilp32 checkout, default ~/work/test-ilp32),
#              CLANG (default: the clang built by ../../build.sh)
set -euo pipefail
cd "$(dirname "$0")"
D=$PWD
K=${1:-ilp32-6.6-a32}
IT=${ILP32_TEST:-$HOME/work/test-ilp32}
T=aarch64-openwrt-linux-musl_ilp32
OWT=${OPENWRT_TOOLCHAIN:-$(ls -d $HOME/work/openwrt-ilp32/staging_dir/toolchain-aarch64_*_ilp32_gcc-*_musl 2>/dev/null | head -1)}
[ -x "$OWT/bin/$T-gcc" ] || { echo "no OpenWrt ILP32 musl toolchain; set OPENWRT_TOOLCHAIN" >&2; exit 1; }
GCC=$OWT/bin/$T-gcc
export STAGING_DIR=${STAGING_DIR:-$(dirname "$OWT")}
CLANG=${CLANG:-$D/../../build/llvm-22.1.8/bin/clang}
CL=("$CLANG" --target=$T --gcc-toolchain="$OWT" --sysroot="$OWT")
SQLDEF=(-DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION)
O=$D/out-musl
mkdir -p "$O"

if [ ! -f sqlite/shell.c ]; then
	mkdir -p sqlite
	wget -q https://www.sqlite.org/2025/sqlite-amalgamation-3500400.zip -O sqlite/a.zip
	(cd sqlite && unzip -qjo a.zip '*/sqlite3.c' '*/sqlite3.h' '*/shell.c' && rm a.zip)
fi

echo "==> build ($("$CLANG" --version | head -1); $("$GCC" --version | head -1))"
"$GCC" -O2 -Wall -c abi_gcc.c -o "$O/abi_gcc.o"
"$GCC" -c abi_old.S -o "$O/abi_old.o"
for opt in O0 O2; do
	"${CL[@]}" -$opt -Wall -c abi_clang.c -o "$O/abi_clang_$opt.o"
	"$GCC" "$O/abi_gcc.o" "$O/abi_clang_$opt.o" "$O/abi_old.o" -o "$O/llvm-abi-$opt"
done
"${CL[@]}" -O2 ${SQLFLAGS:-} "${SQLDEF[@]}" -Isqlite sqlite/shell.c sqlite/sqlite3.c -lm -o "$O/sqlite3-clang"
"$GCC" -O2 "${SQLDEF[@]}" -Isqlite sqlite/shell.c sqlite/sqlite3.c -lm -o "$O/sqlite3-gcc"
"$GCC" -O2 -Wall sqlite_cmp.c -o "$O/sqlite-cmp"
file "$O/sqlite3-clang" | sed 's/, BuildID[^,]*//'

echo "==> initramfs"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W"/{lib,tests,bin,data,dev,proc,tmp}
"$GCC" -static -O2 -Wall -o "$W/init" "$IT/qemu/init.c"
cp "$OWT/lib/libc.so" "$OWT/lib/libgcc_s.so.1" "$W/lib/"
ln -s libc.so "$W/lib/ld-musl-aarch64_ilp32.so.1"
cp "$O/llvm-abi-O0" "$O/llvm-abi-O2" "$O/sqlite-cmp" "$W/tests/"
cp "$O/sqlite3-gcc" "$O/sqlite3-clang" "$W/bin/"
cp workload.sql "$W/data/"
(cd "$W" && find . | LC_ALL=C sort | cpio -o -H newc --owner=0:0 --quiet) | gzip -9 > "$O/initramfs.cpio.gz"

echo "==> QEMU with Image-$K"
LOG=$O/serial-$K.log
timeout "${QEMU_TIMEOUT:-1200}" qemu-system-aarch64 -M virt -cpu cortex-a35 -smp 2 -m "${QEMU_MEM:-512}" \
	-nographic -no-reboot -kernel "$IT/qemu/out/Image-$K" -initrd "$O/initramfs.cpio.gz" \
	-append "console=ttyAMA0 rdinit=/init panic=-1" < /dev/null > "$LOG" 2>&1 || true
sed 's/\x1b\[[0-9;]*m//g; s/\r$//' "$LOG" | grep -a -E '^(ILP32-TEST|##########|ok |FAIL|PASS|pointer|gcc:|clang:)|^ok$|Kernel panic|Unable to handle'
grep -q 'ILP32-TEST-RESULT: 0 of' "$LOG"
