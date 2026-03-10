import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'shield.dart';

/// Widget that loads, decrypts, and renders an encrypted image asset.
class ShieldImage extends StatelessWidget {
  /// Creates a [ShieldImage] for the given encrypted asset path.
  const ShieldImage(
    this.assetPath, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.placeholder,
    this.errorWidget,
  });

  final String assetPath;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: Shield.loadBytes(assetPath),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData) {
          return Image.memory(
            snapshot.data!,
            width: width,
            height: height,
            fit: fit,
            alignment: alignment,
          );
        }
        if (snapshot.hasError) {
          return errorWidget ?? const Icon(Icons.error);
        }
        return placeholder ??
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
      },
    );
  }
}
