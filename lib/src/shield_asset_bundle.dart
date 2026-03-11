import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'shield.dart';

/// AssetBundle that transparently decrypts assets defined in [Shield].
class ShieldAssetBundle extends CachingAssetBundle {
  /// Creates a bundle that decrypts assets using [Shield].
  ///
  /// [delegate] defaults to [rootBundle].
  ShieldAssetBundle({AssetBundle? delegate}) : _delegate = delegate ?? rootBundle;

  final AssetBundle _delegate;

  @override
  Future<ByteData> load(String key) async {
    final encryptedPath = Shield.resolvePathOrNull(key);
    if (encryptedPath == null) {
      return _delegate.load(key);
    }
    try {
      final decrypted = await Shield.loadBytes(key);
      return ByteData.view(
        decrypted.buffer,
        decrypted.offsetInBytes,
        decrypted.lengthInBytes,
      );
    } on FlutterError {
      return _delegate.load(key);
    }
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final encryptedPath = Shield.resolvePathOrNull(key);
    if (encryptedPath == null) {
      return _delegate.loadString(key, cache: cache);
    }
    final data = await load(key);
    return utf8.decode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async {
    final value = await loadString(key);
    return parser(value);
  }
}
