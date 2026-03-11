#include "asset_shield_crypto.h"
#include "asset_shield_embedded_key.h"
#include "zstd.h"

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <stdio.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <pthread.h>
#endif

#if defined(__ANDROID__)
#include <android/asset_manager.h>
#include <android/asset_manager_jni.h>
#include <jni.h>
#endif

#if defined(__APPLE__)
#include <CommonCrypto/CommonCryptor.h>
#endif

#define ASSET_SHIELD_OK 0
#define ASSET_SHIELD_ERR_INVALID_ARGS -1
#define ASSET_SHIELD_ERR_BAD_HEADER -2
#define ASSET_SHIELD_ERR_UNSUPPORTED -3
#define ASSET_SHIELD_ERR_AUTH -4
#define ASSET_SHIELD_ERR_ALLOC -5
#define ASSET_SHIELD_ERR_ZSTD -6
#define ASSET_SHIELD_ERR_OVERFLOW -7
#define ASSET_SHIELD_ERR_THREAD -8

static const uint8_t k_magic[4] = {0x41, 0x53, 0x53, 0x54};
static const uint8_t k_version4 = 4;
static const uint8_t k_algo_none = 0;
static const uint8_t k_algo_zstd = 1;
static const uint8_t k_flag_compressed = 0x01;
static const uint8_t k_tag_len = 16;
static const uint8_t k_iv_len = 12;
static const uint32_t k_header_len_v4 = 28;

static uint8_t g_key[32];
static int g_key_len = 0;

static char* g_assets_base_path = NULL;

#if defined(__ANDROID__)
static AAssetManager* g_asset_manager = NULL;
#endif

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

typedef struct {
  uint8_t table[16][256][16];
  uint8_t h[16];
  int ready;
} ghash_table_full;

static ghash_table_full g_ghash_cache;

#if defined(_WIN32)
static SRWLOCK g_ghash_lock = SRWLOCK_INIT;
#define GHASH_LOCK() AcquireSRWLockExclusive(&g_ghash_lock)
#define GHASH_UNLOCK() ReleaseSRWLockExclusive(&g_ghash_lock)
#else
static pthread_mutex_t g_ghash_lock = PTHREAD_MUTEX_INITIALIZER;
#define GHASH_LOCK() pthread_mutex_lock(&g_ghash_lock)
#define GHASH_UNLOCK() pthread_mutex_unlock(&g_ghash_lock)
#endif

static void ghash_table_full_init(ghash_table_full* table,
                                  const uint8_t h[16]) {
  uint8_t x[16];
  for (int i = 0; i < 16; i++) {
    for (int b = 0; b < 256; b++) {
      memset(x, 0, sizeof(x));
      x[i] = (uint8_t)b;
      gcm_mul(x, h, table->table[i][b]);
    }
  }
  memcpy(table->h, h, 16);
  table->ready = 1;
}

static const ghash_table_full* ghash_table_full_get(const uint8_t h[16]) {
  GHASH_LOCK();
  if (g_ghash_cache.ready != 0 && memcmp(g_ghash_cache.h, h, 16) == 0) {
    GHASH_UNLOCK();
    return &g_ghash_cache;
  }
  ghash_table_full_init(&g_ghash_cache, h);
  GHASH_UNLOCK();
  return &g_ghash_cache;
}

static void ghash_mul_full(const ghash_table_full* table, uint8_t x[16]) {
  uint8_t z[16] = {0};
  for (int i = 0; i < 16; i++) {
    xor_block(z, table->table[i][x[i]]);
  }
  memcpy(x, z, 16);
}

static void ghash_full(const ghash_table_full* table,
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
    ghash_mul_full(table, y);
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

static uint32_t read_u32_le(const uint8_t* data, size_t offset) {
  return (uint32_t)data[offset] |
         ((uint32_t)data[offset + 1] << 8) |
         ((uint32_t)data[offset + 2] << 16) |
         ((uint32_t)data[offset + 3] << 24);
}

static void write_u32_le(uint8_t* dst, uint32_t value) {
  dst[0] = (uint8_t)(value & 0xff);
  dst[1] = (uint8_t)((value >> 8) & 0xff);
  dst[2] = (uint8_t)((value >> 16) & 0xff);
  dst[3] = (uint8_t)((value >> 24) & 0xff);
}

static int derive_chunk_iv(const uint8_t base_iv[12],
                           uint32_t chunk_index,
                           uint8_t out_iv[12]) {
  memcpy(out_iv, base_iv, 12);
  uint32_t counter = ((uint32_t)base_iv[8] << 24) |
                     ((uint32_t)base_iv[9] << 16) |
                     ((uint32_t)base_iv[10] << 8) |
                     ((uint32_t)base_iv[11]);
  uint32_t next = counter + chunk_index;
  if (next < counter) {
    return 0;
  }
  out_iv[8] = (uint8_t)((next >> 24) & 0xff);
  out_iv[9] = (uint8_t)((next >> 16) & 0xff);
  out_iv[10] = (uint8_t)((next >> 8) & 0xff);
  out_iv[11] = (uint8_t)(next & 0xff);
  return 1;
}

static size_t encrypted_payload_length(size_t plain_len, size_t chunk_size) {
  size_t chunk_count = 1;
  if (plain_len > 0) {
    chunk_count = (plain_len + chunk_size - 1) / chunk_size;
  }
  return plain_len + chunk_count * (sizeof(uint32_t) + k_tag_len);
}

static int normalize_workers(int32_t requested, size_t chunk_count) {
  if (requested <= 1 || chunk_count <= 1) {
    return 1;
  }
  if ((size_t)requested > chunk_count) {
    return (int)chunk_count;
  }
  return (int)requested;
}

static int gcm_encrypt_with_keys(const uint32_t* round_keys,
                                 int rounds,
                                 const uint8_t h[16],
                                 const uint8_t* iv,
                                 int iv_len,
                                 const uint8_t* input,
                                 int input_len,
                                 uint8_t* output) {
  if (iv_len != k_iv_len) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }
  uint8_t j0[16] = {0};
  memcpy(j0, iv, iv_len);
  j0[15] = 0x01;

  uint8_t counter[16];
  memcpy(counter, j0, 16);

  int offset = 0;
  while (offset < input_len) {
    uint8_t stream[16];
    inc32(counter);
    aes_encrypt_block(counter, stream, round_keys, rounds);
    int chunk = input_len - offset;
    if (chunk > 16) {
      chunk = 16;
    }
    for (int i = 0; i < chunk; i++) {
      output[offset + i] = (uint8_t)(input[offset + i] ^ stream[i]);
    }
    offset += chunk;
  }

  const ghash_table_full* ht = ghash_table_full_get(h);
  uint8_t s[16];
  ghash_full(ht, output, (size_t)input_len, s);

  uint8_t len_block[16] = {0};
  uint64_t c_bits = (uint64_t)input_len * 8;
  len_block[8] = (uint8_t)(c_bits >> 56);
  len_block[9] = (uint8_t)(c_bits >> 48);
  len_block[10] = (uint8_t)(c_bits >> 40);
  len_block[11] = (uint8_t)(c_bits >> 32);
  len_block[12] = (uint8_t)(c_bits >> 24);
  len_block[13] = (uint8_t)(c_bits >> 16);
  len_block[14] = (uint8_t)(c_bits >> 8);
  len_block[15] = (uint8_t)(c_bits);
  xor_block(s, len_block);
  ghash_mul_full(ht, s);

  uint8_t e_j0[16];
  aes_encrypt_block(j0, e_j0, round_keys, rounds);
  xor_block(s, e_j0);

  memcpy(output + input_len, s, k_tag_len);
  return ASSET_SHIELD_OK;
}

static int gcm_decrypt_with_keys(const uint32_t* round_keys,
                                 int rounds,
                                 const uint8_t h[16],
                                 const uint8_t* iv,
                                 int iv_len,
                                 const uint8_t* input,
                                 int input_len,
                                 uint8_t* output) {
  if (input_len < k_tag_len) {
    return ASSET_SHIELD_ERR_BAD_HEADER;
  }
  if (iv_len != k_iv_len) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }

  uint8_t j0[16] = {0};
  memcpy(j0, iv, iv_len);
  j0[15] = 0x01;

  const int cipher_len = input_len - k_tag_len;
  const uint8_t* cipher = input;
  const uint8_t* tag = input + cipher_len;

  const ghash_table_full* ht = ghash_table_full_get(h);
  uint8_t s[16];
  ghash_full(ht, cipher, (size_t)cipher_len, s);

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
  ghash_mul_full(ht, s);

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

#if defined(__APPLE__)
typedef struct {
  CCCryptorRef ecb;
  CCCryptorRef ctr;
  uint8_t key[32];
  int key_len;
  uint8_t h[16];
} apple_ecb_ctx;

static pthread_key_t g_apple_ecb_ctx_key;
static pthread_once_t g_apple_ecb_ctx_once = PTHREAD_ONCE_INIT;

static void apple_ecb_ctx_destroy(void* ptr) {
  apple_ecb_ctx* ctx = (apple_ecb_ctx*)ptr;
  if (!ctx) return;
  if (ctx->ecb) {
    CCCryptorRelease(ctx->ecb);
  }
  if (ctx->ctr) {
    CCCryptorRelease(ctx->ctr);
  }
  memset(ctx, 0, sizeof(*ctx));
  free(ctx);
}

static void apple_ecb_ctx_init_once(void) {
  (void)pthread_key_create(&g_apple_ecb_ctx_key, apple_ecb_ctx_destroy);
}

static int apple_ecb_encrypt_block(CCCryptorRef ecb,
                                   const uint8_t in[16],
                                   uint8_t out[16]) {
  size_t moved = 0;
  CCCryptorStatus status = CCCryptorUpdate(ecb, in, 16, out, 16, &moved);
  if (status != kCCSuccess || moved != 16) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }
  return ASSET_SHIELD_OK;
}

static int apple_ecb_ctx_create(const uint8_t* key, int key_len, apple_ecb_ctx** out) {
  if (!key || key_len != 32 || !out) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  apple_ecb_ctx* ctx = (apple_ecb_ctx*)calloc(1, sizeof(*ctx));
  if (!ctx) {
    return ASSET_SHIELD_ERR_ALLOC;
  }
  memcpy(ctx->key, key, 32);
  ctx->key_len = key_len;

  CCCryptorRef ecb = NULL;
  CCCryptorStatus status = CCCryptorCreateWithMode(kCCEncrypt,
                                                  kCCModeECB,
                                                  kCCAlgorithmAES,
                                                  ccNoPadding,
                                                  NULL,
                                                  key,
                                                  (size_t)key_len,
                                                  NULL,
                                                  0,
                                                  0,
                                                  0,
                                                  &ecb);
  if (status != kCCSuccess || ecb == NULL) {
    free(ctx);
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }
  ctx->ecb = ecb;

  CCCryptorRef ctr = NULL;
  uint8_t ctr_iv[16] = {0};
  status = CCCryptorCreateWithMode(kCCEncrypt,
                                  kCCModeCTR,
                                  kCCAlgorithmAES,
                                  ccNoPadding,
                                  ctr_iv,
                                  key,
                                  (size_t)key_len,
                                  NULL,
                                  0,
                                  0,
                                  kCCModeOptionCTR_BE,
                                  &ctr);
  if (status != kCCSuccess || ctr == NULL) {
    apple_ecb_ctx_destroy(ctx);
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }
  ctx->ctr = ctr;

  uint8_t zero[16] = {0};
  int rc = apple_ecb_encrypt_block(ecb, zero, ctx->h);
  if (rc != ASSET_SHIELD_OK) {
    apple_ecb_ctx_destroy(ctx);
    return rc;
  }

  *out = ctx;
  return ASSET_SHIELD_OK;
}

static apple_ecb_ctx* apple_ecb_ctx_get(const uint8_t* key, int key_len) {
  (void)pthread_once(&g_apple_ecb_ctx_once, apple_ecb_ctx_init_once);
  apple_ecb_ctx* ctx = (apple_ecb_ctx*)pthread_getspecific(g_apple_ecb_ctx_key);
  if (ctx && ctx->key_len == key_len && memcmp(ctx->key, key, 32) == 0) {
    return ctx;
  }
  if (ctx) {
    apple_ecb_ctx_destroy(ctx);
    (void)pthread_setspecific(g_apple_ecb_ctx_key, NULL);
  }
  apple_ecb_ctx* next = NULL;
  if (apple_ecb_ctx_create(key, key_len, &next) != ASSET_SHIELD_OK) {
    return NULL;
  }
  (void)pthread_setspecific(g_apple_ecb_ctx_key, next);
  return next;
}

static int apple_ctr_crypt(CCCryptorRef ctr,
                           const uint8_t counter[16],
                           const uint8_t* input,
                           size_t input_len,
                           uint8_t* output) {
  if (!ctr) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  CCCryptorStatus status = CCCryptorReset(ctr, counter);
  if (status != kCCSuccess) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }
  size_t moved = 0;
  status = CCCryptorUpdate(ctr, input, input_len, output, input_len, &moved);
  if (status != kCCSuccess || moved != input_len) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }
  return ASSET_SHIELD_OK;
}

static int gcm_encrypt_sys(const uint8_t* key,
                           int key_len,
                           const uint8_t* iv,
                           int iv_len,
                           const uint8_t* input,
                           int input_len,
                           uint8_t* output) {
  if (iv_len != k_iv_len) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }
  apple_ecb_ctx* ctx = apple_ecb_ctx_get(key, key_len);
  if (!ctx) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }
  const uint8_t* h = ctx->h;

  uint8_t j0[16] = {0};
  memcpy(j0, iv, iv_len);
  j0[15] = 0x01;

  uint8_t counter[16];
  memcpy(counter, j0, 16);
  inc32(counter);
  int status = apple_ctr_crypt(ctx->ctr, counter, input, (size_t)input_len, output);
  if (status != ASSET_SHIELD_OK) {
    return status;
  }

  const ghash_table_full* ht = ghash_table_full_get(h);
  uint8_t s[16];
  ghash_full(ht, output, (size_t)input_len, s);

  uint8_t len_block[16] = {0};
  uint64_t c_bits = (uint64_t)input_len * 8;
  len_block[8] = (uint8_t)(c_bits >> 56);
  len_block[9] = (uint8_t)(c_bits >> 48);
  len_block[10] = (uint8_t)(c_bits >> 40);
  len_block[11] = (uint8_t)(c_bits >> 32);
  len_block[12] = (uint8_t)(c_bits >> 24);
  len_block[13] = (uint8_t)(c_bits >> 16);
  len_block[14] = (uint8_t)(c_bits >> 8);
  len_block[15] = (uint8_t)(c_bits);
  xor_block(s, len_block);
  ghash_mul_full(ht, s);

  uint8_t e_j0[16];
  status = apple_ecb_encrypt_block(ctx->ecb, j0, e_j0);
  if (status != ASSET_SHIELD_OK) {
    return status;
  }
  xor_block(s, e_j0);
  memcpy(output + input_len, s, k_tag_len);
  return ASSET_SHIELD_OK;
}

static int gcm_decrypt_sys(const uint8_t* key,
                           int key_len,
                           const uint8_t* iv,
                           int iv_len,
                           const uint8_t* input,
                           int input_len,
                           uint8_t* output) {
  if (input_len < k_tag_len) {
    return ASSET_SHIELD_ERR_BAD_HEADER;
  }
  if (iv_len != k_iv_len) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }

  apple_ecb_ctx* ctx = apple_ecb_ctx_get(key, key_len);
  if (!ctx) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }
  const uint8_t* h = ctx->h;

  uint8_t j0[16] = {0};
  memcpy(j0, iv, iv_len);
  j0[15] = 0x01;

  const int cipher_len = input_len - k_tag_len;
  const uint8_t* cipher = input;
  const uint8_t* tag = input + cipher_len;

  const ghash_table_full* ht = ghash_table_full_get(h);
  uint8_t s[16];
  ghash_full(ht, cipher, (size_t)cipher_len, s);

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
  ghash_mul_full(ht, s);

  uint8_t e_j0[16];
  int status = apple_ecb_encrypt_block(ctx->ecb, j0, e_j0);
  if (status != ASSET_SHIELD_OK) {
    return status;
  }
  xor_block(s, e_j0);

  if (!constant_time_eq(s, tag, k_tag_len)) {
    return ASSET_SHIELD_ERR_AUTH;
  }

  uint8_t counter[16];
  memcpy(counter, j0, 16);
  inc32(counter);
  status = apple_ctr_crypt(ctx->ctr, counter, cipher, (size_t)cipher_len, output);
  if (status != ASSET_SHIELD_OK) {
    return status;
  }

  return ASSET_SHIELD_OK;
}
#endif

static int gcm_encrypt_any(const uint8_t* key,
                           int key_len,
                           const uint32_t* round_keys,
                           int rounds,
                           const uint8_t h[16],
                           const uint8_t* iv,
                           int iv_len,
                           const uint8_t* input,
                           int input_len,
                           uint8_t* output) {
#if defined(__APPLE__)
  return gcm_encrypt_sys(key, key_len, iv, iv_len, input, input_len, output);
#else
  return gcm_encrypt_with_keys(round_keys,
                               rounds,
                               h,
                               iv,
                               iv_len,
                               input,
                               input_len,
                               output);
#endif
}

static int gcm_decrypt_any(const uint8_t* key,
                           int key_len,
                           const uint32_t* round_keys,
                           int rounds,
                           const uint8_t h[16],
                           const uint8_t* iv,
                           int iv_len,
                           const uint8_t* input,
                           int input_len,
                           uint8_t* output) {
#if defined(__APPLE__)
  return gcm_decrypt_sys(key, key_len, iv, iv_len, input, input_len, output);
#else
  return gcm_decrypt_with_keys(round_keys,
                               rounds,
                               h,
                               iv,
                               iv_len,
                               input,
                               input_len,
                               output);
#endif
}

static int zstd_compress_buffer(const uint8_t* data,
                                size_t length,
                                int level,
                                int workers,
                                uint8_t** out_data,
                                size_t* out_length) {
  if (!out_data || !out_length) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  size_t bound = ZSTD_compressBound(length);
  uint8_t* out = (uint8_t*)malloc(bound);
  if (!out) {
    return ASSET_SHIELD_ERR_ALLOC;
  }

  size_t result = 0;
  if (workers > 1) {
    ZSTD_CCtx* cctx = ZSTD_createCCtx();
    if (!cctx) {
      free(out);
      return ASSET_SHIELD_ERR_ZSTD;
    }
#ifdef ZSTD_MULTITHREAD
    ZSTD_CCtx_setParameter(cctx, ZSTD_c_nbWorkers, workers);
#else
    (void)workers;
#endif
    result = ZSTD_compressCCtx(cctx, out, bound, data, length, level);
    ZSTD_freeCCtx(cctx);
  } else {
    result = ZSTD_compress(out, bound, data, length, level);
  }

  if (ZSTD_isError(result)) {
    free(out);
    return ASSET_SHIELD_ERR_ZSTD;
  }

  *out_data = out;
  *out_length = result;
  return ASSET_SHIELD_OK;
}

static int zstd_decompress_buffer(const uint8_t* data,
                                  size_t length,
                                  size_t original_length,
                                  int workers,
                                  uint8_t** out_data,
                                  size_t* out_length) {
  if (!out_data || !out_length) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  uint8_t* out = (uint8_t*)malloc(original_length);
  if (!out) {
    return ASSET_SHIELD_ERR_ALLOC;
  }

  size_t result = 0;
  if (workers > 1) {
    ZSTD_DCtx* dctx = ZSTD_createDCtx();
    if (!dctx) {
      free(out);
      return ASSET_SHIELD_ERR_ZSTD;
    }
    (void)workers;
    result = ZSTD_decompressDCtx(dctx, out, original_length, data, length);
    ZSTD_freeDCtx(dctx);
  } else {
    result = ZSTD_decompress(out, original_length, data, length);
  }

  if (ZSTD_isError(result)) {
    free(out);
    return ASSET_SHIELD_ERR_ZSTD;
  }

  *out_data = out;
  *out_length = result;
  return ASSET_SHIELD_OK;
}

typedef struct {
  const uint8_t* input;
  uint8_t* output;
  const uint32_t* lengths;
  const size_t* offsets;
  size_t chunk_size;
  size_t start_chunk;
  size_t end_chunk;
  size_t last_chunk_index;
  size_t last_chunk_len;
  const uint32_t* round_keys;
  int rounds;
  const uint8_t* h;
  uint8_t base_iv[12];
  uint8_t flags;
  const uint8_t* key;
  int key_len;
  int error;
} decrypt_job;

#if defined(_WIN32)
#define ASSET_THREAD_RETURN DWORD WINAPI
#else
#define ASSET_THREAD_RETURN void*
#endif

static ASSET_THREAD_RETURN decrypt_worker(void* arg) {
  decrypt_job* job = (decrypt_job*)arg;
  uint8_t* scratch = NULL;
  if ((job->flags & k_flag_compressed) != 0 && job->chunk_size > 0) {
    scratch = (uint8_t*)malloc(job->chunk_size);
    if (!scratch) {
      job->error = ASSET_SHIELD_ERR_ALLOC;
#if defined(_WIN32)
      return 0;
#else
      return NULL;
#endif
    }
  }
  for (size_t chunk = job->start_chunk; chunk < job->end_chunk; chunk++) {
    size_t out_offset = chunk * job->chunk_size;
    uint32_t len_field = job->lengths[chunk];
    size_t stored_len = (size_t)(len_field & 0x7fffffff);
    int compressed = (len_field & 0x80000000u) != 0;
    size_t plain_len =
        (chunk == job->last_chunk_index) ? job->last_chunk_len : job->chunk_size;
    uint8_t iv[12];
    if (!derive_chunk_iv(job->base_iv, (uint32_t)chunk, iv)) {
      job->error = ASSET_SHIELD_ERR_OVERFLOW;
      break;
    }
    if (compressed && (job->flags & k_flag_compressed) == 0) {
      job->error = ASSET_SHIELD_ERR_UNSUPPORTED;
      break;
    }
    if (!compressed && stored_len != plain_len) {
      job->error = ASSET_SHIELD_ERR_BAD_HEADER;
      break;
    }
    if (compressed && (plain_len == 0 || stored_len == 0)) {
      job->error = ASSET_SHIELD_ERR_BAD_HEADER;
      break;
    }

    const uint8_t* cipher = job->input + job->offsets[chunk];
    int result = ASSET_SHIELD_OK;

    if (compressed) {
      if (!scratch) {
        job->error = ASSET_SHIELD_ERR_ALLOC;
        break;
      }
      result = gcm_decrypt_any(job->key,
                               job->key_len,
                               job->round_keys,
                               job->rounds,
                               job->h,
                               iv,
                               k_iv_len,
                               cipher,
                               (int)(stored_len + k_tag_len),
                               scratch);
      if (result != ASSET_SHIELD_OK) {
        job->error = result;
        break;
      }
      size_t dec = ZSTD_decompress(job->output + out_offset,
                                   plain_len,
                                   scratch,
                                   stored_len);
      if (ZSTD_isError(dec) || dec != plain_len) {
        job->error = ASSET_SHIELD_ERR_ZSTD;
        break;
      }
    } else {
      result = gcm_decrypt_any(job->key,
                               job->key_len,
                               job->round_keys,
                               job->rounds,
                               job->h,
                               iv,
                               k_iv_len,
                               cipher,
                               (int)(stored_len + k_tag_len),
                               job->output + out_offset);
      if (result != ASSET_SHIELD_OK) {
        job->error = result;
        break;
      }
    }
  }
  if (scratch) {
    free(scratch);
  }
#if defined(_WIN32)
  return 0;
#else
  return NULL;
#endif
}

static int run_decrypt_jobs(const uint8_t* input,
                            uint8_t* output,
                            const uint32_t* lengths,
                            const size_t* offsets,
                            size_t chunk_size,
                            size_t chunk_count,
                            size_t last_chunk_index,
                            size_t last_chunk_len,
                            const uint32_t* round_keys,
                            int rounds,
                            const uint8_t h[16],
                            const uint8_t base_iv[12],
                            uint8_t flags,
                            const uint8_t* key,
                            int key_len,
                            int workers) {
  if (chunk_count == 0) {
    return ASSET_SHIELD_OK;
  }
  int threads = normalize_workers(workers, chunk_count);
  if (threads <= 1) {
    decrypt_job job = {
        .input = input,
        .output = output,
        .lengths = lengths,
        .offsets = offsets,
        .chunk_size = chunk_size,
        .start_chunk = 0,
        .end_chunk = chunk_count,
        .last_chunk_index = last_chunk_index,
        .last_chunk_len = last_chunk_len,
        .round_keys = round_keys,
        .rounds = rounds,
        .h = h,
        .flags = flags,
        .key = key,
        .key_len = key_len,
        .error = ASSET_SHIELD_OK,
    };
    memcpy(job.base_iv, base_iv, sizeof(job.base_iv));
    decrypt_worker(&job);
    return job.error;
  }

  decrypt_job* jobs = (decrypt_job*)calloc((size_t)threads, sizeof(decrypt_job));
  if (!jobs) {
    return ASSET_SHIELD_ERR_ALLOC;
  }
#if defined(_WIN32)
  HANDLE* handles = (HANDLE*)calloc((size_t)threads, sizeof(HANDLE));
#else
  pthread_t* handles = (pthread_t*)calloc((size_t)threads, sizeof(pthread_t));
#endif
  if (!handles) {
    free(jobs);
    return ASSET_SHIELD_ERR_ALLOC;
  }

  size_t base = chunk_count / (size_t)threads;
  size_t extra = chunk_count % (size_t)threads;
  size_t start = 0;

  for (int i = 0; i < threads; i++) {
    size_t count = base + (i < (int)extra ? 1 : 0);
    size_t end = start + count;
    jobs[i] = (decrypt_job){
        .input = input,
        .output = output,
        .lengths = lengths,
        .offsets = offsets,
        .chunk_size = chunk_size,
        .start_chunk = start,
        .end_chunk = end,
        .last_chunk_index = last_chunk_index,
        .last_chunk_len = last_chunk_len,
        .round_keys = round_keys,
        .rounds = rounds,
        .h = h,
        .flags = flags,
        .key = key,
        .key_len = key_len,
        .error = ASSET_SHIELD_OK,
    };
    memcpy(jobs[i].base_iv, base_iv, sizeof(jobs[i].base_iv));

    if (count == 0) {
#if defined(_WIN32)
      handles[i] = NULL;
#endif
      continue;
    }
#if defined(_WIN32)
    handles[i] = CreateThread(NULL, 0, decrypt_worker, &jobs[i], 0, NULL);
    if (!handles[i]) {
      free(handles);
      free(jobs);
      return ASSET_SHIELD_ERR_THREAD;
    }
#else
    if (pthread_create(&handles[i], NULL, decrypt_worker, &jobs[i]) != 0) {
      free(handles);
      free(jobs);
      return ASSET_SHIELD_ERR_THREAD;
    }
#endif
    start = end;
  }

  int result = ASSET_SHIELD_OK;
  for (int i = 0; i < threads; i++) {
#if defined(_WIN32)
    if (handles[i]) {
      WaitForSingleObject(handles[i], INFINITE);
      CloseHandle(handles[i]);
    }
#else
    if (jobs[i].end_chunk > jobs[i].start_chunk) {
      pthread_join(handles[i], NULL);
    }
#endif
    if (jobs[i].error != ASSET_SHIELD_OK && result == ASSET_SHIELD_OK) {
      result = jobs[i].error;
    }
  }

  free(handles);
  free(jobs);
  return result;
}

int32_t asset_shield_encrypt(const uint8_t* data,
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
                             int32_t* out_length) {
  if (!data || !key || !out_data || !out_length || !base_iv) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  if (length < 0 || chunk_size <= 0) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  if (key_length != 32) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  if (base_iv_length != k_iv_len) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  (void)crypto_workers;

  if (compression_algo != k_algo_none && compression_algo != k_algo_zstd) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }

  const size_t plain_len = (size_t)length;
  const size_t chunk_sz = (size_t)chunk_size;
  const uint32_t original_length = (uint32_t)length;
  size_t chunk_count = 1;
  if (plain_len > 0) {
    chunk_count = (plain_len + chunk_sz - 1) / chunk_sz;
  }
  size_t last_chunk_len = (plain_len == 0) ? 0 : (plain_len - (chunk_count - 1) * chunk_sz);

  uint8_t flags = 0;
  uint8_t algo = (uint8_t)k_algo_none;
  if (compression_algo == k_algo_zstd) {
    flags |= k_flag_compressed;
    algo = (uint8_t)k_algo_zstd;
  }

  uint32_t round_keys[60];
  int rounds = 0;
  if (!aes_key_expand(key, key_length, round_keys, &rounds)) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }
  uint8_t h[16];
  uint8_t zero_block[16] = {0};
  aes_encrypt_block(zero_block, h, round_keys, rounds);

  size_t enc_payload_len = encrypted_payload_length(plain_len, chunk_sz);
  size_t total_len = (size_t)k_header_len_v4 + enc_payload_len;
  if (total_len > (size_t)INT32_MAX) {
    return ASSET_SHIELD_ERR_OVERFLOW;
  }

  uint8_t* out = (uint8_t*)malloc(total_len);
  if (!out) {
    return ASSET_SHIELD_ERR_ALLOC;
  }

  size_t offset = 0;
  memcpy(out + offset, k_magic, sizeof(k_magic));
  offset += sizeof(k_magic);
  out[offset++] = k_version4;
  out[offset++] = flags;
  out[offset++] = algo;
  out[offset++] = k_iv_len;
  write_u32_le(out + offset, (uint32_t)chunk_size);
  offset += 4;
  write_u32_le(out + offset, original_length);
  offset += 4;
  memcpy(out + offset, base_iv, k_iv_len);
  offset += k_iv_len;

  ZSTD_CCtx* cctx = NULL;
  if (compression_algo == k_algo_zstd) {
    cctx = ZSTD_createCCtx();
    if (!cctx) {
      free(out);
      return ASSET_SHIELD_ERR_ZSTD;
    }
#ifdef ZSTD_MULTITHREAD
    if (zstd_workers > 1) {
      ZSTD_CCtx_setParameter(cctx, ZSTD_c_nbWorkers, zstd_workers);
    }
#endif
  }

  for (size_t chunk = 0; chunk < chunk_count; chunk++) {
    size_t in_offset = chunk * chunk_sz;
    size_t plain_chunk_len =
        (chunk == chunk_count - 1) ? last_chunk_len : chunk_sz;

    const uint8_t* chunk_data = data + in_offset;
    uint8_t* temp = NULL;
    size_t stored_len = plain_chunk_len;
    uint32_t length_field = 0;
    int chunk_compressed = 0;

    if (compression_algo == k_algo_zstd && plain_chunk_len > 0) {
      size_t bound = ZSTD_compressBound(plain_chunk_len);
      temp = (uint8_t*)malloc(bound);
      if (!temp) {
        if (cctx) {
          ZSTD_freeCCtx(cctx);
        }
        free(out);
        return ASSET_SHIELD_ERR_ALLOC;
      }
      size_t result = ZSTD_compressCCtx(cctx,
                                        temp,
                                        bound,
                                        chunk_data,
                                        plain_chunk_len,
                                        compression_level);
      if (ZSTD_isError(result)) {
        free(temp);
        if (cctx) {
          ZSTD_freeCCtx(cctx);
        }
        free(out);
        return ASSET_SHIELD_ERR_ZSTD;
      }
      if (result < plain_chunk_len) {
        stored_len = result;
        chunk_data = temp;
        chunk_compressed = 1;
      }
    }

    if (stored_len > 0x7fffffff) {
      if (temp) {
        free(temp);
      }
      if (cctx) {
        ZSTD_freeCCtx(cctx);
      }
      free(out);
      return ASSET_SHIELD_ERR_OVERFLOW;
    }

    length_field = (uint32_t)stored_len;
    if (chunk_compressed) {
      length_field |= 0x80000000u;
    }

    write_u32_le(out + offset, length_field);
    offset += sizeof(uint32_t);

    uint8_t iv[12];
    if (!derive_chunk_iv(base_iv, (uint32_t)chunk, iv)) {
      if (temp) {
        free(temp);
      }
      if (cctx) {
        ZSTD_freeCCtx(cctx);
      }
      free(out);
      return ASSET_SHIELD_ERR_OVERFLOW;
    }

    int enc_result = gcm_encrypt_any(key,
                                     key_length,
                                     round_keys,
                                     rounds,
                                     h,
                                     iv,
                                     k_iv_len,
                                     chunk_data,
                                     (int)stored_len,
                                     out + offset);
    if (temp) {
      free(temp);
    }
    if (enc_result != ASSET_SHIELD_OK) {
      if (cctx) {
        ZSTD_freeCCtx(cctx);
      }
      free(out);
      return enc_result;
    }

    offset += stored_len + k_tag_len;
  }

  if (cctx) {
    ZSTD_freeCCtx(cctx);
  }

  *out_data = out;
  *out_length = (int32_t)offset;
  return ASSET_SHIELD_OK;
}

int32_t asset_shield_decrypt(const uint8_t* encrypted_data,
                             int32_t length,
                             const uint8_t* key,
                             int32_t key_length,
                             int32_t crypto_workers,
                             int32_t zstd_workers,
                             uint8_t** out_data,
                             int32_t* out_length) {
  if (!encrypted_data || !key || !out_data || !out_length) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  if (length < (int32_t)k_header_len_v4) {
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

  if (use_key_len != 32) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }

  if (memcmp(encrypted_data, k_magic, sizeof(k_magic)) != 0) {
    return ASSET_SHIELD_ERR_BAD_HEADER;
  }

  const uint8_t version = encrypted_data[4];
  if (version != k_version4) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }

  const uint8_t flags = encrypted_data[5];
  const uint8_t algo = encrypted_data[6];
  const uint8_t iv_len = encrypted_data[7];
  if (iv_len != k_iv_len) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }
  if (algo != k_algo_none && algo != k_algo_zstd) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }

  const uint32_t chunk_size = read_u32_le(encrypted_data, 8);
  const uint32_t original_length = read_u32_le(encrypted_data, 12);
  const uint8_t* base_iv = encrypted_data + 16;

  if (chunk_size == 0) {
    return ASSET_SHIELD_ERR_BAD_HEADER;
  }

  const size_t header_len = k_header_len_v4;
  const size_t data_len = (size_t)length - header_len;
  if (data_len < sizeof(uint32_t) + k_tag_len) {
    return ASSET_SHIELD_ERR_BAD_HEADER;
  }

  size_t chunk_count = 1;
  if (original_length > 0) {
    chunk_count = ((size_t)original_length + (size_t)chunk_size - 1) / (size_t)chunk_size;
  }
  size_t last_chunk_len = (original_length == 0)
      ? 0
      : ((size_t)original_length - (chunk_count - 1) * (size_t)chunk_size);
  size_t last_chunk_index = chunk_count - 1;

  uint32_t* lengths = (uint32_t*)calloc(chunk_count, sizeof(uint32_t));
  size_t* offsets = (size_t*)calloc(chunk_count, sizeof(size_t));
  if (!lengths || !offsets) {
    free(lengths);
    free(offsets);
    return ASSET_SHIELD_ERR_ALLOC;
  }

  size_t pos = header_len;
  for (size_t chunk = 0; chunk < chunk_count; chunk++) {
    if (pos + sizeof(uint32_t) > (size_t)length) {
      free(lengths);
      free(offsets);
      return ASSET_SHIELD_ERR_BAD_HEADER;
    }
    uint32_t len_field = read_u32_le(encrypted_data, pos);
    pos += sizeof(uint32_t);
    size_t stored_len = (size_t)(len_field & 0x7fffffff);
    int compressed = (len_field & 0x80000000u) != 0;
    size_t plain_len =
        (chunk == last_chunk_index) ? last_chunk_len : (size_t)chunk_size;

    if (original_length == 0 && (compressed || stored_len != 0)) {
      free(lengths);
      free(offsets);
      return ASSET_SHIELD_ERR_BAD_HEADER;
    }
    if (stored_len > (size_t)chunk_size) {
      free(lengths);
      free(offsets);
      return ASSET_SHIELD_ERR_BAD_HEADER;
    }
    if (!compressed && stored_len != plain_len) {
      free(lengths);
      free(offsets);
      return ASSET_SHIELD_ERR_BAD_HEADER;
    }
    if (compressed && (flags & k_flag_compressed) == 0) {
      free(lengths);
      free(offsets);
      return ASSET_SHIELD_ERR_UNSUPPORTED;
    }

    size_t cipher_len = stored_len + k_tag_len;
    if (pos + cipher_len > (size_t)length) {
      free(lengths);
      free(offsets);
      return ASSET_SHIELD_ERR_BAD_HEADER;
    }
    lengths[chunk] = len_field;
    offsets[chunk] = pos - header_len;
    pos += cipher_len;
  }

  if (pos != (size_t)length) {
    free(lengths);
    free(offsets);
    return ASSET_SHIELD_ERR_BAD_HEADER;
  }

  if ((flags & k_flag_compressed) != 0 && algo != k_algo_zstd) {
    free(lengths);
    free(offsets);
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }

  uint32_t round_keys[60];
  int rounds = 0;
  if (!aes_key_expand(use_key, use_key_len, round_keys, &rounds)) {
    free(lengths);
    free(offsets);
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }
  uint8_t h[16];
  uint8_t zero_block[16] = {0};
  aes_encrypt_block(zero_block, h, round_keys, rounds);

  uint8_t* output = NULL;
  uint8_t dummy = 0;
  if (original_length > 0) {
    output = (uint8_t*)malloc((size_t)original_length);
    if (!output) {
      free(lengths);
      free(offsets);
      return ASSET_SHIELD_ERR_ALLOC;
    }
  } else {
    output = &dummy;
  }

  int result = run_decrypt_jobs(encrypted_data + header_len,
                                output,
                                lengths,
                                offsets,
                                (size_t)chunk_size,
                                chunk_count,
                                last_chunk_index,
                                last_chunk_len,
                                round_keys,
                                rounds,
                                h,
                                base_iv,
                                flags,
                                use_key,
                                use_key_len,
                                crypto_workers);

  free(lengths);
  free(offsets);
  (void)zstd_workers;

  if (result != ASSET_SHIELD_OK) {
    if (original_length > 0) {
      free(output);
    }
    return result;
  }

  if (original_length == 0) {
    *out_data = NULL;
    *out_length = 0;
    return ASSET_SHIELD_OK;
  }

  if ((size_t)original_length > (size_t)INT32_MAX) {
    free(output);
    return ASSET_SHIELD_ERR_OVERFLOW;
  }

  *out_data = output;
  *out_length = (int32_t)original_length;
  return ASSET_SHIELD_OK;
}

int32_t asset_shield_set_key(const uint8_t* key, int32_t key_length) {
  if (!key || key_length != 32) {
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

int32_t asset_shield_selftest(void) {
  uint32_t state = 0x12345678u;
  for (int i = 0; i < 200; i++) {
    uint8_t x[16];
    uint8_t h[16];
    for (int j = 0; j < 16; j++) {
      state ^= state << 13;
      state ^= state >> 17;
      state ^= state << 5;
      x[j] = (uint8_t)state;
      state ^= state << 13;
      state ^= state >> 17;
      state ^= state << 5;
      h[j] = (uint8_t)state;
    }
    const ghash_table_full* ht = ghash_table_full_get(h);

    uint8_t ref[16];
    gcm_mul(x, h, ref);

    uint8_t fast[16];
    memcpy(fast, x, 16);
    ghash_mul_full(ht, fast);

    if (memcmp(ref, fast, 16) != 0) {
      return -1;
    }
  }
  return 0;
}

int32_t asset_shield_set_assets_base_path(const char* path) {
  if (!path || path[0] == '\0') {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  GHASH_LOCK();
  if (g_assets_base_path) {
    free(g_assets_base_path);
    g_assets_base_path = NULL;
  }
  size_t len = strlen(path);
  g_assets_base_path = (char*)malloc(len + 1);
  if (!g_assets_base_path) {
    GHASH_UNLOCK();
    return ASSET_SHIELD_ERR_ALLOC;
  }
  memcpy(g_assets_base_path, path, len + 1);
  GHASH_UNLOCK();
  return ASSET_SHIELD_OK;
}

int32_t asset_shield_set_android_asset_manager(void* mgr) {
#if defined(__ANDROID__)
  if (!mgr) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  g_asset_manager = (AAssetManager*)mgr;
  return ASSET_SHIELD_OK;
#else
  (void)mgr;
  return ASSET_SHIELD_ERR_UNSUPPORTED;
#endif
}

static int read_file_all(const char* path, uint8_t** out, int32_t* out_len) {
  if (!path || !out || !out_len) return ASSET_SHIELD_ERR_INVALID_ARGS;
  FILE* f = fopen(path, "rb");
  if (!f) return ASSET_SHIELD_ERR_INVALID_ARGS;
  if (fseek(f, 0, SEEK_END) != 0) {
    fclose(f);
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  long size = ftell(f);
  if (size < 0 || size > INT32_MAX) {
    fclose(f);
    return ASSET_SHIELD_ERR_OVERFLOW;
  }
  if (fseek(f, 0, SEEK_SET) != 0) {
    fclose(f);
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  uint8_t* buf = (uint8_t*)malloc((size_t)size);
  if (!buf) {
    fclose(f);
    return ASSET_SHIELD_ERR_ALLOC;
  }
  if (size > 0) {
    size_t got = fread(buf, 1, (size_t)size, f);
    if (got != (size_t)size) {
      free(buf);
      fclose(f);
      return ASSET_SHIELD_ERR_INVALID_ARGS;
    }
  }
  fclose(f);
  *out = buf;
  *out_len = (int32_t)size;
  return ASSET_SHIELD_OK;
}

#if defined(__ANDROID__)
static int read_android_asset_all(const char* rel, uint8_t** out, int32_t* out_len) {
  if (!rel || !out || !out_len) return ASSET_SHIELD_ERR_INVALID_ARGS;
  if (!g_asset_manager) return ASSET_SHIELD_ERR_INVALID_ARGS;
  char full[1024];
  const char* prefix = "flutter_assets/";
  if (strncmp(rel, prefix, strlen(prefix)) == 0) {
    snprintf(full, sizeof(full), "%s", rel);
  } else {
    snprintf(full, sizeof(full), "%s%s", prefix, rel);
  }
  AAsset* asset = AAssetManager_open(g_asset_manager, full, AASSET_MODE_STREAMING);
  if (!asset) return ASSET_SHIELD_ERR_INVALID_ARGS;
  off_t len = AAsset_getLength(asset);
  if (len < 0 || len > INT32_MAX) {
    AAsset_close(asset);
    return ASSET_SHIELD_ERR_OVERFLOW;
  }
  uint8_t* buf = (uint8_t*)malloc((size_t)len);
  if (!buf) {
    AAsset_close(asset);
    return ASSET_SHIELD_ERR_ALLOC;
  }
  int64_t read_total = 0;
  while (read_total < len) {
    int r = AAsset_read(asset, buf + read_total, (size_t)(len - read_total));
    if (r <= 0) break;
    read_total += r;
  }
  AAsset_close(asset);
  if (read_total != len) {
    free(buf);
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  *out = buf;
  *out_len = (int32_t)len;
  return ASSET_SHIELD_OK;
}
#endif

int32_t asset_shield_load_and_decrypt_asset(const char* rel_path,
                                            const uint8_t* key,
                                            int32_t key_length,
                                            int32_t crypto_workers,
                                            int32_t zstd_workers,
                                            uint8_t** out_data,
                                            int32_t* out_length) {
  if (!rel_path || !key || !out_data || !out_length) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  uint8_t* enc = NULL;
  int32_t enc_len = 0;

#if defined(__ANDROID__)
  int rc = read_android_asset_all(rel_path, &enc, &enc_len);
  if (rc != ASSET_SHIELD_OK) return rc;
#else
  GHASH_LOCK();
  const char* base = g_assets_base_path;
  char* base_copy = NULL;
  if (base) {
    size_t blen = strlen(base);
    base_copy = (char*)malloc(blen + 1);
    if (base_copy) {
      memcpy(base_copy, base, blen + 1);
    }
  }
  GHASH_UNLOCK();
  if (!base_copy) return ASSET_SHIELD_ERR_INVALID_ARGS;
  char full[2048];
  snprintf(full, sizeof(full), "%s/%s", base_copy, rel_path);
  int rc = read_file_all(full, &enc, &enc_len);
  free(base_copy);
  if (rc != ASSET_SHIELD_OK) return rc;
#endif

  uint8_t* plain = NULL;
  int32_t plain_len = 0;
  rc = asset_shield_decrypt(enc,
                            enc_len,
                            key,
                            key_length,
                            crypto_workers,
                            zstd_workers,
                            &plain,
                            &plain_len);
  free(enc);
  if (rc != ASSET_SHIELD_OK) return rc;
  *out_data = plain;
  *out_length = plain_len;
  return ASSET_SHIELD_OK;
}

int32_t asset_shield_encrypt_file(const char* input_path,
                                  const char* output_path,
                                  const uint8_t* key,
                                  int32_t key_length,
                                  int32_t compression_algo,
                                  int32_t compression_level,
                                  int32_t chunk_size,
                                  const uint8_t* base_iv,
                                  int32_t base_iv_length,
                                  int32_t zstd_workers) {
  if (!input_path || !output_path || !key || !base_iv) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  if (key_length != 32 || chunk_size <= 0 || base_iv_length != k_iv_len) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  if (compression_algo != k_algo_none && compression_algo != k_algo_zstd) {
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }

  FILE* in = fopen(input_path, "rb");
  if (!in) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  if (fseek(in, 0, SEEK_END) != 0) {
    fclose(in);
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  long end = ftell(in);
  if (end < 0) {
    fclose(in);
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  const uint32_t original_length = (uint32_t)end;
  if (fseek(in, 0, SEEK_SET) != 0) {
    fclose(in);
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }

  FILE* out = fopen(output_path, "wb");
  if (!out) {
    fclose(in);
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }

  const size_t chunk_sz = (size_t)chunk_size;
  const size_t plain_len = (size_t)original_length;
  size_t chunk_count = 1;
  if (plain_len > 0) {
    chunk_count = (plain_len + chunk_sz - 1) / chunk_sz;
  }
  size_t last_chunk_len = (plain_len == 0) ? 0 : (plain_len - (chunk_count - 1) * chunk_sz);

  uint8_t flags = 0;
  uint8_t algo = (uint8_t)k_algo_none;
  if (compression_algo == k_algo_zstd) {
    flags |= k_flag_compressed;
    algo = (uint8_t)k_algo_zstd;
  }

  uint32_t round_keys[60];
  int rounds = 0;
  if (!aes_key_expand(key, key_length, round_keys, &rounds)) {
    fclose(in);
    fclose(out);
    return ASSET_SHIELD_ERR_UNSUPPORTED;
  }
  uint8_t h16[16];
  uint8_t zero_block[16] = {0};
  aes_encrypt_block(zero_block, h16, round_keys, rounds);

  uint8_t header[28];
  size_t offset = 0;
  memcpy(header + offset, k_magic, sizeof(k_magic));
  offset += sizeof(k_magic);
  header[offset++] = k_version4;
  header[offset++] = flags;
  header[offset++] = algo;
  header[offset++] = k_iv_len;
  write_u32_le(header + offset, (uint32_t)chunk_size);
  offset += 4;
  write_u32_le(header + offset, original_length);
  offset += 4;
  memcpy(header + offset, base_iv, k_iv_len);
  offset += k_iv_len;
  if (offset != sizeof(header)) {
    fclose(in);
    fclose(out);
    return ASSET_SHIELD_ERR_BAD_HEADER;
  }

  if (fwrite(header, 1, sizeof(header), out) != sizeof(header)) {
    fclose(in);
    fclose(out);
    return ASSET_SHIELD_ERR_ALLOC;
  }

  ZSTD_CCtx* cctx = NULL;
  if (compression_algo == k_algo_zstd) {
    cctx = ZSTD_createCCtx();
    if (!cctx) {
      fclose(in);
      fclose(out);
      return ASSET_SHIELD_ERR_ZSTD;
    }
#ifdef ZSTD_MULTITHREAD
    if (zstd_workers > 1) {
      ZSTD_CCtx_setParameter(cctx, ZSTD_c_nbWorkers, zstd_workers);
    }
#else
    (void)zstd_workers;
#endif
  } else {
    (void)zstd_workers;
  }

  uint8_t* plain_buf = (uint8_t*)malloc(chunk_sz);
  if (!plain_buf) {
    if (cctx) ZSTD_freeCCtx(cctx);
    fclose(in);
    fclose(out);
    return ASSET_SHIELD_ERR_ALLOC;
  }

  for (size_t chunk = 0; chunk < chunk_count; chunk++) {
    const size_t want = (chunk == chunk_count - 1) ? last_chunk_len : chunk_sz;
    if (want > 0) {
      size_t got = fread(plain_buf, 1, want, in);
      if (got != want) {
        free(plain_buf);
        if (cctx) ZSTD_freeCCtx(cctx);
        fclose(in);
        fclose(out);
        return ASSET_SHIELD_ERR_INVALID_ARGS;
      }
    }

    const uint8_t* chunk_data = plain_buf;
    uint8_t* temp = NULL;
    size_t stored_len = want;
    int chunk_compressed = 0;

    if (compression_algo == k_algo_zstd && want > 0) {
      size_t bound = ZSTD_compressBound(want);
      temp = (uint8_t*)malloc(bound);
      if (!temp) {
        free(plain_buf);
        if (cctx) ZSTD_freeCCtx(cctx);
        fclose(in);
        fclose(out);
        return ASSET_SHIELD_ERR_ALLOC;
      }
      size_t zr = ZSTD_compressCCtx(cctx, temp, bound, plain_buf, want, compression_level);
      if (ZSTD_isError(zr)) {
        free(temp);
        free(plain_buf);
        if (cctx) ZSTD_freeCCtx(cctx);
        fclose(in);
        fclose(out);
        return ASSET_SHIELD_ERR_ZSTD;
      }
      if (zr < want) {
        stored_len = zr;
        chunk_data = temp;
        chunk_compressed = 1;
      }
    }

    uint32_t len_field = (uint32_t)stored_len;
    if (chunk_compressed) {
      len_field |= 0x80000000u;
    }
    uint8_t len_le[4];
    write_u32_le(len_le, len_field);
    if (fwrite(len_le, 1, 4, out) != 4) {
      if (temp) free(temp);
      free(plain_buf);
      if (cctx) ZSTD_freeCCtx(cctx);
      fclose(in);
      fclose(out);
      return ASSET_SHIELD_ERR_ALLOC;
    }

    uint8_t iv[12];
    if (!derive_chunk_iv(base_iv, (uint32_t)chunk, iv)) {
      if (temp) free(temp);
      free(plain_buf);
      if (cctx) ZSTD_freeCCtx(cctx);
      fclose(in);
      fclose(out);
      return ASSET_SHIELD_ERR_OVERFLOW;
    }

    uint8_t* cipher_buf = (uint8_t*)malloc(stored_len + k_tag_len);
    if (!cipher_buf) {
      if (temp) free(temp);
      free(plain_buf);
      if (cctx) ZSTD_freeCCtx(cctx);
      fclose(in);
      fclose(out);
      return ASSET_SHIELD_ERR_ALLOC;
    }
    int enc = gcm_encrypt_any(key,
                              key_length,
                              round_keys,
                              rounds,
                              h16,
                              iv,
                              k_iv_len,
                              chunk_data,
                              (int)stored_len,
                              cipher_buf);
    if (temp) free(temp);
    if (enc != ASSET_SHIELD_OK) {
      free(cipher_buf);
      free(plain_buf);
      if (cctx) ZSTD_freeCCtx(cctx);
      fclose(in);
      fclose(out);
      return enc;
    }

    if (stored_len + k_tag_len > 0) {
      if (fwrite(cipher_buf, 1, stored_len + k_tag_len, out) != stored_len + k_tag_len) {
        free(cipher_buf);
        free(plain_buf);
        if (cctx) ZSTD_freeCCtx(cctx);
        fclose(in);
        fclose(out);
        return ASSET_SHIELD_ERR_ALLOC;
      }
    }
    free(cipher_buf);
  }

  free(plain_buf);
  if (cctx) ZSTD_freeCCtx(cctx);
  fclose(in);
  fclose(out);
  return ASSET_SHIELD_OK;
}

int32_t asset_shield_compress(const uint8_t* data,
                              int32_t length,
                              int32_t level,
                              uint8_t** out_data,
                              int32_t* out_length) {
  if (!data || !out_data || !out_length || length < 0) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  if (length == 0) {
    *out_data = NULL;
    *out_length = 0;
    return ASSET_SHIELD_OK;
  }
  uint8_t* out = NULL;
  size_t out_len = 0;
  int result = zstd_compress_buffer(data,
                                    (size_t)length,
                                    level,
                                    1,
                                    &out,
                                    &out_len);
  if (result != ASSET_SHIELD_OK) {
    return result;
  }
  if (out_len > (size_t)INT32_MAX) {
    free(out);
    return ASSET_SHIELD_ERR_OVERFLOW;
  }
  *out_data = out;
  *out_length = (int32_t)out_len;
  return ASSET_SHIELD_OK;
}

int32_t asset_shield_decompress(const uint8_t* data,
                                int32_t length,
                                int32_t original_length,
                                uint8_t** out_data,
                                int32_t* out_length) {
  if (!data || !out_data || !out_length || length < 0) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  if (length == 0) {
    *out_data = NULL;
    *out_length = 0;
    return ASSET_SHIELD_OK;
  }
  if (original_length <= 0) {
    return ASSET_SHIELD_ERR_INVALID_ARGS;
  }
  uint8_t* out = NULL;
  size_t out_len = 0;
  int result = zstd_decompress_buffer(data,
                                      (size_t)length,
                                      (size_t)original_length,
                                      1,
                                      &out,
                                      &out_len);
  if (result != ASSET_SHIELD_OK) {
    return result;
  }
  if (out_len > (size_t)INT32_MAX) {
    free(out);
    return ASSET_SHIELD_ERR_OVERFLOW;
  }
  *out_data = out;
  *out_length = (int32_t)out_len;
  return ASSET_SHIELD_OK;
}
