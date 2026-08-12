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
  if [[ "$TARGET" == "linux-aarch64" ]]; then
    export CC=aarch64-linux-gnu-gcc
    export CXX=aarch64-linux-gnu-g++
  fi
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
  PERL_CMD="perl"
  if [[ -f "/c/Strawberry/perl/bin/perl.exe" ]]; then
    PERL_CMD="/c/Strawberry/perl/bin/perl.exe"
  elif [[ -f "C:/Strawberry/perl/bin/perl.exe" ]]; then
    PERL_CMD="C:/Strawberry/perl/bin/perl.exe"
  elif command -v perl.exe >/dev/null 2>&1; then
    PERL_CMD="perl.exe"
  fi
  "$PERL_CMD" Configure $TARGET no-shared no-module no-tests no-apps --prefix="$OUTPUT"
  nmake
  nmake install_sw
else
  ./Configure $TARGET $EXTRA_FLAGS no-shared no-module no-tests no-apps --prefix="$OUTPUT" --openssldir="$OUTPUT/ssl"
  make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu || echo 2)"
  make install_sw
fi
