#pragma once

#include <stdint.h>
#include <string.h>

// Default: no embedded key. Use tool/gen_embedded_key.dart to generate one.
#define ASSET_SHIELD_EMBEDDED_KEY_LEN 0

static inline int asset_shield_build_embedded_key(uint8_t* out_key,
                                                  int* out_len) {
  if (!out_key || !out_len) {
    return 0;
  }
  *out_len = 0;
  return 0;
}
