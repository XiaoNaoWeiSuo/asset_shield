import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

void main(List<String> args) {
  final keyArg = _readArg(args, '--key');
  if (keyArg == null || keyArg.isEmpty) {
    stderr.writeln('Usage: dart run tool/gen_embedded_key.dart --key <base64> [--out <path>]');
    exit(64);
  }
  final outPath = _readArg(args, '--out') ?? 'native/asset_shield_embedded_key.h';

  final keyBytes = Uint8List.fromList(base64.decode(keyArg.trim()));
  if (keyBytes.length != 16 && keyBytes.length != 32) {
    stderr.writeln('Key length must be 16 or 32 bytes.');
    exit(64);
  }

  final random = Random.secure();
  final mask = Uint8List.fromList(
    List<int>.generate(keyBytes.length, (_) => random.nextInt(256)),
  );
  final obfuscated = Uint8List(keyBytes.length);
  for (var i = 0; i < keyBytes.length; i++) {
    obfuscated[i] = keyBytes[i] ^ mask[i];
  }

  final buffer = StringBuffer()
    ..writeln('#pragma once')
    ..writeln('#include <stdint.h>')
    ..writeln('#include <string.h>')
    ..writeln('')
    ..writeln('#define ASSET_SHIELD_EMBEDDED_KEY_LEN ${keyBytes.length}')
    ..writeln('static const uint8_t ASSET_SHIELD_KEY_MASK[] = {${_bytes(mask)}};')
    ..writeln('static const uint8_t ASSET_SHIELD_KEY_DATA[] = {${_bytes(obfuscated)}};')
    ..writeln('')
    ..writeln('static inline int asset_shield_build_embedded_key(uint8_t* out_key,')
    ..writeln('                                                  int* out_len) {')
    ..writeln('  if (!out_key || !out_len) {')
    ..writeln('    return 0;')
    ..writeln('  }')
    ..writeln('  *out_len = ASSET_SHIELD_EMBEDDED_KEY_LEN;')
    ..writeln('  for (int i = 0; i < ASSET_SHIELD_EMBEDDED_KEY_LEN; i++) {')
    ..writeln('    out_key[i] = (uint8_t)(ASSET_SHIELD_KEY_DATA[i] ^ ASSET_SHIELD_KEY_MASK[i]);')
    ..writeln('  }')
    ..writeln('  return 1;')
    ..writeln('}');

  File(outPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(buffer.toString());
}

String? _readArg(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}

String _bytes(Uint8List bytes) {
  return bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ');
}
