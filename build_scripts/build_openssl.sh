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

echo "TODO phase 3+ - Target: $TARGET, Output: $OUTPUT"
