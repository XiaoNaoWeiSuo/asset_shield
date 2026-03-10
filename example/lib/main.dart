import 'package:flutter/material.dart';

import 'package:asset_shield/asset_shield.dart';
import 'package:asset_shield/crypto.dart';

import 'generated/asset_shield_map.dart';

void main() {
  final key = ShieldKey.fromBase64(assetShieldKeyBase64);
  Shield.initialize(
    key: key,
    assetMap: assetShieldMap,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Asset Shield Example')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('Encrypted Image Preview'),
              SizedBox(height: 16),
              ShieldImage(
                'assets/licensed-image.jpeg',
                width: 240,
                height: 160,
                fit: BoxFit.cover,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
