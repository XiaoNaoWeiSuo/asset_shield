import 'package:asset_shield/asset_shield.dart';
import 'package:asset_shield/crypto.dart';
import 'package:asset_shield_example/generated/asset_shield_map.dart';
import 'package:flutter/material.dart';

void main() {
  final key = ShieldKey.fromBase64(assetShieldKeyBase64);
  Shield.initialize(key: key, assetMap: assetShieldMap);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Asset Shield Example')),
        body: Column(
          children: [
            ShieldImage('assets/images/images.jpeg'),
            Text('Asset Shield example app.\n', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
