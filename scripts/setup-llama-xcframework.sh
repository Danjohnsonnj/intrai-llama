#!/usr/bin/env bash
set -euo pipefail

LLAMA_CPP_DIR="${HOME}/Local Documents/repos/llama.cpp"
DEST_DIR="$(cd "$(dirname "$0")/.." && pwd)/vendor/llama"
DEST_XCFRAMEWORK="${DEST_DIR}/llama.xcframework"

if [ ! -d "${LLAMA_CPP_DIR}" ]; then
  echo "Missing llama.cpp at: ${LLAMA_CPP_DIR}"
  exit 1
fi

echo "Building llama.xcframework from ${LLAMA_CPP_DIR}"
cd "${LLAMA_CPP_DIR}"
./build-xcframework.sh

if [ ! -d "${LLAMA_CPP_DIR}/build-apple/llama.xcframework" ]; then
  echo "Expected artifact not found: ${LLAMA_CPP_DIR}/build-apple/llama.xcframework"
  exit 1
fi

mkdir -p "${DEST_DIR}"
rm -rf "${DEST_XCFRAMEWORK}"
cp -R "${LLAMA_CPP_DIR}/build-apple/llama.xcframework" "${DEST_XCFRAMEWORK}"

echo "Copied XCFramework to ${DEST_XCFRAMEWORK}"
echo "Next: add ${DEST_XCFRAMEWORK} to your Xcode target frameworks."
