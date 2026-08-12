#!/usr/bin/env bash
set -euo pipefail

TARGET=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --target=*)
      TARGET="${1#*=}"
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

if [[ -z "$TARGET" || -z "$OUTPUT" ]]; then
  echo "Usage: $0 --target=<target> --output=<dir>"
  exit 1
fi

# Ensure absolute paths
mkdir -p "$OUTPUT"
OUTPUT=$(realpath "$OUTPUT")

OPENSSL_ROOT="$OUTPUT"
if [[ ! -d "$OPENSSL_ROOT/lib" && ! -d "$OPENSSL_ROOT/lib64" ]]; then
  echo "Error: OpenSSL must be built into $OPENSSL_ROOT first."
  exit 1
fi

CMAKE_SYSTEM_ARGS=""
if [[ "$TARGET" == android-* ]]; then
  if [[ "$TARGET" == "android-arm64" ]]; then ABI="arm64-v8a"; fi
  if [[ "$TARGET" == "android-arm" ]]; then ABI="armeabi-v7a"; fi
  if [[ "$TARGET" == "android-x86_64" ]]; then ABI="x86_64"; fi
  
  # Android Toolchain is passed from GitHub Actions via env var
  CMAKE_SYSTEM_ARGS="-DCMAKE_TOOLCHAIN_FILE=${ANDROID_NDK_ROOT}/build/cmake/android.toolchain.cmake -DANDROID_ABI=${ABI} -DANDROID_PLATFORM=android-24 -GNinja"
elif [[ "$TARGET" == ios64-* || "$TARGET" == iossimulator-* ]]; then
  # iOS Toolchain passed via env var or assumed from Xcode
  PLATFORM="OS64"
  if [[ "$TARGET" == *"simulator"* ]]; then
    PLATFORM="SIMULATORARM64"
    if [[ "$TARGET" == *"x86_64"* ]]; then
      PLATFORM="SIMULATOR64"
    fi
  fi
  CMAKE_SYSTEM_ARGS="-DCMAKE_TOOLCHAIN_FILE=${PWD}/third_party/ios-cmake/ios.toolchain.cmake -DPLATFORM=${PLATFORM} -DDEPLOYMENT_TARGET=13.0 -DENABLE_BITCODE=OFF -DENABLE_ARC=ON"
elif [[ "$TARGET" == "VC-WIN64A" ]]; then
  CMAKE_SYSTEM_ARGS="-G \"Visual Studio 17 2022\" -A x64 -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded"
fi

OPENSSL_LIB_DIR="$OPENSSL_ROOT/lib"
if [[ ! -d "$OPENSSL_LIB_DIR" && -d "$OPENSSL_ROOT/lib64" ]]; then
  OPENSSL_LIB_DIR="$OPENSSL_ROOT/lib64"
fi

if [[ "$TARGET" == "VC-WIN64A" ]]; then
  CRYPTO_LIB="$OPENSSL_LIB_DIR/libcrypto.lib"
  SSL_LIB="$OPENSSL_LIB_DIR/libssl.lib"
else
  CRYPTO_LIB="$OPENSSL_LIB_DIR/libcrypto.a"
  SSL_LIB="$OPENSSL_LIB_DIR/libssl.a"
fi

cmake -B build/libdatachannel -S third_party/libdatachannel \
  -DUSE_GNUTLS=0 -DUSE_MBEDTLS=0 -DUSE_NICE=0 \
  -DNO_EXAMPLES=1 -DNO_TESTS=1 -DNO_WEBSOCKET=0 \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DOPENSSL_ROOT_DIR="$OPENSSL_ROOT" \
  -DOPENSSL_INCLUDE_DIR="$OPENSSL_ROOT/include" \
  -DOPENSSL_CRYPTO_LIBRARY="$CRYPTO_LIB" \
  -DOPENSSL_SSL_LIBRARY="$SSL_LIB" \
  -DOPENSSL_USE_STATIC_LIBS=ON \
  -DCMAKE_INSTALL_PREFIX="$OUTPUT" \
  $CMAKE_SYSTEM_ARGS

cmake --build build/libdatachannel --config Release -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu || echo 2)"
cmake --install build/libdatachannel --config Release
