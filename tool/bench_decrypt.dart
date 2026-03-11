import 'dart:io';
import 'dart:typed_data';

import 'package:asset_shield/src/ffi/shield_ffi.dart';
import 'package:asset_shield/crypto.dart';

Uint8List _readKeyBytes() {
  final configFile = File('example/lib/generated/asset_shield_config.dart');
  if (configFile.existsSync()) {
    final content = configFile.readAsStringSync();
    final match = RegExp(r"assetShieldKeyBase64\s*=\s*'([^']+)'").firstMatch(content);
    if (match != null) {
      final keyBase64 = match.group(1)!;
      return ShieldKey.fromBase64(keyBase64);
    }
  }
  final yamlFile = File('example/shield_config.yaml');
  if (!yamlFile.existsSync()) {
    throw StateError('No key found: missing example/lib/generated/asset_shield_config.dart and example/shield_config.yaml');
  }
  final content = yamlFile.readAsStringSync();
  final match = RegExp(r'^key:\s*"?([^"\n]+)"?$', multiLine: true)
      .firstMatch(content);
  if (match == null) {
    throw StateError('Key not found in example/shield_config.yaml');
  }
  return ShieldKey.fromBase64(match.group(1)!.trim());
}

List<File> _encryptedFiles() {
  final dir = Directory('example/assets/encrypted');
  if (!dir.existsSync()) {
    throw StateError('Encrypted assets dir not found: ${dir.path}');
  }
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dat'))
      .toList();
  if (files.isEmpty) {
    throw StateError('No .dat files found in ${dir.path}');
  }
  return files;
}

void _bench(String label, int cryptoWorkers, int zstdWorkers, int iterations) {
  final key = _readKeyBytes();
  final ffi = ShieldFfi.load();
  final files = _encryptedFiles();

  final encrypted = <String, Uint8List>{};
  for (final f in files) {
    encrypted[f.path] = Uint8List.fromList(f.readAsBytesSync());
  }

  // warmup
  for (final entry in encrypted.entries) {
    final out = ffi.decrypt(
      entry.value,
      key,
      cryptoWorkers: cryptoWorkers,
      zstdWorkers: zstdWorkers,
    );
    ffi.release(out);
  }

  final sw = Stopwatch()..start();
  int totalBytes = 0;
  for (var i = 0; i < iterations; i++) {
    for (final entry in encrypted.entries) {
      final out = ffi.decrypt(
        entry.value,
        key,
        cryptoWorkers: cryptoWorkers,
        zstdWorkers: zstdWorkers,
      );
      totalBytes += out.length;
      ffi.release(out);
    }
  }
  sw.stop();

  final seconds = sw.elapsedMicroseconds / 1e6;
  final mb = totalBytes / (1024 * 1024);
  final mbps = seconds == 0 ? 0 : mb / seconds;

  stdout.writeln(label);
  stdout.writeln('  files: ${encrypted.length}, iterations: $iterations');
  stdout.writeln('  total: ${mb.toStringAsFixed(2)} MiB in ${seconds.toStringAsFixed(3)} s');
  stdout.writeln('  throughput: ${mbps.toStringAsFixed(2)} MiB/s');
}

void main(List<String> args) {
  final iterations = args.isNotEmpty ? int.parse(args.first) : 200;
  _bench('decrypt (cryptoWorkers=1, zstdWorkers=1)', 1, 1, iterations);
  _bench('decrypt (cryptoWorkers=auto, zstdWorkers=auto)', -1, -1, iterations);
}
