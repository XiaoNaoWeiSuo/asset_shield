import 'package:asset_shield_example/generated/asset_shield_config.dart';
import 'package:flutter/material.dart';
import 'package:asset_shield/asset_shield.dart';
import 'package:asset_shield/crypto.dart';

void main() {
  final key = ShieldKey.fromBase64(assetShieldKeyBase64);
  Shield.initialize(
    key: key,
    encryptedAssetsDir: assetShieldEncryptedDir,
  );
  runApp(
    DefaultAssetBundle(
      bundle: ShieldAssetBundle(),
      child: const MyApp(),
    ),
  );
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
            Image.asset("assets/images/images.jpeg"),
            Text('Asset Shield example app.\n', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
