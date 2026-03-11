import 'dart:io';

import 'package:yaml/yaml.dart';

class ShieldCliConfig {
  ShieldCliConfig({
    required this.rawAssetsDir,
    required this.encryptedAssetsDir,
    required this.extensions,
    required this.keyBase64,
    required this.emitKey,
    required this.compression,
    required this.compressionLevel,
    required this.chunkSize,
    required this.cryptoWorkers,
    required this.zstdWorkers,
    required this.configOutput,
  });

  final String rawAssetsDir;
  final String encryptedAssetsDir;
  final List<String> extensions;
  final String keyBase64;
  final bool emitKey;
  final String compression;
  final int compressionLevel;
  final int chunkSize;
  final int cryptoWorkers;
  final int zstdWorkers;
  final String configOutput;

  static Future<ShieldCliConfig> load(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('Config file not found: ${file.path}');
    }

    final content = await file.readAsString();
    return parseYaml(content, file.path);
  }

  static ShieldCliConfig parseYaml(String content, String sourcePath) {
    final yaml = loadYaml(content);
    if (yaml is! YamlMap) {
      throw StateError('Invalid YAML format in $sourcePath.');
    }

    String readString(String key, {String? fallback}) {
      final value = yaml[key];
      if (value == null) {
        if (fallback != null) return fallback;
        throw StateError('Missing required field: $key');
      }
      if (value is! String) {
        throw StateError('Field $key must be a string.');
      }
      return value;
    }

    bool readBool(String key, {bool fallback = false}) {
      final value = yaml[key];
      if (value == null) return fallback;
      if (value is! bool) {
        throw StateError('Field $key must be a boolean.');
      }
      return value;
    }

    List<String> readExtensions(String key) {
      final value = yaml[key];
      if (value == null) return <String>[];
      if (value is! YamlList) {
        throw StateError('Field $key must be a list.');
      }
      final list = <String>[];
      for (final item in value) {
        if (item is! String) {
          throw StateError('Extension values must be strings.');
        }
        final normalized = item.startsWith('.') ? item.toLowerCase() : '.${item.toLowerCase()}';
        list.add(normalized);
      }
      return list;
    }

    return ShieldCliConfig(
      rawAssetsDir: readString('raw_assets_dir', fallback: 'assets'),
      encryptedAssetsDir: readString('encrypted_assets_dir', fallback: 'assets/encrypted'),
      extensions: readExtensions('extensions'),
      keyBase64: readString('key'),
      emitKey: readBool('emit_key', fallback: false),
      compression: readString('compression', fallback: 'zstd').toLowerCase(),
      compressionLevel: _readInt(yaml, 'compression_level', fallback: 3),
      chunkSize: _readInt(yaml, 'chunk_size', fallback: 256 * 1024),
      cryptoWorkers: _readInt(yaml, 'crypto_workers', fallback: -1),
      zstdWorkers: _readInt(yaml, 'zstd_workers', fallback: -1),
      configOutput: readString(
        'config_output',
        fallback: 'lib/generated/asset_shield_config.dart',
      ),
    );
  }
}

int _readInt(YamlMap yaml, String key, {required int fallback}) {
  final value = yaml[key];
  if (value == null) return fallback;
  if (value is int) return value;
  throw StateError('Field $key must be an integer.');
}
