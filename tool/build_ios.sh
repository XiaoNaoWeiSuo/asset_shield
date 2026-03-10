#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/ios"
FRAMEWORK_DIR="${ROOT_DIR}/ios/Frameworks"

mkdir -p "${BUILD_DIR}" "${FRAMEWORK_DIR}"

if [[ -n "${ASSET_SHIELD_KEY_BASE64:-}" ]]; then
  if ! command -v dart >/dev/null 2>&1; then
    echo "dart not found; cannot generate embedded key header." >&2
    exit 1
  fi
  dart run "${ROOT_DIR}/tool/gen_embedded_key.dart" --key "${ASSET_SHIELD_KEY_BASE64}"
fi

IOS_DEVICE="${BUILD_DIR}/ios-device"
IOS_SIM="${BUILD_DIR}/ios-sim"

mkdir -p "${IOS_DEVICE}" "${IOS_SIM}"

build_lib() {
  local sdk=$1
  local arch=$2
  local out_dir=$3
  local cc
  cc="$(xcrun --sdk "${sdk}" --find clang)"
  "${cc}" -std=c99 -O2 -fvisibility=hidden -fPIC \
    -isysroot "$(xcrun --sdk "${sdk}" --show-sdk-path)" \
    -arch "${arch}" \
    -c "${ROOT_DIR}/native/asset_shield_crypto.c" \
    -o "${out_dir}/asset_shield_crypto_${arch}.o"
  libtool -static -o "${out_dir}/libasset_shield_crypto.a" "${out_dir}/asset_shield_crypto_${arch}.o"
}

build_lib iphoneos arm64 "${IOS_DEVICE}"
build_lib iphonesimulator arm64 "${IOS_SIM}"
build_lib iphonesimulator x86_64 "${IOS_SIM}"

lipo -create \
  "${IOS_SIM}/libasset_shield_crypto.a" \
  -output "${IOS_SIM}/libasset_shield_crypto_universal.a"

xcodebuild -create-xcframework \
  -library "${IOS_DEVICE}/libasset_shield_crypto.a" -headers "${ROOT_DIR}/native" \
  -library "${IOS_SIM}/libasset_shield_crypto_universal.a" -headers "${ROOT_DIR}/native" \
  -output "${FRAMEWORK_DIR}/AssetShieldCrypto.xcframework"

echo "Built iOS xcframework at ${FRAMEWORK_DIR}/AssetShieldCrypto.xcframework"
