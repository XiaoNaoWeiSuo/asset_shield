import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Asset Shield Example')),
        body: const Center(
          child: Text(
            'Asset Shield example app.\n'
            'Configure shield_config.yaml and run build_runner to see encrypted assets.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
