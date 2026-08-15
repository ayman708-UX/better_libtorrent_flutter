#!/bin/bash
set -euo pipefail

PLATFORM=$1
VERSION="0.0.8"
REPIOS_URL="https://github.com/ayman708-UX/better_libtorrent_flutter/releases/download/v0.0.8/torrent_engine-ios.zip"
MACOS_URL="https://github.com/ayman708-UX/better_libtorrent_flutter/releases/download/v0.0.8/torrent_engine-macos.zip"

if [ "$PLATFORM" == "ios" ]; then
  URL=$REPIOS_URL
else
  URL=$MACOS_URL
fi

ZIP_NAME="torrent_engine-${PLATFORM}.zip"
OUT_DIR="${PLATFORM}"

if [ ! -d "${OUT_DIR}" ]; then
  echo "Downloading ${PLATFORM} binaries from ${URL}..."
  curl -L -s -o "${ZIP_NAME}" "${URL}"
  unzip -q "${ZIP_NAME}" -d "${OUT_DIR}"
  rm "${ZIP_NAME}"
  
  if [ "$PLATFORM" == "ios" ]; then
    # iOS release contains final-ios/TorrentEngine.xcframework
    mv "${OUT_DIR}/final-ios/TorrentEngine.xcframework" "TorrentEngine.xcframework"
  elif [ "$PLATFORM" == "macos" ]; then
    # macOS release contains final-macos/TorrentEngineMac.xcframework
    mv "${OUT_DIR}/final-macos/TorrentEngineMac.xcframework" "TorrentEngineMac.xcframework"
  fi
  rm -rf "${OUT_DIR}"
fi
