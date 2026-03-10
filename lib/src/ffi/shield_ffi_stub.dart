import 'dart:typed_data';

/// Stub FFI for unsupported platforms (e.g. web).
class ShieldFfi {
  ShieldFfi._();

  static ShieldFfi load({String? libraryPath}) {
    throw UnsupportedError('Native FFI is not available on this platform.');
  }

  Uint8List decrypt(Uint8List encrypted, Uint8List key) {
    throw UnsupportedError('Native FFI is not available on this platform.');
  }

  Uint8List compress(Uint8List data, {int level = 3}) {
    throw UnsupportedError('Native FFI is not available on this platform.');
  }

  Uint8List decompress(Uint8List data, {required int originalLength}) {
    throw UnsupportedError('Native FFI is not available on this platform.');
  }

  void setKey(Uint8List key) {
    throw UnsupportedError('Native FFI is not available on this platform.');
  }

  void clearKey() {
    throw UnsupportedError('Native FFI is not available on this platform.');
  }
}
