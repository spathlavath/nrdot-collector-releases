#!/bin/bash
# Copyright New Relic, Inc. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Local build script for nrdot-collector
# Builds Linux (deb/rpm) for amd64/arm64 and Windows MSI for amd64
# No goreleaser-pro required — uses golang + nfpm Docker images directly

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "${SCRIPT_DIR}"

BUILD_DIR="${SCRIPT_DIR}/_build"
DIST_DIR="${SCRIPT_DIR}/dist"
PACKAGES_DIR="${SCRIPT_DIR}/packages"
VERSION="1.15.1"
BINARY="nrdot-collector"
# Local fork checkout needed for sqlnormalizer replace directive in go.mod
SQLNORMALIZER_DIR="/Users/spathlavath/otel/logs/opentelemetry-collector-contrib"

echo "======================================"
echo "NRDOT Collector - Local Build"
echo "Version: ${VERSION}"
echo "======================================"

# Ensure _build sources exist
if [ ! -f "${BUILD_DIR}/main.go" ]; then
    echo "ERROR: ${BUILD_DIR}/main.go not found."
    echo "Run 'make generate-sources' from the repo root first."
    exit 1
fi

# Clean previous dist/packages
rm -rf "${DIST_DIR}" "${PACKAGES_DIR}"
mkdir -p "${PACKAGES_DIR}"

# ======================================
# Step 1: Build Linux AMD64
# ======================================
echo ""
echo "==> Building Linux AMD64..."
mkdir -p "${DIST_DIR}/${BINARY}_linux_amd64_v1"

docker run --rm \
    -v "${BUILD_DIR}:/workspace" \
    -v "${DIST_DIR}:/dist" \
    -v "${SQLNORMALIZER_DIR}:${SQLNORMALIZER_DIR}:ro" \
    -w /workspace \
    --platform linux/amd64 \
    golang:1.25-bookworm \
    bash -c "
        set -e
        CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
        go build -trimpath -buildmode=pie -ldflags='-s -w' \
            -o /dist/${BINARY}_linux_amd64_v1/${BINARY} .
        chmod +x /dist/${BINARY}_linux_amd64_v1/${BINARY}
        echo 'Linux AMD64 done'
    "
echo "✅ Linux AMD64: ${DIST_DIR}/${BINARY}_linux_amd64_v1/${BINARY}"

# ======================================
# Step 2: Build Linux ARM64
# ======================================
echo ""
echo "==> Building Linux ARM64..."
mkdir -p "${DIST_DIR}/${BINARY}_linux_arm64_v8.0"

docker run --rm \
    -v "${BUILD_DIR}:/workspace" \
    -v "${DIST_DIR}:/dist" \
    -v "${SQLNORMALIZER_DIR}:${SQLNORMALIZER_DIR}:ro" \
    -w /workspace \
    --platform linux/amd64 \
    golang:1.25-bookworm \
    bash -c "
        set -e
        CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
        go build -trimpath -buildmode=pie -ldflags='-s -w' \
            -o /dist/${BINARY}_linux_arm64_v8.0/${BINARY} .
        chmod +x /dist/${BINARY}_linux_arm64_v8.0/${BINARY}
        echo 'Linux ARM64 done'
    "
echo "✅ Linux ARM64: ${DIST_DIR}/${BINARY}_linux_arm64_v8.0/${BINARY}"

# ======================================
# Step 3: Build Windows AMD64
# ======================================
echo ""
echo "==> Building Windows AMD64..."
mkdir -p "${DIST_DIR}/${BINARY}_windows_amd64_v1"

docker run --rm \
    -v "${BUILD_DIR}:/workspace" \
    -v "${DIST_DIR}:/dist" \
    -v "${SQLNORMALIZER_DIR}:${SQLNORMALIZER_DIR}:ro" \
    -w /workspace \
    --platform linux/amd64 \
    golang:1.25-bookworm \
    bash -c "
        set -e
        CGO_ENABLED=0 GOOS=windows GOARCH=amd64 \
        go build -trimpath -ldflags='-s -w' \
            -o /dist/${BINARY}_windows_amd64_v1/${BINARY}.exe .
        echo 'Windows AMD64 done'
    "
echo "✅ Windows AMD64: ${DIST_DIR}/${BINARY}_windows_amd64_v1/${BINARY}.exe"

# ======================================
# Step 4: Package Linux AMD64 (deb + rpm)
# ======================================
echo ""
echo "==> Packaging Linux AMD64 (deb + rpm)..."

docker run --rm \
    -v "${SCRIPT_DIR}:/workspace" \
    -w /workspace \
    goreleaser/nfpm:latest \
    package --config nfpm-amd64.yaml --packager deb --target /workspace/packages

docker run --rm \
    -v "${SCRIPT_DIR}:/workspace" \
    -w /workspace \
    goreleaser/nfpm:latest \
    package --config nfpm-amd64.yaml --packager rpm --target /workspace/packages

echo "✅ Linux AMD64 deb + rpm created"

# ======================================
# Step 5: Package Linux ARM64 (deb + rpm)
# ======================================
echo ""
echo "==> Packaging Linux ARM64 (deb + rpm)..."

docker run --rm \
    -v "${SCRIPT_DIR}:/workspace" \
    -w /workspace \
    goreleaser/nfpm:latest \
    package --config nfpm-arm64.yaml --packager deb --target /workspace/packages

docker run --rm \
    -v "${SCRIPT_DIR}:/workspace" \
    -w /workspace \
    goreleaser/nfpm:latest \
    package --config nfpm-arm64.yaml --packager rpm --target /workspace/packages

echo "✅ Linux ARM64 deb + rpm created"

# ======================================
# Step 6: Build Windows MSI
# ======================================
echo ""
echo "==> Building Windows MSI..."

WINDOWS_EXE="${DIST_DIR}/${BINARY}_windows_amd64_v1/${BINARY}.exe"
MSI_BUILD_DIR="${SCRIPT_DIR}/_msi_build"
rm -rf "${MSI_BUILD_DIR}"
mkdir -p "${MSI_BUILD_DIR}"

# Copy files needed by wixl into a flat build dir
cp "${WINDOWS_EXE}" "${MSI_BUILD_DIR}/${BINARY}.exe"
cp "${SCRIPT_DIR}/config.yaml" "${MSI_BUILD_DIR}/config.yaml"
cp "${SCRIPT_DIR}/windows/installer-local.wxs" "${MSI_BUILD_DIR}/installer.wxs"

docker run --rm \
    -v "${MSI_BUILD_DIR}:/msi" \
    -v "${PACKAGES_DIR}:/output" \
    -w /msi \
    --platform linux/amd64 \
    ubuntu:22.04 \
    bash -c "
        set -e
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq && apt-get install -y -qq msitools > /dev/null 2>&1
        wixl -o /output/${BINARY}_${VERSION}_windows_amd64.msi installer.wxs
        echo 'MSI done'
    "

rm -rf "${MSI_BUILD_DIR}"
echo "✅ Windows MSI: ${PACKAGES_DIR}/${BINARY}_${VERSION}_windows_amd64.msi"

# ======================================
# Summary
# ======================================
echo ""
echo "======================================"
echo "Build Complete!"
echo "======================================"
ls -lh "${PACKAGES_DIR}/"
