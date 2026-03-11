#if defined(__ANDROID__)
#include <jni.h>
#include <android/asset_manager_jni.h>

#include "asset_shield_crypto.h"

JNIEXPORT void JNICALL
Java_com_asset_1shield_AssetShieldPlugin_nativeInit(JNIEnv* env,
                                                    jclass clazz,
                                                    jobject asset_manager) {
  (void)clazz;
  if (!asset_manager) return;
  AAssetManager* mgr = AAssetManager_fromJava(env, asset_manager);
  if (!mgr) return;
  asset_shield_set_android_asset_manager((void*)mgr);
}
#endif

