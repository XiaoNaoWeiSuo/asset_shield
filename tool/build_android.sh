#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
ZSTD_DIR="${ROOT_DIR}/third_party/zstd/lib"

if [[ -z "${NDK_HOME}" ]]; then
  SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [[ -n "${SDK_ROOT}" && -d "${SDK_ROOT}/ndk" ]]; then
    NDK_HOME="$(ls -1d "${SDK_ROOT}/ndk/"* 2>/dev/null | sort -V | tail -n 1 || true)"
  fi
fi

if [[ -z "${NDK_HOME}" ]]; then
  if [[ "$(uname -s)" == "Darwin" && -d "${HOME}/Library/Android/sdk/ndk" ]]; then
    NDK_HOME="$(ls -1d "${HOME}/Library/Android/sdk/ndk/"* 2>/dev/null | sort -V | tail -n 1 || true)"
  elif [[ -d "${HOME}/Android/Sdk/ndk" ]]; then
    NDK_HOME="$(ls -1d "${HOME}/Android/Sdk/ndk/"* 2>/dev/null | sort -V | tail -n 1 || true)"
  fi
fi

if [[ -z "${NDK_HOME}" ]]; then
  echo "ANDROID_NDK_HOME or ANDROID_NDK_ROOT is not set." >&2
  exit 1
fi

HOST_OS="$(uname -s)"
HOST_ARCH="$(uname -m)"
HOST_TAG=""
if [[ "${HOST_OS}" == "Darwin" ]]; then
  if [[ "${HOST_ARCH}" == "arm64" ]]; then
    HOST_TAG="darwin-arm64"
  else
    HOST_TAG="darwin-x86_64"
  fi
elif [[ "${HOST_OS}" == "Linux" ]]; then
  if [[ "${HOST_ARCH}" == "aarch64" || "${HOST_ARCH}" == "arm64" ]]; then
    HOST_TAG="linux-arm64"
  else
    HOST_TAG="linux-x86_64"
  fi
else
  case "${HOST_OS}" in
    MINGW*|MSYS*|CYGWIN*)
      HOST_TAG="windows-x86_64"
      ;;
    *)
      echo "Unsupported host OS: ${HOST_OS}" >&2
      exit 1
      ;;
  esac
fi

TOOLCHAIN="${NDK_HOME}/toolchains/llvm/prebuilt/${HOST_TAG}/bin"
if [[ ! -d "${TOOLCHAIN}" && "${HOST_TAG}" == "darwin-arm64" ]]; then
  FALLBACK="${NDK_HOME}/toolchains/llvm/prebuilt/darwin-x86_64/bin"
  if [[ -d "${FALLBACK}" ]]; then
    TOOLCHAIN="${FALLBACK}"
  fi
fi
if [[ ! -d "${TOOLCHAIN}" ]]; then
  echo "NDK toolchain not found at ${TOOLCHAIN}" >&2
  exit 1
fi

if [[ -n "${ASSET_SHIELD_KEY_BASE64:-}" ]]; then
  if ! command -v dart >/dev/null 2>&1; then
    echo "dart not found; cannot generate embedded key header." >&2
    exit 1
  fi
  dart run "${ROOT_DIR}/tool/gen_embedded_key.dart" --key "${ASSET_SHIELD_KEY_BASE64}"
fi

OUT_DIR="${ROOT_DIR}/android/src/main/jniLibs"
mkdir -p "${OUT_DIR}/arm64-v8a" "${OUT_DIR}/armeabi-v7a" "${OUT_DIR}/x86_64"

build_one() {
  local target=$1
  local out=$2
  "${TOOLCHAIN}/clang" -std=c99 -O2 -fPIC -fvisibility=hidden -shared -pthread \
    -DZSTD_MULTITHREAD=1 -DZSTD_DISABLE_ASM=1 \
    -I "${ZSTD_DIR}" \
    --target="${target}" \
    -o "${out}" \
    "${ROOT_DIR}/native/asset_shield_crypto.c" \
    "${ROOT_DIR}/native/asset_shield_android_jni.c" \
    $(find "${ZSTD_DIR}/common" "${ZSTD_DIR}/compress" "${ZSTD_DIR}/decompress" -name "*.c")
}

build_one aarch64-linux-android21 "${OUT_DIR}/arm64-v8a/libasset_shield_crypto.so"
build_one armv7a-linux-androideabi21 "${OUT_DIR}/armeabi-v7a/libasset_shield_crypto.so"
build_one x86_64-linux-android21 "${OUT_DIR}/x86_64/libasset_shield_crypto.so"

echo "Built Android .so files into ${OUT_DIR}"
