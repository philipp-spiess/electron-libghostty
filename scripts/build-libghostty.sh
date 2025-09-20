#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMODULE_DIR="${ROOT_DIR}/third_party/libghostty"
ARTIFACT_ROOT="${ROOT_DIR}/native-deps"
LIB_OUT_DIR="${ARTIFACT_ROOT}/lib/macos"
INCLUDE_OUT_DIR="${ARTIFACT_ROOT}/include"
RESOURCE_OUT_DIR="${ARTIFACT_ROOT}/share/ghostty"

print_err() {
  echo "[libghostty] $*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    print_err "Missing required command: $1"
    exit 1
  fi
}

require_cmd zig
require_cmd rsync
require_cmd lipo

mkdir -p "${LIB_OUT_DIR}" "${INCLUDE_OUT_DIR}" "${RESOURCE_OUT_DIR}"

ZIG_ARGS=("-Dapp-runtime=none" "-Demit-xcframework=true" "-Dxcframework-target=universal" "-Doptimize=ReleaseFast" "-Dstrip")
if [[ $# -gt 0 ]]; then
  ZIG_ARGS+=("$@")
fi

print_err "Running zig build ${ZIG_ARGS[*]}"
(
  cd "${SUBMODULE_DIR}"
  zig build "${ZIG_ARGS[@]}"
)

XCFRAMEWORK_PATH="${SUBMODULE_DIR}/macos/GhosttyKit.xcframework"
if [[ ! -d "${XCFRAMEWORK_PATH}" ]]; then
  print_err "xcframework not produced at ${XCFRAMEWORK_PATH}"
  exit 1
fi

STATIC_SRC=$(find "${XCFRAMEWORK_PATH}" -type f -name 'libghostty.a' -path '*macos*' -print 2>/dev/null | sort | head -n 1)
if [[ -z "${STATIC_SRC}" ]]; then
  print_err "No macOS static library found in xcframework"
  exit 1
fi
cp "${STATIC_SRC}" "${LIB_OUT_DIR}/libghostty.a"
print_err "Installed static library -> ${LIB_OUT_DIR}/libghostty.a"
if lipo -info "${LIB_OUT_DIR}/libghostty.a" >/dev/null 2>&1; then
  print_err "Static slices: $(lipo -info "${LIB_OUT_DIR}/libghostty.a")"
fi

DYLIB_SRC=$(find "${XCFRAMEWORK_PATH}" -type f -name 'libghostty.dylib' -path '*macos*' -print 2>/dev/null | sort | head -n 1)
if [[ -n "${DYLIB_SRC}" ]]; then
  cp "${DYLIB_SRC}" "${LIB_OUT_DIR}/libghostty.dylib"
  print_err "Installed dynamic library -> ${LIB_OUT_DIR}/libghostty.dylib"
  if lipo -info "${LIB_OUT_DIR}/libghostty.dylib" >/dev/null 2>&1; then
    print_err "Dynamic slices: $(lipo -info "${LIB_OUT_DIR}/libghostty.dylib")"
  fi
  if [[ -d "${DYLIB_SRC}.dSYM" ]]; then
    rsync -a --delete "${DYLIB_SRC}.dSYM/" "${LIB_OUT_DIR}/libghostty.dSYM/"
    print_err "Installed debug symbols -> ${LIB_OUT_DIR}/libghostty.dSYM"
  fi
else
  print_err "No macOS dynamic library; continuing with static archive only"
fi

cp "${SUBMODULE_DIR}/include/ghostty.h" "${INCLUDE_OUT_DIR}/ghostty.h"
print_err "Installed header -> ${INCLUDE_OUT_DIR}/ghostty.h"

RESOURCE_SRC="${SUBMODULE_DIR}/zig-out/share/ghostty"
if [[ ! -d "${RESOURCE_SRC}" ]]; then
  RESOURCE_SRC="${SUBMODULE_DIR}/dist/share/ghostty"
  if [[ ! -d "${RESOURCE_SRC}" ]]; then
    print_err "No ghostty resources directory found"
    exit 1
  fi
fi
rsync -a --delete "${RESOURCE_SRC}/" "${RESOURCE_OUT_DIR}/"
print_err "Synced resources -> ${RESOURCE_OUT_DIR}"

print_err "libghostty build complete"
