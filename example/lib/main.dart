import 'package:asset_shield_example/generated/asset_shield_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:asset_shield/asset_shield.dart';
import 'package:asset_shield/crypto.dart';
import 'dart:io';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  Uint8List? key;
  try {
    if (assetShieldKeyBase64.isNotEmpty) {
      key = ShieldKey.fromBase64(assetShieldKeyBase64);
    }
  } catch (_) {
    key = null;
  }

  if (key == null) {
    runApp(const MissingConfigApp());
    return;
  }

  Shield.initialize(
    key: key,
    encryptedAssetsDir: assetShieldEncryptedDir,
  );
  runApp(DefaultAssetBundle(bundle: ShieldAssetBundle(), child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const BenchPage(),
    );
  }
}

class MissingConfigApp extends StatelessWidget {
  const MissingConfigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Missing generated config.\\n\\n'
              'Run in example/:\\n'
              '  dart run asset_shield init\\n'
              '  dart run asset_shield encrypt\\n\\n'
              'Then restart the app.',
            ),
          ),
        ),
      ),
    );
  }
}

class BenchPage extends StatefulWidget {
  const BenchPage({super.key});

  @override
  State<BenchPage> createState() => _BenchPageState();
}

class _BenchPageState extends State<BenchPage> {
  final _pathsController = TextEditingController(
    text: 'assets/raw_bench/compressible.bin\nassets/raw_bench/random.bin',
  );
  final _itersController = TextEditingController(text: '5');
  final _cryptoWorkersController = TextEditingController(text: '-1');
  final _zstdWorkersController = TextEditingController(text: '-1');

  bool _warmup = true;
  bool _running = false;
  String _log = '';

  @override
  void dispose() {
    _pathsController.dispose();
    _itersController.dispose();
    _cryptoWorkersController.dispose();
    _zstdWorkersController.dispose();
    super.dispose();
  }

  int _normalizeWorkers(int v) {
    if (v < 0) return Platform.numberOfProcessors;
    if (v == 0) return 1;
    return v < 1 ? 1 : v;
  }

  List<String> _paths() {
    return _pathsController.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _runBench({required bool nativeRead}) async {
    if (_running) return;
    setState(() {
      _running = true;
      _log = '';
    });

    final ffi = ShieldFfi.load();
    final key = ShieldKey.fromBase64(assetShieldKeyBase64);

    final iters = int.tryParse(_itersController.text.trim()) ?? 5;
    final cryptoWorkers =
        _normalizeWorkers(int.tryParse(_cryptoWorkersController.text.trim()) ?? -1);
    final zstdWorkers =
        _normalizeWorkers(int.tryParse(_zstdWorkersController.text.trim()) ?? -1);

    final originalPaths = _paths();
    if (originalPaths.isEmpty) {
      setState(() {
        _log = 'No paths.\n';
      });
      return;
    }

    final encryptedPaths = <String>[];
    for (final p in originalPaths) {
      encryptedPaths.add(Shield.resolvePath(p));
    }

    void log(String line) {
      setState(() => _log += '$line\n');
    }

    log('mode: ${nativeRead ? 'native_read+decrypt' : 'bundle_load+decrypt'}');
    log('iters: $iters, warmup: $_warmup');
    log('cryptoWorkers: $cryptoWorkers, zstdWorkers: $zstdWorkers');
    log('files:');
    for (var i = 0; i < originalPaths.length; i++) {
      log('  ${originalPaths[i]} -> ${encryptedPaths[i]}');
    }

    // Warmup (don’t count): ensures JIT + native caches are hot.
    if (_warmup) {
      for (final encPath in encryptedPaths) {
        if (nativeRead) {
          final out = ffi.decryptAsset(
            encPath,
            key,
            cryptoWorkers: cryptoWorkers,
            zstdWorkers: zstdWorkers,
          );
          ffi.release(out);
        } else {
          final data = await rootBundle.load(encPath);
          final encBytes =
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          final out = ffi.decrypt(
            encBytes,
            key,
            cryptoWorkers: cryptoWorkers,
            zstdWorkers: zstdWorkers,
          );
          ffi.release(out);
        }
      }
    }

    int totalPlain = 0;
    int totalEnc = 0;
    final swTotal = Stopwatch()..start();

    for (var iter = 0; iter < iters; iter++) {
      final swIter = Stopwatch()..start();
      int iterPlain = 0;
      int iterEnc = 0;
      Duration bundleLoad = Duration.zero;
      Duration decryptTime = Duration.zero;

      for (final encPath in encryptedPaths) {
        if (nativeRead) {
          final sw = Stopwatch()..start();
          final out = ffi.decryptAsset(
            encPath,
            key,
            cryptoWorkers: cryptoWorkers,
            zstdWorkers: zstdWorkers,
          );
          sw.stop();
          decryptTime += sw.elapsed;
          iterPlain += out.length;
          ffi.release(out);
        } else {
          final swLoad = Stopwatch()..start();
          final data = await rootBundle.load(encPath);
          swLoad.stop();
          bundleLoad += swLoad.elapsed;

          final encBytes =
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          iterEnc += encBytes.length;

          final swDec = Stopwatch()..start();
          final out = ffi.decrypt(
            encBytes,
            key,
            cryptoWorkers: cryptoWorkers,
            zstdWorkers: zstdWorkers,
          );
          swDec.stop();
          decryptTime += swDec.elapsed;
          iterPlain += out.length;
          ffi.release(out);
        }
      }

      swIter.stop();
      totalPlain += iterPlain;
      totalEnc += iterEnc;

      final sec = swIter.elapsedMicroseconds / 1e6;
      final mib = iterPlain / (1024 * 1024);
      final throughput = sec == 0 ? 0.0 : mib / sec;

      if (nativeRead) {
        log('iter ${iter + 1}: ${mib.toStringAsFixed(2)} MiB in ${sec.toStringAsFixed(3)}s => ${throughput.toStringAsFixed(2)} MiB/s');
      } else {
        final loadSec = bundleLoad.inMicroseconds / 1e6;
        final decSec = decryptTime.inMicroseconds / 1e6;
        log('iter ${iter + 1}: plain ${mib.toStringAsFixed(2)} MiB, enc ${(iterEnc / (1024 * 1024)).toStringAsFixed(2)} MiB');
        log('  bundleLoad ${loadSec.toStringAsFixed(3)}s, decrypt ${decSec.toStringAsFixed(3)}s, total ${sec.toStringAsFixed(3)}s');
        log('  throughput ${throughput.toStringAsFixed(2)} MiB/s');
      }
    }

    swTotal.stop();
    final sec = swTotal.elapsedMicroseconds / 1e6;
    final mib = totalPlain / (1024 * 1024);
    final throughput = sec == 0 ? 0.0 : mib / sec;
    log('---');
    log('total: ${mib.toStringAsFixed(2)} MiB in ${sec.toStringAsFixed(3)}s => ${throughput.toStringAsFixed(2)} MiB/s');
    if (!nativeRead) {
      log('total enc read (bundle path): ${(totalEnc / (1024 * 1024)).toStringAsFixed(2)} MiB');
    }

    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final running = _running;
    return Scaffold(
      appBar: AppBar(title: const Text('Asset Shield Bench')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _itersController,
                      decoration: const InputDecoration(
                        labelText: 'Iterations',
                      ),
                      keyboardType: TextInputType.number,
                      enabled: !running,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _cryptoWorkersController,
                      decoration: const InputDecoration(
                        labelText: 'cryptoWorkers (-1=auto)',
                      ),
                      keyboardType: TextInputType.number,
                      enabled: !running,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _zstdWorkersController,
                      decoration: const InputDecoration(
                        labelText: 'zstdWorkers (-1=auto)',
                      ),
                      keyboardType: TextInputType.number,
                      enabled: !running,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Checkbox(
                    value: _warmup,
                    onChanged: running
                        ? null
                        : (v) => setState(() => _warmup = v ?? true),
                  ),
                  const Text('Warmup'),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: running ? null : () => _runBench(nativeRead: true),
                    child: const Text('Run Native Read'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: running ? null : () => _runBench(nativeRead: false),
                    child: const Text('Run Bundle Load'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: _pathsController,
                  enabled: !running,
                  maxLines: null,
                  decoration: const InputDecoration(
                    labelText: 'Original Asset Paths (one per line)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      _log,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
