#!/usr/bin/env bash
set -euo pipefail

LLAMA_CPP_DIR="${HOME}/Local Documents/repos/llama.cpp"
DEST_DIR="$(cd "$(dirname "$0")/.." && pwd)/vendor/llama"
DEST_XCFRAMEWORK="${DEST_DIR}/llama.xcframework"
IOS_MIN_OS_VERSION=26.4

BUILD_IOS_SIM_DIR="${LLAMA_CPP_DIR}/build-ios-sim"
BUILD_IOS_DEVICE_DIR="${LLAMA_CPP_DIR}/build-ios-device"
BUILD_ARTIFACT_DIR="${LLAMA_CPP_DIR}/build-apple-ios"
HEADERS_DIR="${BUILD_ARTIFACT_DIR}/Headers"
SIM_COMBINED_LIB="${BUILD_IOS_SIM_DIR}/llama-ios-sim.a"
DEVICE_COMBINED_LIB="${BUILD_IOS_DEVICE_DIR}/llama-ios-device.a"

if [ ! -d "${LLAMA_CPP_DIR}" ]; then
  echo "Missing llama.cpp at: ${LLAMA_CPP_DIR}"
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake is required but not found."
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required but not found."
  exit 1
fi

echo "Building iOS-only llama.xcframework from ${LLAMA_CPP_DIR}"
echo "Target scope: iPhone simulator + iPhone device only (MVP)."

cd "${LLAMA_CPP_DIR}"

rm -rf "${BUILD_IOS_SIM_DIR}" "${BUILD_IOS_DEVICE_DIR}" "${BUILD_ARTIFACT_DIR}"
mkdir -p "${BUILD_ARTIFACT_DIR}" "${HEADERS_DIR}"

COMMON_CMAKE_ARGS=(
  -DBUILD_SHARED_LIBS=OFF
  -DLLAMA_BUILD_EXAMPLES=OFF
  -DLLAMA_BUILD_TOOLS=OFF
  -DLLAMA_BUILD_TESTS=OFF
  -DLLAMA_BUILD_SERVER=OFF
  -DGGML_NATIVE=OFF
  -DGGML_METAL=ON
  -DGGML_METAL_EMBED_LIBRARY=ON
  -DGGML_BLAS_DEFAULT=ON
  -DGGML_OPENMP=OFF
)

echo "Configuring iOS simulator build (arm64 only)..."
cmake -B "${BUILD_IOS_SIM_DIR}" -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES="arm64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${IOS_MIN_OS_VERSION}" \
  "${COMMON_CMAKE_ARGS[@]}"

echo "Building iOS simulator static libraries..."
cmake --build "${BUILD_IOS_SIM_DIR}" --config Release -- -quiet

echo "Configuring iOS device build..."
cmake -B "${BUILD_IOS_DEVICE_DIR}" -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES="arm64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${IOS_MIN_OS_VERSION}" \
  "${COMMON_CMAKE_ARGS[@]}"

echo "Building iOS device static libraries..."
cmake --build "${BUILD_IOS_DEVICE_DIR}" --config Release -- -quiet

combine_static_libs() {
  local build_dir="$1"
  local output_lib="$2"
  local release_dir_name="$3"

  local libs=()
  while IFS= read -r -d '' file; do
    libs+=("$file")
  done < <(find "${build_dir}" -path "*/${release_dir_name}/*.a" -print0)

  if [ "${#libs[@]}" -eq 0 ]; then
    echo "No static libraries found in ${build_dir} for ${release_dir_name}"
    exit 1
  fi

  xcrun libtool -static "${libs[@]}" -o "${output_lib}"
}

echo "Combining iOS simulator libraries..."
combine_static_libs "${BUILD_IOS_SIM_DIR}" "${SIM_COMBINED_LIB}" "Release-iphonesimulator"

echo "Combining iOS device libraries..."
combine_static_libs "${BUILD_IOS_DEVICE_DIR}" "${DEVICE_COMBINED_LIB}" "Release-iphoneos"

echo "Copying headers..."
REQUIRED_HEADERS=(
  "include/llama.h"
  "ggml/include/ggml.h"
  "ggml/include/ggml-alloc.h"
  "ggml/include/ggml-backend.h"
  "ggml/include/ggml-blas.h"
  "ggml/include/ggml-cpu.h"
  "ggml/include/ggml-metal.h"
  "ggml/include/ggml-opt.h"
  "ggml/include/gguf.h"
)

for header in "${REQUIRED_HEADERS[@]}"; do
  if [ -f "${header}" ]; then
    cp "${header}" "${HEADERS_DIR}/"
  else
    echo "Warning: expected header not found: ${header} (upstream layout may have changed)"
  fi
done

echo "Generating module map for Swift import..."
cat > "${HEADERS_DIR}/module.modulemap" << 'MODULEMAP'
module llama {
    header "llama.h"
    header "ggml.h"
    header "ggml-alloc.h"
    header "ggml-backend.h"
    header "ggml-metal.h"
    header "ggml-cpu.h"
    header "ggml-blas.h"
    header "gguf.h"

    link "c++"
    link framework "Accelerate"
    link framework "Metal"
    link framework "Foundation"

    export *
}
MODULEMAP

echo "Creating iOS-only XCFramework artifact..."
xcrun xcodebuild -create-xcframework \
  -library "${DEVICE_COMBINED_LIB}" -headers "${HEADERS_DIR}" \
  -library "${SIM_COMBINED_LIB}" -headers "${HEADERS_DIR}" \
  -output "${BUILD_ARTIFACT_DIR}/llama.xcframework"

if [ ! -d "${BUILD_ARTIFACT_DIR}/llama.xcframework" ]; then
  echo "Expected artifact not found: ${BUILD_ARTIFACT_DIR}/llama.xcframework"
  exit 1
fi

mkdir -p "${DEST_DIR}"
rm -rf "${DEST_XCFRAMEWORK}"
cp -R "${BUILD_ARTIFACT_DIR}/llama.xcframework" "${DEST_XCFRAMEWORK}"

echo "Copied XCFramework to ${DEST_XCFRAMEWORK}"
echo "Next: add ${DEST_XCFRAMEWORK} to your iOS app target frameworks."
