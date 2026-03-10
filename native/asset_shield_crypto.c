#include "asset_shield_crypto.h"
#include "asset_shield_embedded_key.h"

#include <stdlib.h>
#include <string.h>

#define ASSET_SHIELD_OK 0
#define ASSET_SHIELD_ERR_INVALID_ARGS -1
#define ASSET_SHIELD_ERR_BAD_HEADER -2
#define ASSET_SHIELD_ERR_UNSUPPORTED -3
#define ASSET_SHIELD_ERR_AUTH -4
#define ASSET_SHIELD_ERR_ALLOC -5

static const uint8_t k_magic[4] = {0x41, 0x53, 0x53, 0x54};
static const uint8_t k_version = 1;
static const uint8_t k_tag_len = 16;
static const uint8_t k_iv_len = 12;

static uint8_t g_key[32];
static int g_key_len = 0;

static const uint8_t sbox[256] = {
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67,
    0x2b, 0xfe, 0xd7, 0xab, 0x76, 0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59,
    0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0, 0xb7,
    0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1,
    0x71, 0xd8, 0x31, 0x15, 0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05,
    0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75, 0x09, 0x83,
    0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29,
    0xe3, 0x2f, 0x84, 0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b,
    0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf, 0xd0, 0xef, 0xaa,
    0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c,
    0x9f, 0xa8, 0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc,
    0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2, 0xcd, 0x0c, 0x13, 0xec,
    0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19,
    0x73, 0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee,
    0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb, 0xe0, 0x32, 0x3a, 0x0a, 0x49,
    0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4,
    0xea, 0x65, 0x7a, 0xae, 0x08, 0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6,
    0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a, 0x70,
    0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9,
    0x86, 0xc1, 0x1d, 0x9e, 0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e,
    0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf, 0x8c, 0xa1,
    0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0,
    0x54, 0xbb, 0x16};

static const uint8_t rcon[11] = {0x00, 0x01, 0x02, 0x04, 0x08, 0x10,
                                 0x20, 0x40, 0x80, 0x1b, 0x36};

static uint32_t rot_word(uint32_t word) {
  return (word << 8) | (word >> 24);
}

static uint32_t sub_word(uint32_t word) {
  uint32_t result = 0;
  result |= ((uint32_t)sbox[(word >> 24) & 0xff]) << 24;
  result |= ((uint32_t)sbox[(word >> 16) & 0xff]) << 16;
  result |= ((uint32_t)sbox[(word >> 8) & 0xff]) << 8;
  result |= ((uint32_t)sbox[word & 0xff]);
  return result;
}

static int aes_key_expand(const uint8_t* key,
                          int key_len,
                          uint32_t* round_keys,
                          int* rounds) {
  int nk = 0;
  int nr = 0;
  if (key_len == 16) {
    nk = 4;
    nr = 10;
  } else if (key_len == 32) {
    nk = 8;
    nr = 14;
  } else {
    return 0;
  }

  for (int i = 0; i < nk; i++) {
    round_keys[i] = ((uint32_t)key[4 * i] << 24) |
                    ((uint32_t)key[4 * i + 1] << 16) |
                    ((uint32_t)key[4 * i + 2] << 8) |
                    ((uint32_t)key[4 * i + 3]);
  }

  const int words = 4 * (nr + 1);
  for (int i = nk; i < words; i++) {
    uint32_t temp = round_keys[i - 1];
    if (i % nk == 0) {
      temp = sub_word(rot_word(temp)) ^ ((uint32_t)rcon[i / nk] << 24);
    } else if (nk > 6 && i % nk == 4) {
      temp = sub_word(temp);
    }
    round_keys[i] = round_keys[i - nk] ^ temp;
  }

  *rounds = nr;
  return 1;
}

static uint8_t xtime(uint8_t x) {
  return (uint8_t)((x << 1) ^ ((x >> 7) * 0x1b));
}

static void mix_columns(uint8_t state[4][4]) {
  for (int c = 0; c < 4; c++) {
    uint8_t a0 = state[0][c];
    uint8_t a1 = state[1][c];
    uint8_t a2 = state[2][c];
    uint8_t a3 = state[3][c];

    uint8_t t = a0 ^ a1 ^ a2 ^ a3;
    uint8_t u = a0;
    state[0][c] ^= t ^ xtime((uint8_t)(a0 ^ a1));
    state[1][c] ^= t ^ xtime((uint8_t)(a1 ^ a2));
    state[2][c] ^= t ^ xtime((uint8_t)(a2 ^ a3));
    state[3][c] ^= t ^ xtime((uint8_t)(a3 ^ u));
  }
}

static void shift_rows(uint8_t state[4][4]) {
  uint8_t temp;

  temp = state[1][0];
  state[1][0] = state[1][1];
  state[1][1] = state[1][2];
  state[1][2] = state[1][3];
  state[1][3] = temp;

  temp = state[2][0];
  state[2][0] = state[2][2];
  state[2][2] = temp;
  temp = state[2][1];
  state[2][1] = state[2][3];
  state[2][3] = temp;

  temp = state[3][3];
  state[3][3] = state[3][2];
  state[3][2] = state[3][1];
  state[3][1] = state[3][0];
  state[3][0] = temp;
}

static void sub_bytes(uint8_t state[4][4]) {
  for (int r = 0; r < 4; r++) {
    for (int c = 0; c < 4; c++) {
      state[r][c] = sbox[state[r][c]];
    }
  }
}

static void add_round_key(uint8_t state[4][4],
                          const uint32_t* round_keys,
                          int round) {
  for (int c = 0; c < 4; c++) {
    uint32_t key = round_keys[round * 4 + c];
    state[0][c] ^= (uint8_t)(key >> 24);
    state[1][c] ^= (uint8_t)(key >> 16);
    state[2][c] ^= (uint8_t)(key >> 8);
    state[3][c] ^= (uint8_t)(key);
  }
}

static void aes_encrypt_block(const uint8_t in[16],
                              uint8_t out[16],
                              const uint32_t* round_keys,
                              int rounds) {
  uint8_t state[4][4];
  for (int c = 0; c < 4; c++) {
    for (int r = 0; r < 4; r++) {
      state[r][c] = in[r + 4 * c];
    }
  }

  add_round_key(state, round_keys, 0);
  for (int round = 1; round < rounds; round++) {
    sub_bytes(state);
    shift_rows(state);
    mix_columns(state);
    add_round_key(state, round_keys, round);
  }
  sub_bytes(state);
  shift_rows(state);
  add_round_key(state, round_keys, rounds);

  for (int c = 0; c < 4; c++) {
    for (int r = 0; r < 4; r++) {
      out[r + 4 * c] = state[r][c];
    }
  }
}

static void xor_block(uint8_t* dst, const uint8_t* src) {
  for (int i = 0; i < 16; i++) {
    dst[i] ^= src[i];
  }
}

static void shift_right_one(uint8_t* block) {
  uint8_t carry = 0;
  for (int i = 0; i < 16; i++) {
    uint8_t new_carry = block[i] & 0x01;
    block[i] = (uint8_t)((block[i] >> 1) | (carry << 7));
    carry = new_carry;
  }
}

static void gcm_mul(const uint8_t x[16], const uint8_t y[16], uint8_t out[16]) {
  uint8_t z[16] = {0};
  uint8_t v[16];
  memcpy(v, y, 16);

  for (int i = 0; i < 128; i++) {
    int byte_index = i / 8;
    int bit_index = 7 - (i % 8);
    uint8_t bit = (uint8_t)((x[byte_index] >> bit_index) & 1);
    if (bit) {
      xor_block(z, v);
    }
    uint8_t lsb = (uint8_t)(v[15] & 1);
    shift_right_one(v);
    if (lsb) {
      v[0] ^= 0xe1;
    }
  }

  memcpy(out, z, 16);
}

static void ghash(const uint8_t h[16],
                  const uint8_t* data,
                  size_t len,
                  uint8_t out[16]) {
  uint8_t y[16] = {0};
  uint8_t block[16];
  size_t offset = 0;

  while (offset < len) {
    size_t chunk = len - offset;
    if (chunk > 16) {
      chunk = 16;
    }
    memset(block, 0, 16);
    memcpy(block, data + offset, chunk);
    xor_block(y, block);
    gcm_mul(y, h, y);
    offset += chunk;
  }

  memcpy(out, y, 16);
}

static void inc32(uint8_t block[16]) {
  for (int i = 15; i >= 12; i--) {
    block[i]++;
    if (block[i] != 0) {
      break;
    }
  }
}

static int constant_time_eq(const uint8_t* a, const uint8_t* b, size_t len) {
  uint8_t diff = 0;
  for (size_t i = 0; i < len; i++) {
    diff |= (uint8_t)(a[i] ^ b[i]);
  }
  return diff == 0;
}

static int gcm_decrypt(const uint8_t* key,
                       int key_len,
                       const uint8_t* iv,
                       int iv_len,
                       const uint8_t* input,
                       int input_len,
                       uint8_t* output) {
  if (input_len < k_tag_len) {
    return ASSET_SHIELD_ERR_BAD_HEADER;
  }

  uint32_t round_keys[60];
  int rounds = 0;
  if (!aes_key_expand(key, key_len, round_keys, &rounds)) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }

  uint8_t zero_block[16] = {0};
  uint8_t h[16];
  aes_encrypt_block(zero_block, h, round_keys, rounds);

  if (iv_len != k_iv_len) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }

  uint8_t j0[16] = {0};
  memcpy(j0, iv, iv_len);
  j0[15] = 0x01;

  const int cipher_len = input_len - k_tag_len;
  const uint8_t* cipher = input;
  const uint8_t* tag = input + cipher_len;

  uint8_t s[16];
  ghash(h, cipher, cipher_len, s);

  uint8_t len_block[16] = {0};
  uint64_t c_bits = (uint64_t)cipher_len * 8;
  len_block[8] = (uint8_t)(c_bits >> 56);
  len_block[9] = (uint8_t)(c_bits >> 48);
  len_block[10] = (uint8_t)(c_bits >> 40);
  len_block[11] = (uint8_t)(c_bits >> 32);
  len_block[12] = (uint8_t)(c_bits >> 24);
  len_block[13] = (uint8_t)(c_bits >> 16);
  len_block[14] = (uint8_t)(c_bits >> 8);
  len_block[15] = (uint8_t)(c_bits);
  xor_block(s, len_block);
  gcm_mul(s, h, s);

  uint8_t e_j0[16];
  aes_encrypt_block(j0, e_j0, round_keys, rounds);
  xor_block(s, e_j0);

  if (!constant_time_eq(s, tag, k_tag_len)) {
    return ASSET_SHIELD_ERR_AUTH;
  }

  uint8_t counter[16];
  memcpy(counter, j0, 16);

  int offset = 0;
  while (offset < cipher_len) {
    uint8_t stream[16];
    inc32(counter);
    aes_encrypt_block(counter, stream, round_keys, rounds);
    int chunk = cipher_len - offset;
    if (chunk > 16) {
      chunk = 16;
    }
    for (int i = 0; i < chunk; i++) {
      output[offset + i] = (uint8_t)(cipher[offset + i] ^ stream[i]);
    }
    offset += chunk;
  }

  return ASSET_SHIELD_OK;
}

int32_t asset_shield_decrypt(const uint8_t* encrypted_data,
                             int32_t length,
                             const uint8_t* key,
                             int32_t key_length,
                             uint8_t** out_data,
                             int32_t* out_length) {
  if (!encrypted_data || !key || !out_data || !out_length) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  if (length < (int32_t)(sizeof(k_magic) + 2 + k_iv_len + k_tag_len)) {
    return ASSET_SHIELD_ERR_BAD_HEADER;
  }
  const uint8_t* use_key = key;
  int use_key_len = key_length;
  if (use_key_len == 0) {
    if (g_key_len == 0) {
      int embedded_len = 0;
      if (asset_shield_build_embedded_key(g_key, &embedded_len)) {
        g_key_len = embedded_len;
      }
    }
    if (g_key_len == 0) {
      return ASSET_SHIELD_ERR_INVALID_ARGS;
    }
    use_key = g_key;
    use_key_len = g_key_len;
  }

  if (use_key_len != 16 && use_key_len != 32) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }

  if (memcmp(encrypted_data, k_magic, sizeof(k_magic)) != 0) {
    return ASSET_SHIELD_ERR_BAD_HEADER;
  }

  uint8_t version = encrypted_data[4];
  uint8_t iv_len = encrypted_data[5];
  if (version != k_version || iv_len != k_iv_len) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }

  const uint8_t* iv = encrypted_data + 6;
  const uint8_t* cipher = encrypted_data + 6 + iv_len;
  int32_t cipher_len = length - (int32_t)(6 + iv_len);
  if (cipher_len <= k_tag_len) {
    return ASSET_SHIELD_ERR_BAD_HEADER;
  }

  uint8_t* plaintext = (uint8_t*)malloc((size_t)(cipher_len - k_tag_len));
  if (!plaintext) {
    return ASSET_SHIELD_ERR_ALLOC;
  }

  int result =
      gcm_decrypt(use_key, use_key_len, iv, iv_len, cipher, cipher_len, plaintext);
  if (result != ASSET_SHIELD_OK) {
    free(plaintext);
    return result;
  }

  *out_data = plaintext;
  *out_length = cipher_len - k_tag_len;
  return ASSET_SHIELD_OK;
}

int32_t asset_shield_set_key(const uint8_t* key, int32_t key_length) {
  if (!key || (key_length != 16 && key_length != 32)) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  memcpy(g_key, key, (size_t)key_length);
  g_key_len = key_length;
  return ASSET_SHIELD_OK;
}

void asset_shield_clear_key(void) {
  memset(g_key, 0, sizeof(g_key));
  g_key_len = 0;
}

void asset_shield_free(uint8_t* data) {
  free(data);
}
