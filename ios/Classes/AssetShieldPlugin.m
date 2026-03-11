#import "AssetShieldPlugin.h"

@implementation AssetShieldPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  (void)registrar;
  // iOS Flutter apps typically store assets under:
  // <App>.app/Frameworks/App.framework/flutter_assets
  // Fallback to <App>.app/flutter_assets if present.
  NSString* bundlePath = [[NSBundle mainBundle] bundlePath];
  NSString* base = [[bundlePath stringByAppendingPathComponent:@"Frameworks/App.framework"]
      stringByAppendingPathComponent:@"flutter_assets"];
  if (![[NSFileManager defaultManager] fileExistsAtPath:base]) {
    base = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"flutter_assets"];
  }
  extern int32_t asset_shield_set_assets_base_path(const char* path);
  asset_shield_set_assets_base_path([base fileSystemRepresentation]);
}
@end
