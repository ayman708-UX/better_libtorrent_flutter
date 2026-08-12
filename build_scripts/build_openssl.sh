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

# Ensure absolute output path
mkdir -p "$OUTPUT"
OUTPUT=$(realpath "$OUTPUT")

cd third_party/openssl

# Extra flags for specific platforms
EXTRA_FLAGS=""
if [[ "$TARGET" == android-* ]]; then
  EXTRA_FLAGS="-D__ANDROID_API__=24"
elif [[ "$TARGET" == linux-* ]]; then
  EXTRA_FLAGS="-fPIC"
fi

# Clean up before building
if [[ -f Makefile ]]; then
  if [[ "$TARGET" == "VC-WIN64A" ]]; then
    nmake clean || true
  else
    make clean || true
  fi
fi

if [[ "$TARGET" == "VC-WIN64A" ]]; then
  perl Configure $TARGET no-shared no-tests no-apps --prefix="$OUTPUT"
  nmake
  nmake install_sw
else
  ./Configure $TARGET $EXTRA_FLAGS no-shared no-tests no-apps --prefix="$OUTPUT" --openssldir="$OUTPUT/ssl"
  make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu || echo 2)"
  make install_sw
fi
