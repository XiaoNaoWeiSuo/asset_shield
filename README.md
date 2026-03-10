Asset Shield
============

Asset Shield 是一个 Flutter 静态资源加密解密插件，提供从开发期加密到运行期解密的完整链路。你可以在构建前将图片/配置/音视频等资源加密为二进制文件，在运行时通过 FFI 解密并在内存中直接使用。

主要特性
--------

- CLI 加密工具：批量加密资源并生成映射表
- 资源压缩：原生 Zstd 压缩（默认对所有资源尝试，自动择优保留更小结果）
- 运行时 API：Shield.loadBytes / Shield.loadString
- 便捷组件：ShieldImage 直接显示加密图片
- 原生解密：AES-256-GCM（Android/iOS/macOS/Linux/Windows）
- 大文件处理：超过阈值自动切到 Isolate 解密

快速开始
--------

1) 生成密钥

```bash
dart run asset_shield gen-key
```

或直接初始化配置（自动生成密钥）：

```bash
dart run asset_shield init
```

2) 在项目中创建配置文件 shield_config.yaml

```yaml
raw_assets_dir: assets
encrypted_assets_dir: assets/encrypted
map_output: lib/generated/asset_shield_map.dart
compression: zstd
compression_level: 3
extensions:
  - .png
  - .json
  - .mp3
key: "REPLACE_WITH_BASE64_KEY"
emit_key: true
```

说明：
- `compression: zstd` 会对所有资源尝试压缩，若压缩后反而更大则自动保留原始数据
- Web 端如需运行，请将 `compression: none`
- 压缩依赖原生库，确保已包含各平台预编译库

发布者指南（多机编译）
--------------------

为了让使用者 `pub get` 即可使用，你需要在发布前编译并提交各平台原生库。

Mac（iOS + macOS）：

```bash
./tool/build_macos.sh
./tool/build_ios.sh
```

Linux：

```bash
./tool/build_linux.sh
```

Windows：

```powershell
.\tool\build_windows.ps1
```

Android（Mac 或 Linux）：

```bash
ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/<version> ./tool/build_android.sh
```

发布前检查产物目录：
- `android/src/main/jniLibs/**`
- `ios/Frameworks/AssetShieldCrypto.xcframework`
- `macos/Frameworks/libasset_shield_crypto.dylib`
- `linux/lib/libasset_shield_crypto.so`
- `windows/lib/asset_shield_crypto.dll`

3) 执行加密

```bash
dart run asset_shield encrypt
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

插件完整生命周期
---------------

1) 配置阶段（一次性）
- 通过 `dart run asset_shield init` 生成 `shield_config.yaml`
- 或手动创建配置文件，配置资源目录、输出目录、映射表路径、后缀、密钥

2) 构建阶段（每次资源变更）
- 手动模式：`dart run asset_shield encrypt`

3) 打包阶段（Flutter build）
- 只打包加密后的 `.dat` 资源
- 明文资源不进入包体

4) 运行阶段（App 内解密）
- 在 `main()` 中调用 `Shield.initialize`
- 使用 `Shield.loadBytes` / `Shield.loadString` 或 `ShieldImage` 直接读取和渲染

命令行工具
----------

更便捷的运行方式：

1) 全局激活（一次配置，后续直接用 asset_shield 命令）

```bash
dart pub global activate --path .
asset_shield init
asset_shield encrypt
```

2) 本地快捷脚本（无需全局安装）

```bash
./tool/asset_shield init
./tool/asset_shield encrypt
```

Windows：

```powershell
.\tool\asset_shield.ps1 init
.\tool\asset_shield.ps1 encrypt
```

生成密钥：

```bash
dart run asset_shield gen-key --length 32
```

初始化配置：

```bash
dart run asset_shield init
```

使用短命令：

```bash
dart run asset_shield e
dart run asset_shield g
dart run asset_shield i
```

加密并生成映射表：

```bash
dart run asset_shield encrypt
```

手动流程说明
------------

每次资源变更后执行：

```bash
dart run asset_shield encrypt
```

```

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
- Linux：预编译 libasset_shield_crypto.so 放在 linux/lib
- Windows：预编译 asset_shield_crypto.dll 放在 windows/lib

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

- 当前原生 AES-256-GCM 为自实现版本，建议在生产环境替换为成熟加密库并做安全审计
- Web 端不支持 Zstd 解压时，请在 web 构建中禁用压缩（compression: none）
- 密钥管理目前为本地配置，建议结合运行时拉取或混淆手段
- 超大资源建议引入流式解密方案
