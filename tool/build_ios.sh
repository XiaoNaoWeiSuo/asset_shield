#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/ios"
FRAMEWORK_DIR="${ROOT_DIR}/ios/Frameworks"
ZSTD_DIR="${ROOT_DIR}/third_party/zstd/lib"
IOS_MIN_VERSION="${IOS_MIN_VERSION:-12.0}"
HEADERS_DIR="${BUILD_DIR}/headers"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${FRAMEWORK_DIR}"
rm -rf "${FRAMEWORK_DIR}/AssetShieldCrypto.xcframework"
mkdir -p "${HEADERS_DIR}"
cp -f "${ROOT_DIR}/native/asset_shield_crypto.h" "${HEADERS_DIR}/asset_shield_crypto.h"

if [[ -n "${ASSET_SHIELD_KEY_BASE64:-}" ]]; then
  if ! command -v dart >/dev/null 2>&1; then
    echo "dart not found; cannot generate embedded key header." >&2
    exit 1
  fi
  dart run "${ROOT_DIR}/tool/gen_embedded_key.dart" --key "${ASSET_SHIELD_KEY_BASE64}"
fi

IOS_DEVICE="${BUILD_DIR}/ios-device"
IOS_SIM="${BUILD_DIR}/ios-sim"
IOS_SIM_ARM64="${BUILD_DIR}/ios-sim-arm64"
IOS_SIM_X86_64="${BUILD_DIR}/ios-sim-x86_64"

mkdir -p "${IOS_DEVICE}" "${IOS_SIM}" "${IOS_SIM_ARM64}" "${IOS_SIM_X86_64}"

build_lib() {
  local sdk=$1
  local arch=$2
  local out_dir=$3
  local cc
  cc="$(xcrun --sdk "${sdk}" --find clang)"
  rm -f "${out_dir}"/*.o "${out_dir}/libasset_shield_crypto.a"
  local min_flag=""
  if [[ "${sdk}" == "iphoneos" ]]; then
    min_flag="-miphoneos-version-min=${IOS_MIN_VERSION}"
  else
    min_flag="-mios-simulator-version-min=${IOS_MIN_VERSION}"
  fi
  local sources=("${ROOT_DIR}/native/asset_shield_crypto.c")
  while IFS= read -r -d '' src; do
    sources+=("${src}")
  done < <(find "${ZSTD_DIR}/common" "${ZSTD_DIR}/compress" "${ZSTD_DIR}/decompress" -name "*.c" -print0)

  local objs=()
  for src in "${sources[@]}"; do
    local rel="${src#${ROOT_DIR}/}"
    local obj="${out_dir}/$(echo "${rel}" | tr '/.' '__').o"
    "${cc}" -std=c99 -O2 -fvisibility=hidden -fPIC -pthread \
      -DZSTD_MULTITHREAD=1 \
      -I "${ZSTD_DIR}" \
      -isysroot "$(xcrun --sdk "${sdk}" --show-sdk-path)" \
      ${min_flag} \
      -arch "${arch}" \
      -c "${src}" \
      -o "${obj}"
    objs+=("${obj}")
  done
  libtool -static -o "${out_dir}/libasset_shield_crypto.a" "${objs[@]}"
}

build_lib iphoneos arm64 "${IOS_DEVICE}"
build_lib iphonesimulator arm64 "${IOS_SIM_ARM64}"
build_lib iphonesimulator x86_64 "${IOS_SIM_X86_64}"

lipo -create \
  "${IOS_SIM_ARM64}/libasset_shield_crypto.a" \
  "${IOS_SIM_X86_64}/libasset_shield_crypto.a" \
  -output "${IOS_SIM}/libasset_shield_crypto.a"

xcodebuild -create-xcframework \
  -library "${IOS_DEVICE}/libasset_shield_crypto.a" -headers "${HEADERS_DIR}" \
  -library "${IOS_SIM}/libasset_shield_crypto.a" -headers "${HEADERS_DIR}" \
  -output "${FRAMEWORK_DIR}/AssetShieldCrypto.xcframework"

echo "Built iOS xcframework at ${FRAMEWORK_DIR}/AssetShieldCrypto.xcframework"
