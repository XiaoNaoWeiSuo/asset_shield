#import "AssetShieldPlugin.h"

@implementation AssetShieldPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  (void)registrar;
  NSString* base = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"flutter_assets"];
  extern int32_t asset_shield_set_assets_base_path(const char* path);
  asset_shield_set_assets_base_path([base fileSystemRepresentation]);
}
@end
