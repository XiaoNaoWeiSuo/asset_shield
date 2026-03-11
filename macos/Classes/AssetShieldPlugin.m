#import "AssetShieldPlugin.h"

@implementation AssetShieldPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  (void)registrar;
  // macOS Flutter apps typically store assets under:
  // <App>.app/Contents/Frameworks/App.framework/Resources/flutter_assets
  // Fallback to <App>.app/Contents/Resources/flutter_assets if present.
  NSString* bundlePath = [[NSBundle mainBundle] bundlePath];
  NSString* base = [[bundlePath stringByAppendingPathComponent:@"Contents/Frameworks/App.framework/Resources"]
      stringByAppendingPathComponent:@"flutter_assets"];
  if (![[NSFileManager defaultManager] fileExistsAtPath:base]) {
    base = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"flutter_assets"];
  }
  extern int32_t asset_shield_set_assets_base_path(const char* path);
  asset_shield_set_assets_base_path([base fileSystemRepresentation]);
}
@end
