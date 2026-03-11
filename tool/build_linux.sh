#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/linux/lib"
ZSTD_DIR="${ROOT_DIR}/third_party/zstd/lib"

mkdir -p "${OUT_DIR}"

if [[ -n "${ASSET_SHIELD_KEY_BASE64:-}" ]]; then
  if ! command -v dart >/dev/null 2>&1; then
    echo "dart not found; cannot generate embedded key header." >&2
    exit 1
  fi
  dart run "${ROOT_DIR}/tool/gen_embedded_key.dart" --key "${ASSET_SHIELD_KEY_BASE64}"
fi

cc="${CC:-gcc}"
asm_define=""
if [[ "${ASSET_SHIELD_ZSTD_DISABLE_ASM:-}" == "1" ]]; then
  asm_define="-DZSTD_DISABLE_ASM=1"
fi

asm_sources=()
if [[ -z "${asm_define}" ]]; then
  arch="$(uname -m || true)"
  if [[ "${arch}" == "x86_64" ]]; then
    # zstd ships the amd64 Huffman fast-loop in assembly; include it or we'll get
    # undefined symbol errors at link time.
    if [[ -f "${ZSTD_DIR}/decompress/huf_decompress_amd64.S" ]]; then
      asm_sources+=("${ZSTD_DIR}/decompress/huf_decompress_amd64.S")
    fi
  fi
fi
"${cc}" -std=c99 -O2 -fPIC -fvisibility=hidden -shared -pthread \
  -DZSTD_MULTITHREAD=1 \
  ${asm_define} \
  -I "${ZSTD_DIR}" \
  -o "${OUT_DIR}/libasset_shield_crypto.so" \
  "${ROOT_DIR}/native/asset_shield_crypto.c" \
  "${asm_sources[@]}" \
  $(find "${ZSTD_DIR}/common" "${ZSTD_DIR}/compress" "${ZSTD_DIR}/decompress" -name "*.c")

echo "Built ${OUT_DIR}/libasset_shield_crypto.so"
