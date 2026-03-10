import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:asset_shield/crypto.dart';
import 'package:asset_shield/src/config/shield_cli_config.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    exitCode = 64;
    return;
  }

  final normalizedArgs = _normalizeArgs(args);
  final command = normalizedArgs.first;
  final options = normalizedArgs.sublist(1);

  switch (command) {
    case 'encrypt':
      final parsed = _parseEncryptOptions(options);
      await _runEncrypt(parsed);
      return;
    case 'gen-key':
      final length = _parseLengthOption(options);
      _runGenKey(length);
      return;
    case 'init':
      final parsed = _parseInitOptions(options);
      await _runInit(parsed);
      return;
    default:
      _printUsage();
      exitCode = 64;
  }
}

void _printUsage() {
  stdout.writeln('Asset Shield CLI');
  stdout.writeln('Usage: asset_shield <command> [options]');
  stdout.writeln('');
  stdout.writeln('Commands:');
  stdout.writeln('  encrypt  Encrypt assets based on shield_config.yaml');
  stdout.writeln('  gen-key  Generate a random AES key');
  stdout.writeln('  init     Create a shield_config.yaml template');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  encrypt  [--dry-run] [-v|--verbose]');
  stdout.writeln('  gen-key  [--length <bytes>]');
  stdout.writeln('  init     [-f|--force] [--no-gen-key] [--no-emit-key]');
}

Future<void> _runEncrypt(_EncryptOptions options) async {
  const configPath = 'shield_config.yaml';
  final dryRun = options.dryRun;
  final verbose = options.verbose;

  final config = await ShieldCliConfig.load(configPath);
  final keyBytes = ShieldKey.fromBase64(config.keyBase64);
  final compression = config.compression;
  final compressEnabled = compression != 'none';
  if (compression != 'zstd' && compression != 'none') {
    stderr.writeln('Unsupported compression "$compression", falling back to none.');
  }

  final rawDir = Directory(config.rawAssetsDir);
  if (!await rawDir.exists()) {
    stderr.writeln('Raw assets directory not found: ${rawDir.path}');
    exitCode = 66;
    return;
  }

  final encryptedDir = Directory(config.encryptedAssetsDir);
  if (!dryRun) {
    await encryptedDir.create(recursive: true);
  }

  final assetMap = <String, String>{};
  final files = await rawDir.list(recursive: true).where((entity) {
    if (entity is! File) return false;
    if (config.extensions.isEmpty) return true;
    final ext = p.extension(entity.path).toLowerCase();
    return config.extensions.contains(ext);
  }).toList();

  for (final entity in files) {
    final file = entity as File;
    final relative = p.relative(file.path, from: rawDir.path);
    final encryptedRelative = '$relative.dat';
    final encryptedPath = p.join(encryptedDir.path, encryptedRelative);

    final originalAssetPath = _toPosix(p.join(config.rawAssetsDir, relative));
    final encryptedAssetPath = _toPosix(p.join(config.encryptedAssetsDir, encryptedRelative));

    assetMap[originalAssetPath] = encryptedAssetPath;

    if (verbose || dryRun) {
      stdout.writeln('${dryRun ? '[dry-run] ' : ''}$originalAssetPath -> $encryptedAssetPath');
    }

    if (dryRun) {
      continue;
    }

    final bytes = await file.readAsBytes();
    final encrypted = ShieldCrypto.encrypt(
      Uint8List.fromList(bytes),
      keyBytes,
      compress: compressEnabled && compression == 'zstd',
      compressionLevel: config.compressionLevel,
    );
    final outFile = File(encryptedPath);
    await outFile.parent.create(recursive: true);
    await outFile.writeAsBytes(encrypted, flush: true);
  }

  if (dryRun) {
    return;
  }

  await _writeMapFile(config, assetMap);
  stdout.writeln('Encrypted ${assetMap.length} assets.');
}

void _runGenKey(int length) {
  final key = ShieldKey.generate(lengthBytes: length);
  stdout.writeln(ShieldKey.toBase64(key));
}

Future<void> _runInit(_InitOptions options) async {
  const outputPath = 'shield_config.yaml';
  final force = options.force;
  final genKey = options.genKey;
  final emitKey = options.emitKey;

  final file = File(outputPath);
  if (await file.exists() && !force) {
    stderr.writeln('Config already exists: ${file.path}');
    exitCode = 73;
    return;
  }

  final keyBase64 = genKey
      ? ShieldKey.toBase64(ShieldKey.generate(lengthBytes: 32))
      : 'REPLACE_WITH_BASE64_KEY';

  final buffer = StringBuffer()
    ..writeln('raw_assets_dir: assets')
    ..writeln('encrypted_assets_dir: assets/encrypted')
    ..writeln('map_output: lib/generated/asset_shield_map.dart')
    ..writeln('compression: zstd')
    ..writeln('compression_level: 3')
    ..writeln('extensions:')
    ..writeln('  - .png')
    ..writeln('  - .json')
    ..writeln('  - .mp3')
    ..writeln('key: "$keyBase64"')
    ..writeln('emit_key: ${emitKey ? 'true' : 'false'}');

  await file.parent.create(recursive: true);
  await file.writeAsString(buffer.toString(), flush: true);
  stdout.writeln('Wrote config: ${file.path}');
}

Future<void> _writeMapFile(
  ShieldCliConfig config,
  Map<String, String> assetMap,
) async {
  final mapFile = File(config.mapOutput);
  await mapFile.parent.create(recursive: true);

  final sortedKeys = assetMap.keys.toList()..sort();
  final buffer = StringBuffer()
    ..writeln('// Generated by asset_shield. Do not edit by hand.')
    ..writeln("const Map<String, String> assetShieldMap = <String, String>{");

  for (final key in sortedKeys) {
    final value = assetMap[key]!;
    buffer.writeln("  '${_escape(key)}': '${_escape(value)}',");
  }
  buffer.writeln('};');

  if (config.emitKey) {
    buffer
      ..writeln('')
      ..writeln("const String assetShieldKeyBase64 = '${_escape(config.keyBase64)}';");
  }

  await mapFile.writeAsString(buffer.toString(), flush: true);
  stdout.writeln('Wrote asset map: ${mapFile.path}');
}

List<String> _normalizeArgs(List<String> args) {
  if (args.isEmpty) {
    return args;
  }
  final command = args.first;
  final mapped = switch (command) {
    'e' || 'enc' => 'encrypt',
    'g' || 'k' => 'gen-key',
    'i' => 'init',
    _ => command,
  };
  if (mapped == command) {
    return args;
  }
  return <String>[mapped, ...args.skip(1)];
}

String _escape(String input) {
  return input.replaceAll('\\', '\\\\').replaceAll("'", r"\'");
}

String _toPosix(String input) {
  return input.replaceAll('\\', '/');
}

_EncryptOptions _parseEncryptOptions(List<String> args) {
  var dryRun = false;
  var verbose = false;
  for (final arg in args) {
    switch (arg) {
      case '--dry-run':
        dryRun = true;
      case '-v':
      case '--verbose':
        verbose = true;
      default:
        stderr.writeln('Unknown option for encrypt: $arg');
        exitCode = 64;
        return const _EncryptOptions();
    }
  }
  return _EncryptOptions(dryRun: dryRun, verbose: verbose);
}

int _parseLengthOption(List<String> args) {
  if (args.isEmpty) {
    return 32;
  }
  if (args.length == 2 && (args[0] == '--length' || args[0] == '-l')) {
    return int.tryParse(args[1]) ?? 32;
  }
  stderr.writeln('Unknown option for gen-key: ${args.join(' ')}');
  exitCode = 64;
  return 32;
}

_InitOptions _parseInitOptions(List<String> args) {
  var force = false;
  var genKey = true;
  var emitKey = true;
  for (final arg in args) {
    switch (arg) {
      case '-f':
      case '--force':
        force = true;
      case '--no-gen-key':
        genKey = false;
      case '--no-emit-key':
        emitKey = false;
      default:
        stderr.writeln('Unknown option for init: $arg');
        exitCode = 64;
        return const _InitOptions();
    }
  }
  return _InitOptions(force: force, genKey: genKey, emitKey: emitKey);
}

class _EncryptOptions {
  const _EncryptOptions({this.dryRun = false, this.verbose = false});

  final bool dryRun;
  final bool verbose;
}

class _InitOptions {
  const _InitOptions({this.force = false, this.genKey = true, this.emitKey = true});

  final bool force;
  final bool genKey;
  final bool emitKey;
}
