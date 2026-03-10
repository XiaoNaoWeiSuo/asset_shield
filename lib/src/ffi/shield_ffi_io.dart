import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef _NativeDecrypt = Int32 Function(
  Pointer<Uint8> data,
  Int32 length,
  Pointer<Uint8> key,
  Int32 keyLength,
  Pointer<Pointer<Uint8>> outData,
  Pointer<Int32> outLength,
);

typedef _DartDecrypt = int Function(
  Pointer<Uint8> data,
  int length,
  Pointer<Uint8> key,
  int keyLength,
  Pointer<Pointer<Uint8>> outData,
  Pointer<Int32> outLength,
);

typedef _NativeFree = Void Function(Pointer<Uint8>);
typedef _DartFree = void Function(Pointer<Uint8>);

typedef _NativeSetKey = Int32 Function(Pointer<Uint8> key, Int32 length);
typedef _DartSetKey = int Function(Pointer<Uint8> key, int length);

typedef _NativeClearKey = Void Function();
typedef _DartClearKey = void Function();

typedef _NativeCompress = Int32 Function(
  Pointer<Uint8> data,
  Int32 length,
  Int32 level,
  Pointer<Pointer<Uint8>> outData,
  Pointer<Int32> outLength,
);
typedef _DartCompress = int Function(
  Pointer<Uint8> data,
  int length,
  int level,
  Pointer<Pointer<Uint8>> outData,
  Pointer<Int32> outLength,
);

typedef _NativeDecompress = Int32 Function(
  Pointer<Uint8> data,
  Int32 length,
  Int32 originalLength,
  Pointer<Pointer<Uint8>> outData,
  Pointer<Int32> outLength,
);
typedef _DartDecompress = int Function(
  Pointer<Uint8> data,
  int length,
  int originalLength,
  Pointer<Pointer<Uint8>> outData,
  Pointer<Int32> outLength,
);

/// FFI bridge to native crypto and compression.
class ShieldFfi {
  ShieldFfi._(DynamicLibrary library)
      : _decrypt = library.lookupFunction<_NativeDecrypt, _DartDecrypt>(
          'asset_shield_decrypt',
        ),
        _free = library.lookupFunction<_NativeFree, _DartFree>(
          'asset_shield_free',
        ),
        _compress = library.lookupFunction<_NativeCompress, _DartCompress>(
          'asset_shield_compress',
        ),
        _decompress = library.lookupFunction<_NativeDecompress, _DartDecompress>(
          'asset_shield_decompress',
        ),
        _setKey = library.lookupFunction<_NativeSetKey, _DartSetKey>(
          'asset_shield_set_key',
        ),
        _clearKey = library.lookupFunction<_NativeClearKey, _DartClearKey>(
          'asset_shield_clear_key',
        );

  final _DartDecrypt _decrypt;
  final _DartFree _free;
  final _DartCompress _compress;
  final _DartDecompress _decompress;
  final _DartSetKey _setKey;
  final _DartClearKey _clearKey;

  static ShieldFfi? _cached;

  static ShieldFfi load({String? libraryPath}) {
    final envPath = Platform.environment['ASSET_SHIELD_NATIVE_LIB'];
    if (libraryPath != null && libraryPath.isNotEmpty) {
      return ShieldFfi._(DynamicLibrary.open(libraryPath));
    }
    if (envPath != null && envPath.isNotEmpty && File(envPath).existsSync()) {
      return ShieldFfi._(DynamicLibrary.open(envPath));
    }
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    final library = _openDefaultLibrary();
    final instance = ShieldFfi._(library);
    _cached = instance;
    return instance;
  }

  Uint8List decrypt(Uint8List encrypted, Uint8List key) {
    final dataPtr = malloc<Uint8>(encrypted.length);
    final keyPtr = malloc<Uint8>(key.length);
    final outPtr = malloc<Pointer<Uint8>>();
    final outLen = malloc<Int32>();

    try {
      dataPtr.asTypedList(encrypted.length).setAll(0, encrypted);
      if (key.isNotEmpty) {
        keyPtr.asTypedList(key.length).setAll(0, key);
      }

      final result = _decrypt(
        dataPtr,
        encrypted.length,
        keyPtr,
        key.length,
        outPtr,
        outLen,
      );

      if (result != 0) {
        throw StateError('Native decrypt failed: $result');
      }

      final length = outLen.value;
      final output = Uint8List.fromList(outPtr.value.asTypedList(length));
      _free(outPtr.value);
      return output;
    } finally {
      malloc.free(dataPtr);
      malloc.free(keyPtr);
      malloc.free(outPtr);
      malloc.free(outLen);
    }
  }

  void setKey(Uint8List key) {
    final keyPtr = malloc<Uint8>(key.length);
    try {
      keyPtr.asTypedList(key.length).setAll(0, key);
      final result = _setKey(keyPtr, key.length);
      if (result != 0) {
        throw StateError('Native setKey failed: $result');
      }
    } finally {
      malloc.free(keyPtr);
    }
  }

  void clearKey() {
    _clearKey();
  }

  Uint8List compress(Uint8List data, {int level = 3}) {
    final dataPtr = malloc<Uint8>(data.length);
    final outPtr = malloc<Pointer<Uint8>>();
    final outLen = malloc<Int32>();
    try {
      dataPtr.asTypedList(data.length).setAll(0, data);
      final result = _compress(
        dataPtr,
        data.length,
        level,
        outPtr,
        outLen,
      );
      if (result != 0) {
        throw StateError('Native compress failed: $result');
      }
      final length = outLen.value;
      if (length == 0) {
        return Uint8List(0);
      }
      final output = Uint8List.fromList(outPtr.value.asTypedList(length));
      _free(outPtr.value);
      return output;
    } finally {
      malloc.free(dataPtr);
      malloc.free(outPtr);
      malloc.free(outLen);
    }
  }

  Uint8List decompress(Uint8List data, {required int originalLength}) {
    final dataPtr = malloc<Uint8>(data.length);
    final outPtr = malloc<Pointer<Uint8>>();
    final outLen = malloc<Int32>();
    try {
      dataPtr.asTypedList(data.length).setAll(0, data);
      final result = _decompress(
        dataPtr,
        data.length,
        originalLength,
        outPtr,
        outLen,
      );
      if (result != 0) {
        throw StateError('Native decompress failed: $result');
      }
      final length = outLen.value;
      if (length == 0) {
        return Uint8List(0);
      }
      final output = Uint8List.fromList(outPtr.value.asTypedList(length));
      _free(outPtr.value);
      return output;
    } finally {
      malloc.free(dataPtr);
      malloc.free(outPtr);
      malloc.free(outLen);
    }
  }

  static DynamicLibrary _openDefaultLibrary() {
    final candidate = _resolveBundledLibrary();
    if (candidate != null) {
      return DynamicLibrary.open(candidate);
    }
    if (Platform.isMacOS) {
      try {
        return DynamicLibrary.open('libasset_shield_crypto.dylib');
      } catch (_) {
        return DynamicLibrary.process();
      }
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('libasset_shield_crypto.so');
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('asset_shield_crypto.dll');
    }
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libasset_shield_crypto.so');
    }
    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }
    throw UnsupportedError('Unsupported platform for native crypto.');
  }

  static String? _resolveBundledLibrary() {
    final candidates = <String>[];
    if (Platform.isMacOS) {
      candidates.add('macos/Frameworks/libasset_shield_crypto.dylib');
    } else if (Platform.isLinux) {
      candidates.add('linux/lib/libasset_shield_crypto.so');
    } else if (Platform.isWindows) {
      candidates.add('windows/lib/asset_shield_crypto.dll');
    }

    return _findInParents(Directory.current.path, candidates);
  }

  static String? _findInParents(String start, List<String> relativePaths) {
    var dir = Directory(start);
    for (var i = 0; i < 6; i++) {
      for (final rel in relativePaths) {
        final candidate = p.join(dir.path, rel);
        if (File(candidate).existsSync()) {
          return candidate;
        }
      }
      final parent = dir.parent;
      if (parent.path == dir.path) {
        break;
      }
      dir = parent;
    }
    return null;
  }
}
