import 'dart:io';
import 'dart:ui' as ui;

import 'package:asset_shield/asset_shield.dart';
import 'package:asset_shield/crypto.dart';
import 'package:asset_shield_example/generated/asset_shield_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF0B5FFF),
      ),
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
              '缺少生成的配置文件或密钥。\n\n'
              '请在 example/ 目录下执行:\n'
              '  dart run asset_shield init\n'
              '  dart run asset_shield encrypt\n\n'
              '然后重启 App。',
            ),
          ),
        ),
      ),
    );
  }
}

enum _BenchMode {
  nativeRead,
  bundleRead,
}

class BenchPage extends StatefulWidget {
  const BenchPage({super.key});

  @override
  State<BenchPage> createState() => _BenchPageState();
}

class _BenchPageState extends State<BenchPage> {
  final _assetPathController =
      TextEditingController(text: 'assets/images/images.jpeg');
  final _itersController = TextEditingController(text: '20');
  final _cryptoWorkersController = TextEditingController(text: '-1');
  final _zstdWorkersController = TextEditingController(text: '-1');

  bool _warmup = true;
  bool _running = false;
  String _log = '';
  ui.Image? _preview;
  _BenchSummary? _lastSummary;

  @override
  void dispose() {
    _assetPathController.dispose();
    _itersController.dispose();
    _cryptoWorkersController.dispose();
    _zstdWorkersController.dispose();
    _preview?.dispose();
    super.dispose();
  }

  int _normalizeWorkers(int v) {
    if (v < 0) return Platform.numberOfProcessors;
    if (v == 0) return 1;
    return v < 1 ? 1 : v;
  }

  Future<_OneRun> _runOnce({
    required ShieldFfi ffi,
    required Uint8List key,
    required String encryptedPath,
    required _BenchMode mode,
    required int cryptoWorkers,
    required int zstdWorkers,
    required bool decode,
  }) async {
    int bundleLoadUs = 0;
    int decryptUs = 0;
    int decodeUs = 0;
    int plainBytes = 0;
    int encBytes = 0;
    ui.Image? image;

    if (mode == _BenchMode.nativeRead) {
      final sw = Stopwatch()..start();
      final out = ffi.decryptAsset(
        encryptedPath,
        key,
        cryptoWorkers: cryptoWorkers,
        zstdWorkers: zstdWorkers,
      );
      try {
        sw.stop();
        decryptUs = sw.elapsedMicroseconds;
        plainBytes = out.length;

        if (decode) {
          final swDecode = Stopwatch()..start();
          final codec = await ui.instantiateImageCodec(out);
          final frame = await codec.getNextFrame();
          codec.dispose();
          swDecode.stop();
          decodeUs = swDecode.elapsedMicroseconds;
          image = frame.image;
        }
      } finally {
        ffi.release(out);
      }
    } else {
      final swLoad = Stopwatch()..start();
      final data = await rootBundle.load(encryptedPath);
      swLoad.stop();
      bundleLoadUs = swLoad.elapsedMicroseconds;

      final enc =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      encBytes = enc.length;

      final swDec = Stopwatch()..start();
      final out = ffi.decrypt(
        enc,
        key,
        cryptoWorkers: cryptoWorkers,
        zstdWorkers: zstdWorkers,
      );
      try {
        swDec.stop();
        decryptUs = swDec.elapsedMicroseconds;
        plainBytes = out.length;

        if (decode) {
          final swDecode = Stopwatch()..start();
          final codec = await ui.instantiateImageCodec(out);
          final frame = await codec.getNextFrame();
          codec.dispose();
          swDecode.stop();
          decodeUs = swDecode.elapsedMicroseconds;
          image = frame.image;
        }
      } finally {
        ffi.release(out);
      }
    }

    return _OneRun(
      mode: mode,
      bundleLoadUs: bundleLoadUs,
      decryptUs: decryptUs,
      decodeUs: decodeUs,
      plainBytes: plainBytes,
      encBytes: encBytes,
      image: image,
    );
  }

  Future<void> _runBench(_BenchMode mode) async {
    if (_running) return;

    setState(() {
      _running = true;
      _log = '';
      _lastSummary = null;
    });

    final log = StringBuffer();
    _BenchSummary? summary;
    ui.Image? last;

    try {
      final ffi = ShieldFfi.load();
      final key = ShieldKey.fromBase64(assetShieldKeyBase64);

      final iters = int.tryParse(_itersController.text.trim()) ?? 20;
      final cryptoWorkers =
          _normalizeWorkers(int.tryParse(_cryptoWorkersController.text.trim()) ?? -1);
      final zstdWorkers =
          _normalizeWorkers(int.tryParse(_zstdWorkersController.text.trim()) ?? -1);

      final originalPath = _assetPathController.text.trim();
      if (originalPath.isEmpty) {
        log.writeln('资源路径为空。');
        return;
      }

      final encryptedPath = Shield.resolvePath(originalPath);

      log.writeln('测试模式: ${mode == _BenchMode.nativeRead ? '原生读取+解密' : 'Bundle读取+解密'}');
      log.writeln('迭代次数: $iters, 预热: ${_warmup ? '开' : '关'}');
      log.writeln('cryptoWorkers: $cryptoWorkers, zstdWorkers: $zstdWorkers');
      log.writeln('原始路径: $originalPath');
      log.writeln('加密路径: $encryptedPath');
      log.writeln('');

      if (_warmup) {
        log.writeln('预热中...');
        await _runOnce(
          ffi: ffi,
          key: key,
          encryptedPath: encryptedPath,
          mode: mode,
          cryptoWorkers: cryptoWorkers,
          zstdWorkers: zstdWorkers,
          decode: false,
        );
        log.writeln('预热完成。');
        log.writeln('');
      }

      summary = _BenchSummary.zero(mode: mode);

      for (var i = 0; i < iters; i++) {
        log.writeln('第 ${i + 1} 次:');
        final r = await _runOnce(
          ffi: ffi,
          key: key,
          encryptedPath: encryptedPath,
          mode: mode,
          cryptoWorkers: cryptoWorkers,
          zstdWorkers: zstdWorkers,
          decode: true,
        );
        summary.add(r);

        log.writeln('  bundleLoad: ${(r.bundleLoadUs / 1000).toStringAsFixed(2)} ms');
        log.writeln('  解密耗时: ${(r.decryptUs / 1000).toStringAsFixed(2)} ms');
        log.writeln('  解码耗时: ${(r.decodeUs / 1000).toStringAsFixed(2)} ms');
        log.writeln(
          '  总耗时: ${(r.totalUs / 1000).toStringAsFixed(2)} ms, '
          '吞吐: ${r.throughputMiBs.toStringAsFixed(2)} MiB/s',
        );
        log.writeln('');

        if (r.image != null) {
          last?.dispose();
          last = r.image;
        }
        if (!mounted) break;
      }
    } catch (e, st) {
      log.writeln('发生错误: $e');
      log.writeln(st);
    } finally {
      if (!mounted) return;
      setState(() {
        _preview?.dispose();
        _preview = last;
        _log = log.toString();
        _lastSummary = summary;
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = _lastSummary;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary.withValues(alpha: 0.10),
              scheme.secondary.withValues(alpha: 0.08),
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HeaderCard(running: _running),
              const SizedBox(height: 12),
              _ControlsCard(
                running: _running,
                assetPathController: _assetPathController,
                itersController: _itersController,
                cryptoWorkersController: _cryptoWorkersController,
                zstdWorkersController: _zstdWorkersController,
                warmup: _warmup,
                onWarmupChanged: (v) => setState(() => _warmup = v),
                onRunNative: () => _runBench(_BenchMode.nativeRead),
                onRunBundle: () => _runBench(_BenchMode.bundleRead),
              ),
              const SizedBox(height: 12),
              _ResultCard(preview: _preview, summary: summary),
              const SizedBox(height: 12),
              _LogCard(log: _log),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.running});

  final bool running;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.18),
            scheme.secondary.withValues(alpha: 0.10),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.bolt, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Asset Shield 性能测试',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  running ? '执行中...（建议不要切到后台）' : '点击按钮触发: 读取 -> 解密 -> 解码',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                if (running) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlsCard extends StatelessWidget {
  const _ControlsCard({
    required this.running,
    required this.assetPathController,
    required this.itersController,
    required this.cryptoWorkersController,
    required this.zstdWorkersController,
    required this.warmup,
    required this.onWarmupChanged,
    required this.onRunNative,
    required this.onRunBundle,
  });

  final bool running;
  final TextEditingController assetPathController;
  final TextEditingController itersController;
  final TextEditingController cryptoWorkersController;
  final TextEditingController zstdWorkersController;
  final bool warmup;
  final ValueChanged<bool> onWarmupChanged;
  final VoidCallback onRunNative;
  final VoidCallback onRunBundle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '参数设置',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: assetPathController,
              enabled: !running,
              decoration: const InputDecoration(
                labelText: '原始资源路径（明文路径）',
                hintText: '例如: assets/images/images.jpeg',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: itersController,
                    enabled: !running,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '迭代次数',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: cryptoWorkersController,
                    enabled: !running,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'cryptoWorkers',
                      helperText: '-1=自动，0/1=单线程',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: zstdWorkersController,
                    enabled: !running,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'zstdWorkers',
                      helperText: '-1=自动，0/1=单线程',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Switch(
                  value: warmup,
                  onChanged: running ? null : onWarmupChanged,
                ),
                const SizedBox(width: 8),
                // Text('预热（推荐打开）', style: Theme.of(context).textTheme.bodyMedium),
                const Spacer(),
                FilledButton.icon(
                  onPressed: running ? null : onRunNative,
                  icon: const Icon(Icons.memory),
                  label: const Text('原生读取'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: running ? null : onRunBundle,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Bundle读取'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.preview, required this.summary});

  final ui.Image? preview;
  final _BenchSummary? summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '结果',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: scheme.surfaceContainerHighest,
                ),
                clipBehavior: Clip.antiAlias,
                child: preview == null
                    ? Center(
                        child: Text(
                          '尚未运行\n点击上方按钮开始测试',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      )
                    : RawImage(image: preview),
              ),
            ),
            const SizedBox(height: 12),
            if (summary == null)
              Text(
                '说明: 这里统计的是端到端耗时（读取+解密(+解压)+解码）。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              )
            else
              _SummaryView(summary: summary!),
          ],
        ),
      ),
    );
  }
}

class _SummaryView extends StatelessWidget {
  const _SummaryView({required this.summary});

  final _BenchSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '汇总（平均值）',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text('模式: ${summary.mode == _BenchMode.nativeRead ? '原生读取' : 'Bundle读取'}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text('总耗时: ${summary.avgTotalMs.toStringAsFixed(2)} ms',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text('吞吐: ${summary.avgThroughputMiBs.toStringAsFixed(2)} MiB/s',
              style: Theme.of(context).textTheme.bodySmall),
          if (summary.mode == _BenchMode.bundleRead) ...[
            const SizedBox(height: 4),
            Text('Bundle读取: ${summary.avgBundleLoadMs.toStringAsFixed(2)} ms',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 4),
          Text('解密: ${summary.avgDecryptMs.toStringAsFixed(2)} ms',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text('解码: ${summary.avgDecodeMs.toStringAsFixed(2)} ms',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.log});

  final String log;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '运行日志',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                IconButton(
                  onPressed:
                      log.isEmpty ? null : () => Clipboard.setData(ClipboardData(text: log)),
                  icon: const Icon(Icons.copy_all),
                  tooltip: '复制日志',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 260,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: Text(
                  log.isEmpty ? '点击按钮开始测试...' : log,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OneRun {
  _OneRun({
    required this.mode,
    required this.bundleLoadUs,
    required this.decryptUs,
    required this.decodeUs,
    required this.plainBytes,
    required this.encBytes,
    required this.image,
  });

  final _BenchMode mode;
  final int bundleLoadUs;
  final int decryptUs;
  final int decodeUs;
  final int plainBytes;
  final int encBytes;
  final ui.Image? image;

  int get totalUs => bundleLoadUs + decryptUs + decodeUs;

  double get throughputMiBs {
    final sec = totalUs / 1e6;
    final mib = plainBytes / (1024 * 1024);
    if (sec == 0) return 0;
    return mib / sec;
  }
}

class _BenchSummary {
  _BenchSummary._({
    required this.mode,
    required this.runs,
    required this.totalBundleLoadUs,
    required this.totalDecryptUs,
    required this.totalDecodeUs,
    required this.totalPlainBytes,
  });

  factory _BenchSummary.zero({required _BenchMode mode}) {
    return _BenchSummary._(
      mode: mode,
      runs: 0,
      totalBundleLoadUs: 0,
      totalDecryptUs: 0,
      totalDecodeUs: 0,
      totalPlainBytes: 0,
    );
  }

  final _BenchMode mode;
  int runs;
  int totalBundleLoadUs;
  int totalDecryptUs;
  int totalDecodeUs;
  int totalPlainBytes;

  void add(_OneRun run) {
    runs += 1;
    totalBundleLoadUs += run.bundleLoadUs;
    totalDecryptUs += run.decryptUs;
    totalDecodeUs += run.decodeUs;
    totalPlainBytes += run.plainBytes;
  }

  double get avgBundleLoadMs => runs == 0 ? 0 : totalBundleLoadUs / runs / 1000.0;
  double get avgDecryptMs => runs == 0 ? 0 : totalDecryptUs / runs / 1000.0;
  double get avgDecodeMs => runs == 0 ? 0 : totalDecodeUs / runs / 1000.0;

  double get avgTotalMs =>
      runs == 0 ? 0 : (totalBundleLoadUs + totalDecryptUs + totalDecodeUs) / runs / 1000.0;

  double get avgThroughputMiBs {
    final sec = (totalBundleLoadUs + totalDecryptUs + totalDecodeUs) / 1e6;
    final mib = totalPlainBytes / (1024 * 1024);
    if (sec == 0) return 0;
    return mib / sec;
  }
}
