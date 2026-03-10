Asset Shield
============

Asset Shield 是一个 Flutter 静态资源加密解密插件，提供从开发期加密到运行期解密的完整链路。你可以在构建前将图片/配置/音视频等资源加密为二进制文件，在运行时通过 FFI 解密并在内存中直接使用。

主要特性
--------

- CLI 加密工具：批量加密资源并生成映射表
- 运行时 API：Shield.loadBytes / Shield.loadString
- 便捷组件：ShieldImage 直接显示加密图片
- 原生解密：Android/iOS/macOS 预编译动态库
- 大文件处理：超过阈值自动切到 Isolate 解密

快速开始
--------

1) 生成密钥

```bash
dart run asset_shield gen-key
```

2) 在项目中创建配置文件 shield_config.yaml

```yaml
raw_assets_dir: assets
encrypted_assets_dir: assets/encrypted
map_output: lib/generated/asset_shield_map.dart
extensions:
  - .png
  - .json
  - .mp3
key: "REPLACE_WITH_BASE64_KEY"
emit_key: true
```

3) 执行加密

```bash
dart run asset_shield encrypt -c shield_config.yaml
```

会生成：
- 加密资源：assets/encrypted/*
- 映射表：lib/generated/asset_shield_map.dart

4) 在 pubspec.yaml 中注册加密资源目录

```yaml
flutter:
  assets:
    - assets/encrypted/
```

5) 运行时初始化并使用

```dart
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
```

显示加密图片：

```dart
ShieldImage(
  'assets/licensed-image.jpeg',
  width: 240,
  height: 160,
  fit: BoxFit.cover,
)
```

读取加密文本/JSON：

```dart
final jsonString = await Shield.loadString('assets/config.json');
```

命令行工具
----------

生成密钥：

```bash
dart run asset_shield gen-key --length 32
```

加密并生成映射表：

```bash
dart run asset_shield encrypt -c shield_config.yaml
```

运行时 API
----------

- Shield.initialize({ key, assetMap, isolateThresholdBytes, useNative, nativeLibraryPath })
- Shield.initializeWithNativeKey({ assetMap, isolateThresholdBytes, nativeLibraryPath })
- Shield.setNativeKey(keyBytes)
- Shield.clearNativeKey()
- Shield.loadBytes(assetPath)
- Shield.loadString(assetPath)
- ShieldImage(assetPath)

原生库说明
----------

- Android：预编译 .so 放在 android/src/main/jniLibs
- iOS：预编译 AssetShieldCrypto.xcframework 放在 ios/Frameworks
- macOS：预编译 libasset_shield_crypto.dylib 放在 macos/Frameworks

注意：如果需要指定自定义原生库路径，可在 Shield.initialize 中传入 nativeLibraryPath。

密钥管理
--------

插件支持两种模式：

1) Dart 传入密钥（默认）
- 在 Dart 中调用 Shield.initialize 并传入 key
- FFI 直接使用该 key 进行解密

2) 原生层密钥（混淆存储）
- 在编译原生库时通过 ASSET_SHIELD_KEY_BASE64 生成混淆后的内嵌密钥
- 运行时调用 Shield.initializeWithNativeKey，不需要在 Dart 暴露密钥
- 如需动态下发密钥，可在运行时调用 Shield.setNativeKey

生成内嵌密钥头文件：

```bash
ASSET_SHIELD_KEY_BASE64=<base64> ./tool/build_macos.sh
ASSET_SHIELD_KEY_BASE64=<base64> ./tool/build_ios.sh
ASSET_SHIELD_KEY_BASE64=<base64> ./tool/build_android.sh
```

开发与测试
----------

Mac 构建原生库：

```bash
./tool/build_macos.sh
```

iOS 构建原生库：

```bash
./tool/build_ios.sh
```

Android 构建原生库：

```bash
ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/<version> ./tool/build_android.sh
```

运行插件测试：

```bash
flutter test
```

示例工程测试：

```bash
cd example
flutter test
```

限制与安全建议
--------------

- 当前原生 AES-GCM 为自实现版本，建议在生产环境替换为成熟加密库并做安全审计
- 密钥管理目前为本地配置，建议结合运行时拉取或混淆手段
- 超大资源建议引入流式解密方案
