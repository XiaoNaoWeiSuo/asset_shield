#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/build/macos"
FRAMEWORK_DIR="${ROOT_DIR}/macos/Frameworks"
ZSTD_DIR="${ROOT_DIR}/third_party/zstd/lib"
MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
HEADERS_DIR="${OUT_DIR}/headers"

mkdir -p "${OUT_DIR}" "${FRAMEWORK_DIR}"
rm -rf "${FRAMEWORK_DIR}/AssetShieldCrypto.xcframework"
rm -rf "${HEADERS_DIR}"
mkdir -p "${HEADERS_DIR}"
cp -f "${ROOT_DIR}/native/asset_shield_crypto.h" "${HEADERS_DIR}/asset_shield_crypto.h"

if [[ -n "${ASSET_SHIELD_KEY_BASE64:-}" ]]; then
  if ! command -v dart >/dev/null 2>&1; then
    echo "dart not found; cannot generate embedded key header." >&2
    exit 1
  fi
  dart run "${ROOT_DIR}/tool/gen_embedded_key.dart" --key "${ASSET_SHIELD_KEY_BASE64}"
fi

clang -std=c99 -O2 -fvisibility=hidden -dynamiclib -pthread \
  -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET}" \
  -DZSTD_MULTITHREAD=1 \
  -I "${ZSTD_DIR}" \
  -o "${OUT_DIR}/libasset_shield_crypto.dylib" \
  "${ROOT_DIR}/native/asset_shield_crypto.c" \
  $(find "${ZSTD_DIR}/common" "${ZSTD_DIR}/compress" "${ZSTD_DIR}/decompress" -name "*.c")

cp -f "${OUT_DIR}/libasset_shield_crypto.dylib" "${FRAMEWORK_DIR}/libasset_shield_crypto.dylib"

xcodebuild -create-xcframework \
  -library "${OUT_DIR}/libasset_shield_crypto.dylib" -headers "${HEADERS_DIR}" \
  -output "${FRAMEWORK_DIR}/AssetShieldCrypto.xcframework"

echo "Built ${OUT_DIR}/libasset_shield_crypto.dylib and ${FRAMEWORK_DIR}/AssetShieldCrypto.xcframework"
