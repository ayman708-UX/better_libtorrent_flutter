#!/usr/bin/env bash
set -euo pipefail

TARGET=""
OUTPUT=""

DEPS=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --target=*)
      TARGET="${1#*=}"
      shift
      ;;
    --deps=*)
      DEPS="${1#*=}"
      shift
      ;;
    --output=*)
      OUTPUT="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$TARGET" || -z "$OUTPUT" || -z "$DEPS" ]]; then
  echo "Usage: $0 --target=<target> --deps=<deps_dir> --output=<dir>"
  exit 1
fi

# Ensure absolute paths
mkdir -p "$OUTPUT" "$DEPS"
OUTPUT=$(realpath "$OUTPUT")
DEPS=$(realpath "$DEPS")

CMAKE_SYSTEM_ARGS=()
if [[ "$TARGET" == android-* ]]; then
  if [[ "$TARGET" == "android-arm64" ]]; then ABI="arm64-v8a"; fi
  if [[ "$TARGET" == "android-arm" ]]; then ABI="armeabi-v7a"; fi
  if [[ "$TARGET" == "android-x86_64" ]]; then ABI="x86_64"; fi
  
  CMAKE_SYSTEM_ARGS=("-DCMAKE_TOOLCHAIN_FILE=${ANDROID_NDK_ROOT}/build/cmake/android.toolchain.cmake" "-DANDROID_ABI=${ABI}" "-DANDROID_PLATFORM=android-24" "-GNinja")
elif [[ "$TARGET" == ios64-* || "$TARGET" == iossimulator-* ]]; then
  CMAKE_SYSTEM_ARGS=("-DCMAKE_SYSTEM_NAME=iOS" "-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0" "-DENABLE_BITCODE=OFF" "-DENABLE_ARC=ON")
  if [[ "$TARGET" == *"simulator"* ]]; then
    CMAKE_SYSTEM_ARGS+=("-DCMAKE_OSX_SYSROOT=iphonesimulator")
    if [[ "$TARGET" == *"x86_64"* ]]; then
      CMAKE_SYSTEM_ARGS+=("-DCMAKE_OSX_ARCHITECTURES=x86_64")
    else
      CMAKE_SYSTEM_ARGS+=("-DCMAKE_OSX_ARCHITECTURES=arm64")
    fi
  else
    CMAKE_SYSTEM_ARGS+=("-DCMAKE_OSX_SYSROOT=iphoneos" "-DCMAKE_OSX_ARCHITECTURES=arm64")
  fi
elif [[ "$TARGET" == "linux-aarch64" ]]; then
  CMAKE_SYSTEM_ARGS=("-DCMAKE_SYSTEM_NAME=Linux" "-DCMAKE_SYSTEM_PROCESSOR=aarch64" "-DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc" "-DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++")
elif [[ "$TARGET" == "VC-WIN64A" ]]; then
  CMAKE_SYSTEM_ARGS=("-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded")
fi

echo "Building libtorrent..."
cmake -B build/libtorrent -S third_party/libtorrent \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -Dencryption=ON -Dwebtorrent=ON -Ddht=ON -Dlogging=OFF \
  -DBOOST_ROOT="$PWD/third_party/boost" \
  -DOPENSSL_ROOT_DIR="$DEPS" \
  -DOPENSSL_USE_STATIC_LIBS=ON \
  -DCMAKE_PREFIX_PATH="$DEPS" \
  -DCMAKE_CXX_STANDARD=17 \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_INSTALL_PREFIX="$DEPS" \
  ${CMAKE_SYSTEM_ARGS[@]:+"${CMAKE_SYSTEM_ARGS[@]}"}

cmake --build build/libtorrent --config Release -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu || echo 2)"
cmake --install build/libtorrent --config Release

echo "Building torrent_engine bridge..."
cmake -B build/engine -S src \
  -DCMAKE_BUILD_TYPE=Release \
  -DDEPS_DIR="$DEPS" \
  -DCMAKE_INSTALL_PREFIX="$OUTPUT" \
  ${CMAKE_SYSTEM_ARGS[@]:+"${CMAKE_SYSTEM_ARGS[@]}"}

cmake --build build/engine --config Release -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu || echo 2)"
cmake --install build/engine --config Release
