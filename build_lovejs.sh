#!/usr/bin/env bash
#
# Build the love.js engine binaries (love.js / love.wasm / love.worker.js) from a
# megasource checkout and stage them into src/{compat,release}.
#
# Pinned toolchain: emsdk 2.0.0 + Ninja (newer Emscripten removed getMemory, which
# the 11.5 tree still uses).
#
# Usage:
#   ./build_lovejs.sh --emsdk ~/emsdk --megasource ~/megasource
#   ./build_lovejs.sh --emsdk ~/emsdk --megasource ~/megasource --love ~/love
#   ./build_lovejs.sh --emsdk ~/emsdk -m ~/megasource --targets compat
#
# Or through the environment: EMSDK, MEGASOURCE, LOVE.
#
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"

emsdk="${EMSDK:-}"
megasource="${MEGASOURCE:-}"
love="${LOVE:-}"
out="$root/src"
build="$root/build"
targets="compat release"
jobs=""
clean=0

usage() {
	cat <<EOF
usage: $(basename "$0") --emsdk DIR --megasource DIR [options]

  -e, --emsdk DIR       emsdk checkout (must be 2.0.0); defaults to \$EMSDK
  -m, --megasource DIR  megasource checkout; defaults to \$MEGASOURCE
  -l, --love DIR        a love checkout to build instead of megasource's
                        libs/love submodule (passed as -DMEGA_LOVE); defaults to \$LOVE
      --out DIR         where love.js / love.wasm / love.worker.js go [<repo>/src]
      --build DIR       build directory [<repo>/build]
      --targets LIST    comma-separated: compat,release [compat,release]
      --jobs N          parallel jobs [number of CPUs]
      --clean           delete the build directory first
  -h, --help            this message
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		-e|--emsdk) emsdk="${2:-}"; shift 2 ;;
		-m|--megasource) megasource="${2:-}"; shift 2 ;;
		-l|--love) love="${2:-}"; shift 2 ;;
		--out) out="${2:-}"; shift 2 ;;
		--build) build="${2:-}"; shift 2 ;;
		--targets) targets="${2:-}"; shift 2 ;;
		--jobs) jobs="${2:-}"; shift 2 ;;
		--clean) clean=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
	esac
done

if [ -z "$emsdk" ] || [ -z "$megasource" ]; then
	usage >&2
	exit 1
fi

for dir in "$emsdk" "$megasource"; do
	[ -d "$dir" ] || { echo "not a directory: $dir" >&2; exit 1; }
done
if [ -n "$love" ] && [ ! -d "$love" ]; then
	echo "not a directory: $love" >&2
	exit 1
fi

emsdk_env="$emsdk/emsdk_env.sh"
[ -f "$emsdk_env" ] || { echo "emsdk_env.sh not found in '$emsdk' (expected emsdk 2.0.0)" >&2; exit 1; }

# shellcheck source=/dev/null
. "$emsdk_env"

if ! command -v emcmake >/dev/null 2>&1; then
	echo "emcmake not found after sourcing $emsdk_env" >&2
	exit 1
fi
if ! command -v ninja >/dev/null 2>&1; then
	echo "ninja not found; install it (apt: ninja-build, brew: ninja, winget: Ninja-build.Ninja)" >&2
	exit 1
fi

if [ -z "$jobs" ]; then
	jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
fi
[ "$jobs" -ge 1 ] 2>/dev/null || jobs=4

echo "emcc:  $(command -v emcc)"
echo "ninja: $(command -v ninja)"

for target in ${targets//,/ }; do
	case "$target" in
		compat|release) ;;
		*) echo "unknown target: $target (expected compat or release)" >&2; exit 1 ;;
	esac

	build_dir="$build/$target"
	if [ "$clean" -eq 1 ]; then
		rm -rf "$build_dir"
	fi

	cmake_args=(
		-S "$megasource"
		-B "$build_dir"
		-G Ninja
		-DLOVE_JIT=0
		-DCMAKE_BUILD_TYPE=Release
		# LÖVE 11.5's cmake_minimum_required predates 3.5; without this CMake >= 4 refuses to configure.
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5
	)
	if [ "$target" = "compat" ]; then
		cmake_args+=(-DLOVEJS_COMPAT=1)
	fi
	if [ -n "$love" ]; then
		cmake_args+=("-DMEGA_LOVE=$love")
	fi

	echo "=== [$target] configure ==="
	emcmake cmake "${cmake_args[@]}"

	echo "=== [$target] build ==="
	cmake --build "$build_dir" --parallel "$jobs"

	engine_dir="$build_dir/love"
	out_dir="$out/$target"
	mkdir -p "$out_dir"

	staged=""
	for file in love.js love.wasm love.worker.js; do
		if [ -f "$engine_dir/$file" ]; then
			cp "$engine_dir/$file" "$out_dir/$file"
			staged="$staged $file"
		fi
	done
	[ -n "$staged" ] || { echo "no engine binaries produced in $engine_dir" >&2; exit 1; }

	echo "=== [$target] staged:$staged -> $out_dir ==="
done

echo "love.js engine build complete."
