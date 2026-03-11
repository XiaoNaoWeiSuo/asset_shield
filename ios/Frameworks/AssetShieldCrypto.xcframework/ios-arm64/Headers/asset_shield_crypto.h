#pragma once

#include <stdint.h>

#if defined(_WIN32)
#define ASSET_SHIELD_EXPORT __declspec(dllexport)
#else
#define ASSET_SHIELD_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Returns 0 on success, negative error codes on failure.
ASSET_SHIELD_EXPORT int32_t asset_shield_encrypt(
    const uint8_t* data,
    int32_t length,
    const uint8_t* key,
    int32_t key_length,
    int32_t compression_algo,
    int32_t compression_level,
    int32_t chunk_size,
    const uint8_t* base_iv,
    int32_t base_iv_length,
    int32_t crypto_workers,
    int32_t zstd_workers,
    uint8_t** out_data,
    int32_t* out_length);

ASSET_SHIELD_EXPORT int32_t asset_shield_decrypt(
    const uint8_t* encrypted_data,
    int32_t length,
    const uint8_t* key,
    int32_t key_length,
    int32_t crypto_workers,
    int32_t zstd_workers,
    uint8_t** out_data,
    int32_t* out_length);

ASSET_SHIELD_EXPORT int32_t asset_shield_compress(
    const uint8_t* data,
    int32_t length,
    int32_t level,
    uint8_t** out_data,
    int32_t* out_length);

ASSET_SHIELD_EXPORT int32_t asset_shield_decompress(
    const uint8_t* data,
    int32_t length,
    int32_t original_length,
    uint8_t** out_data,
    int32_t* out_length);

ASSET_SHIELD_EXPORT int32_t asset_shield_set_key(const uint8_t* key,
                                                 int32_t key_length);

ASSET_SHIELD_EXPORT void asset_shield_clear_key(void);

ASSET_SHIELD_EXPORT void asset_shield_free(uint8_t* data);

// Debug helper: returns 0 on success, non-zero on failure.
ASSET_SHIELD_EXPORT int32_t asset_shield_selftest(void);

// Sets a base directory for reading assets directly on file-based platforms.
// Example value on Apple platforms: <bundle_resource_path>/flutter_assets
// Returns 0 on success.
ASSET_SHIELD_EXPORT int32_t asset_shield_set_assets_base_path(const char* path);

// Android-only: sets the AAssetManager* (passed as an opaque pointer).
// Returns 0 on success.
ASSET_SHIELD_EXPORT int32_t asset_shield_set_android_asset_manager(void* mgr);

// Loads encrypted bytes from the platform asset store and decrypts them.
// rel_path is relative to flutter_assets (e.g. "assets/encrypted/<hash>.dat").
ASSET_SHIELD_EXPORT int32_t asset_shield_load_and_decrypt_asset(
    const char* rel_path,
    const uint8_t* key,
    int32_t key_length,
    int32_t crypto_workers,
    int32_t zstd_workers,
    uint8_t** out_data,
    int32_t* out_length);

// Encrypts an input file to output file (V4 format). Returns 0 on success.
ASSET_SHIELD_EXPORT int32_t asset_shield_encrypt_file(
    const char* input_path,
    const char* output_path,
    const uint8_t* key,
    int32_t key_length,
    int32_t compression_algo,
    int32_t compression_level,
    int32_t chunk_size,
    const uint8_t* base_iv,
    int32_t base_iv_length,
    int32_t zstd_workers);

#ifdef __cplusplus
}
#endif
