import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

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

class ShieldFfi {
  ShieldFfi._(this._library)
      : _decrypt = _library.lookupFunction<_NativeDecrypt, _DartDecrypt>(
          'asset_shield_decrypt',
        ),
        _free = _library.lookupFunction<_NativeFree, _DartFree>(
          'asset_shield_free',
        ),
        _setKey = _library.lookupFunction<_NativeSetKey, _DartSetKey>(
          'asset_shield_set_key',
        ),
        _clearKey = _library.lookupFunction<_NativeClearKey, _DartClearKey>(
          'asset_shield_clear_key',
        );

  final DynamicLibrary _library;
  final _DartDecrypt _decrypt;
  final _DartFree _free;
  final _DartSetKey _setKey;
  final _DartClearKey _clearKey;

  static ShieldFfi? _cached;

  static ShieldFfi load({String? libraryPath}) {
    if (libraryPath != null && libraryPath.isNotEmpty) {
      return ShieldFfi._(DynamicLibrary.open(libraryPath));
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
      keyPtr.asTypedList(key.length).setAll(0, key);

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

  static DynamicLibrary _openDefaultLibrary() {
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
}
