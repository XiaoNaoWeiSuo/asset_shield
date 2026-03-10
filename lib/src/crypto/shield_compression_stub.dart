import 'dart:typed_data';

class ShieldCompression {
  static Uint8List compress(Uint8List data, {int level = 3}) {
    return data;
  }

  static Uint8List decompress(Uint8List data, {required int originalLength}) {
    throw UnsupportedError('Native compression is not available on this platform.');
  }
}
