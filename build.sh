#!/bin/bash
# Build clang/LLVM with the AArch64 GNU ILP32 patches.
#
#   ./build.sh [ninja targets...]
#
# Environment:
#   LLVM_VERSION  upstream release to patch (default 22.1.8; needs patches/llvm-$LLVM_VERSION)
#   SRC           llvm-project checkout to create/use (default ./src/llvm-project-$LLVM_VERSION)
#   BUILD         build directory (default ./build/llvm-$LLVM_VERSION)
#   JOBS          parallel compile jobs (default: number of CPUs)
#   TESTS         ON to also configure the lit test tools (default OFF)
#
# The source is a shallow clone of the llvmorg-$LLVM_VERSION tag; the patches are
# applied with "git am" on a branch named ilp32-$LLVM_VERSION. Only the AArch64
# target is built. Default targets: clang, the LLVMgold plugin when binutils
# plugin-api.h is installed, and the usual binutils-style tools.
set -euo pipefail

TOP=$(cd "$(dirname "$0")" && pwd)
V=${LLVM_VERSION:-22.1.8}
SRC=${SRC:-$TOP/src/llvm-project-$V}
BUILD=${BUILD:-$TOP/build/llvm-$V}
JOBS=${JOBS:-$(nproc)}
TESTS=${TESTS:-OFF}
PATCHES=$TOP/patches/llvm-$V

[ -d "$PATCHES" ] || { echo "no patches for LLVM $V in $PATCHES" >&2; exit 1; }

if [ ! -d "$SRC/.git" ]; then
	git clone --depth 1 --branch "llvmorg-$V" https://github.com/llvm/llvm-project.git "$SRC"
fi
cd "$SRC"
if ! git rev-parse -q --verify "refs/heads/ilp32-$V" > /dev/null; then
	git switch -c "ilp32-$V" "llvmorg-$V"
	git am --keep-cr "$PATCHES"/*.patch
fi

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
	targets=(clang llvm-ar llvm-ranlib llvm-nm llvm-objdump llvm-readelf llvm-profdata)
	if [ -f /usr/include/plugin-api.h ]; then
		targets+=(LLVMgold)
	fi
fi

if [ ! -f "$BUILD/build.ninja" ]; then
	cmake -G Ninja -S "$SRC/llvm" -B "$BUILD" \
		-DLLVM_ENABLE_PROJECTS=clang -DLLVM_TARGETS_TO_BUILD=AArch64 \
		-DLLVM_DEFAULT_TARGET_TRIPLE=aarch64-linux-gnu_ilp32 \
		-DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_ASSERTIONS=OFF \
		-DLLVM_PARALLEL_COMPILE_JOBS="$JOBS" -DLLVM_PARALLEL_LINK_JOBS=1 \
		-DLLVM_INCLUDE_TESTS="$TESTS" -DLLVM_INCLUDE_BENCHMARKS=OFF \
		-DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_DOCS=OFF \
		-DLLVM_BINUTILS_INCDIR=/usr/include
fi
ninja -C "$BUILD" "${targets[@]}"
echo "clang: $BUILD/bin/clang"
