package com.asset_shield;

import android.content.res.AssetManager;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

public final class AssetShieldPlugin implements FlutterPlugin {
  static {
    try {
      System.loadLibrary("asset_shield_crypto");
    } catch (UnsatisfiedLinkError ignored) {
      // The library is also loaded by Dart FFI; best-effort here for init.
    }
  }

  private static native void nativeInit(@NonNull AssetManager assetManager);

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    nativeInit(binding.getApplicationContext().getAssets());
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    // No-op.
  }
}

