import 'dart:typed_data';

import '../ffi/shield_ffi.dart';

class ShieldCompression {
  static Uint8List compress(Uint8List data, {int level = 3}) {
    if (data.isEmpty) {
      return data;
    }
    return ShieldFfi.load().compress(data, level: level);
  }

  static Uint8List decompress(Uint8List data, {required int originalLength}) {
    if (data.isEmpty) {
      return data;
    }
    return ShieldFfi.load().decompress(
      data,
      originalLength: originalLength,
    );
  }
}
