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
ASSET_SHIELD_EXPORT int32_t asset_shield_decrypt(
    const uint8_t* encrypted_data,
    int32_t length,
    const uint8_t* key,
    int32_t key_length,
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

#ifdef __cplusplus
}
#endif
