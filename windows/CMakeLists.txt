cmake_minimum_required(VERSION 3.14)
project(asset_shield LANGUAGES CXX)

# FFI-only plugin: expose bundled libraries to Flutter.
set(asset_shield_bundled_libraries
  "${CMAKE_CURRENT_SOURCE_DIR}/lib/asset_shield_crypto.dll"
  PARENT_SCOPE
)
