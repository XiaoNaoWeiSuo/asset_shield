import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _NativeSelftest = Int32 Function();
typedef _DartSelftest = int Function();

void main() {
  // Load the default bundled library (same logic as ShieldFfi.load, but minimal).
  final candidates = <String>[];
  if (Platform.isMacOS) {
    candidates.add('macos/Frameworks/libasset_shield_crypto.dylib');
    candidates.add('build/macos/libasset_shield_crypto.dylib');
    candidates.add('libasset_shield_crypto.dylib');
  }

  DynamicLibrary? lib;
  String? picked;
  for (final c in candidates) {
    if (File(c).existsSync()) {
      lib = DynamicLibrary.open(c);
      picked = c;
      break;
    }
  }
  if (picked == null) {
    stderr.writeln('No library found. Looked in: ${candidates.join(', ')}');
    exit(1);
  }

  final fn = lib!.lookupFunction<_NativeSelftest, _DartSelftest>('asset_shield_selftest');
  final rc = fn();
  stdout.writeln('asset_shield_selftest: $rc (lib=$picked)');
  if (rc != 0) exit(2);
}
