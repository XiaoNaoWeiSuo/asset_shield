import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef _NativeEncrypt = Int32 Function(
  Pointer<Uint8> data,
  Int32 length,
  Pointer<Uint8> key,
  Int32 keyLength,
  Int32 compressionAlgo,
  Int32 compressionLevel,
  Int32 chunkSize,
  Pointer<Uint8> baseIv,
  Int32 baseIvLength,
  Int32 cryptoWorkers,
  Int32 zstdWorkers,
  Pointer<Pointer<Uint8>> outData,
  Pointer<Int32> outLength,
);

typedef _DartEncrypt = int Function(
  Pointer<Uint8> data,
  int length,
  Pointer<Uint8> key,
  int keyLength,
  int compressionAlgo,
  int compressionLevel,
  int chunkSize,
  Pointer<Uint8> baseIv,
  int baseIvLength,
  int cryptoWorkers,
  int zstdWorkers,
  Pointer<Pointer<Uint8>> outData,
  Pointer<Int32> outLength,
);

typedef _NativeEncryptFile = Int32 Function(
  Pointer<Utf8> inputPath,
  Pointer<Utf8> outputPath,
  Pointer<Uint8> key,
  Int32 keyLength,
  Int32 compressionAlgo,
  Int32 compressionLevel,
  Int32 chunkSize,
  Pointer<Uint8> baseIv,
  Int32 baseIvLength,
  Int32 zstdWorkers,
);

typedef _DartEncryptFile = int Function(
  Pointer<Utf8> inputPath,
  Pointer<Utf8> outputPath,
  Pointer<Uint8> key,
  int keyLength,
  int compressionAlgo,
  int compressionLevel,
  int chunkSize,
  Pointer<Uint8> baseIv,
  int baseIvLength,
  int zstdWorkers,
);

typedef _NativeDecrypt = Int32 Function(
  Pointer<Uint8> data,
  Int32 length,
  Pointer<Uint8> key,
  Int32 keyLength,
  Int32 cryptoWorkers,
  Int32 zstdWorkers,
  Pointer<Pointer<Uint8>> outData,
  Pointer<Int32> outLength,
);

typedef _DartDecrypt = int Function(
  Pointer<Uint8> data,
  int length,
  Pointer<Uint8> key,
  int keyLength,
  int cryptoWorkers,
  int zstdWorkers,
  Pointer<Pointer<Uint8>> outData,
  Pointer<Int32> outLength,
);

typedef _NativeSetAssetsBasePath = Int32 Function(Pointer<Utf8> path);
typedef _DartSetAssetsBasePath = int Function(Pointer<Utf8> path);

typedef _NativeDecryptAsset = Int32 Function(
  Pointer<Utf8> relPath,
  Pointer<Uint8> key,
  Int32 keyLength,
  Int32 cryptoWorkers,
  Int32 zstdWorkers,
  Pointer<Pointer<Uint8>> outData,
  Pointer<Int32> outLength,
);

typedef _DartDecryptAsset = int Function(
  Pointer<Utf8> relPath,
  Pointer<Uint8> key,
  int keyLength,
  int cryptoWorkers,
  int zstdWorkers,
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
      : _encrypt = library.lookupFunction<_NativeEncrypt, _DartEncrypt>(
          'asset_shield_encrypt',
        ),
        _encryptFile = library.lookupFunction<_NativeEncryptFile, _DartEncryptFile>(
          'asset_shield_encrypt_file',
        ),
        _decrypt = library.lookupFunction<_NativeDecrypt, _DartDecrypt>(
          'asset_shield_decrypt',
        ),
        _setAssetsBasePath =
            library.lookupFunction<_NativeSetAssetsBasePath, _DartSetAssetsBasePath>(
          'asset_shield_set_assets_base_path',
        ),
        _decryptAsset = library.lookupFunction<_NativeDecryptAsset, _DartDecryptAsset>(
          'asset_shield_load_and_decrypt_asset',
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

  final _DartEncrypt _encrypt;
  final _DartEncryptFile _encryptFile;
  final _DartDecrypt _decrypt;
  final _DartSetAssetsBasePath _setAssetsBasePath;
  final _DartDecryptAsset _decryptAsset;
  final _DartFree _free;
  final _DartCompress _compress;
  final _DartDecompress _decompress;
  final _DartSetKey _setKey;
  final _DartClearKey _clearKey;

  static ShieldFfi? _cached;
  static final Expando<Pointer<Uint8>> _nativePtr =
      Expando<Pointer<Uint8>>('asset_shield_native_ptr');
  static final Finalizer<Pointer<Uint8>> _finalizer =
      Finalizer<Pointer<Uint8>>(_freeNative);

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
    if (Platform.isMacOS) {
      // Prefer the in-process dylib so native asset base path set by the plugin
      // is shared with FFI calls. Falling back to an external dylib can create
      // a separate image with its own globals.
      try {
        final instance = ShieldFfi._(DynamicLibrary.process());
        _cached = instance;
        return instance;
      } catch (_) {
        // Fall back to resolving a bundled library.
      }
    }
    final library = _openDefaultLibrary();
    final instance = ShieldFfi._(library);
    _cached = instance;
    return instance;
  }

  static void _freeNative(Pointer<Uint8> ptr) {
    try {
      ShieldFfi.load()._free(ptr);
    } catch (_) {
      // Ignore dispose errors from finalizers.
    }
  }

  static Uint8List _wrapNativeBuffer(Pointer<Uint8> ptr, int length) {
    if (length == 0) {
      if (ptr.address != 0) {
        _freeNative(ptr);
      }
      return Uint8List(0);
    }
    if (ptr.address == 0) {
      return Uint8List(0);
    }
    final list = ptr.asTypedList(length);
    final buffer = list.buffer;
    _nativePtr[buffer] = ptr;
    _finalizer.attach(buffer, ptr, detach: buffer);
    return list;
  }

  void release(Uint8List bytes) {
    final ptr = _nativePtr[bytes.buffer];
    if (ptr == null) return;
    _nativePtr[bytes.buffer] = null;
    _finalizer.detach(bytes.buffer);
    _free(ptr);
  }

  Uint8List encrypt(
    Uint8List plain,
    Uint8List key, {
    required int compressionAlgo,
    required int compressionLevel,
    required int chunkSize,
    required Uint8List baseIv,
    required int cryptoWorkers,
    required int zstdWorkers,
  }) {
    final dataPtr = malloc<Uint8>(plain.length);
    final keyPtr = malloc<Uint8>(key.length);
    final ivPtr = malloc<Uint8>(baseIv.length);
    final outPtr = malloc<Pointer<Uint8>>();
    final outLen = malloc<Int32>();

    try {
      if (plain.isNotEmpty) {
        dataPtr.asTypedList(plain.length).setAll(0, plain);
      }
      if (key.isNotEmpty) {
        keyPtr.asTypedList(key.length).setAll(0, key);
      }
      if (baseIv.isNotEmpty) {
        ivPtr.asTypedList(baseIv.length).setAll(0, baseIv);
      }

      final result = _encrypt(
        dataPtr,
        plain.length,
        keyPtr,
        key.length,
        compressionAlgo,
        compressionLevel,
        chunkSize,
        ivPtr,
        baseIv.length,
        cryptoWorkers,
        zstdWorkers,
        outPtr,
        outLen,
      );

      if (result != 0) {
        throw StateError('Native encrypt failed: $result');
      }

      final length = outLen.value;
      return _wrapNativeBuffer(outPtr.value, length);
    } finally {
      malloc.free(dataPtr);
      malloc.free(keyPtr);
      malloc.free(ivPtr);
      malloc.free(outPtr);
      malloc.free(outLen);
    }
  }

  void encryptFile(
    String inputPath,
    String outputPath,
    Uint8List key, {
    required int compressionAlgo,
    required int compressionLevel,
    required int chunkSize,
    required Uint8List baseIv,
    required int zstdWorkers,
  }) {
    final inPtr = inputPath.toNativeUtf8();
    final outPtr = outputPath.toNativeUtf8();
    final keyPtr = malloc<Uint8>(key.length);
    final ivPtr = malloc<Uint8>(baseIv.length);
    try {
      if (key.isNotEmpty) {
        keyPtr.asTypedList(key.length).setAll(0, key);
      }
      if (baseIv.isNotEmpty) {
        ivPtr.asTypedList(baseIv.length).setAll(0, baseIv);
      }
      final result = _encryptFile(
        inPtr,
        outPtr,
        keyPtr,
        key.length,
        compressionAlgo,
        compressionLevel,
        chunkSize,
        ivPtr,
        baseIv.length,
        zstdWorkers,
      );
      if (result != 0) {
        throw StateError('Native encryptFile failed: $result');
      }
    } finally {
      malloc.free(inPtr);
      malloc.free(outPtr);
      malloc.free(keyPtr);
      malloc.free(ivPtr);
    }
  }

  void setAssetsBasePath(String path) {
    final ptr = path.toNativeUtf8();
    try {
      final result = _setAssetsBasePath(ptr);
      if (result != 0) {
        throw StateError('Native setAssetsBasePath failed: $result');
      }
    } finally {
      malloc.free(ptr);
    }
  }

  Uint8List decryptAsset(
    String relPath,
    Uint8List key, {
    required int cryptoWorkers,
    required int zstdWorkers,
  }) {
    final pathPtr = relPath.toNativeUtf8();
    final keyAlloc = key.isEmpty ? 1 : key.length;
    final keyPtr = malloc<Uint8>(keyAlloc);
    final outPtr = malloc<Pointer<Uint8>>();
    final outLen = malloc<Int32>();
    try {
      if (key.isNotEmpty) {
        keyPtr.asTypedList(key.length).setAll(0, key);
      }
      final result = _decryptAsset(
        pathPtr,
        keyPtr,
        key.length,
        cryptoWorkers,
        zstdWorkers,
        outPtr,
        outLen,
      );
      if (result != 0) {
        throw StateError('Native decryptAsset failed: $result');
      }
      final length = outLen.value;
      return _wrapNativeBuffer(outPtr.value, length);
    } finally {
      malloc.free(pathPtr);
      malloc.free(keyPtr);
      malloc.free(outPtr);
      malloc.free(outLen);
    }
  }

  Uint8List decrypt(
    Uint8List encrypted,
    Uint8List key, {
    required int cryptoWorkers,
    required int zstdWorkers,
  }) {
    final dataPtr = malloc<Uint8>(encrypted.length);
    final keyAlloc = key.isEmpty ? 1 : key.length;
    final keyPtr = malloc<Uint8>(keyAlloc);
    final outPtr = malloc<Pointer<Uint8>>();
    final outLen = malloc<Int32>();

    try {
      if (encrypted.isNotEmpty) {
        dataPtr.asTypedList(encrypted.length).setAll(0, encrypted);
      }
      if (key.isNotEmpty) {
        keyPtr.asTypedList(key.length).setAll(0, key);
      }

      final result = _decrypt(
        dataPtr,
        encrypted.length,
        keyPtr,
        key.length,
        cryptoWorkers,
        zstdWorkers,
        outPtr,
        outLen,
      );

      if (result != 0) {
        throw StateError('Native decrypt failed: $result');
      }

      final length = outLen.value;
      return _wrapNativeBuffer(outPtr.value, length);
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
      return _wrapNativeBuffer(outPtr.value, length);
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
      return _wrapNativeBuffer(outPtr.value, length);
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
