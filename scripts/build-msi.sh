#!/bin/bash
# Copyright New Relic, Inc. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Build a Windows MSI for nrdot-collector using msitools/wixl inside an Ubuntu container.
# Assumes the windows binary has already been compiled into dist/nrdot-collector_windows_amd64_v1/nrdot-collector.exe.

set -euo pipefail

REPO_DIR="$( cd "$(dirname "$( dirname "${BASH_SOURCE[0]}" )")" &> /dev/null && pwd )"
DIST_NAME="${DIST_NAME:-nrdot-collector}"
DIST_DIR="${REPO_DIR}/distributions/${DIST_NAME}"
VERSION="${VERSION:-$(${REPO_DIR}/scripts/get-version.sh 2>/dev/null || echo 0.0.0-local)}"
BINARY_NAME="${BINARY_NAME:-nrdot-collector}"
BUILD_DIR="${DIST_DIR}/dist"

WIN_EXE="${BUILD_DIR}/${BINARY_NAME}_windows_amd64_v1/${BINARY_NAME}.exe"
WXS_TEMPLATE="${DIST_DIR}/windows/installer.wxs"
CONFIG_FILE="${DIST_DIR}/config.yaml"

OUTPUT_MSI="${BUILD_DIR}/${BINARY_NAME}_${VERSION}_windows_amd64.msi"

echo "================================================================"
echo "  Building Windows MSI for ${DIST_NAME} v${VERSION}"
echo "================================================================"

for f in "${WIN_EXE}" "${WXS_TEMPLATE}" "${CONFIG_FILE}"; do
    if [ ! -f "${f}" ]; then
        echo "ERROR: required file not found: ${f}"
        exit 1
    fi
done

# Substitute Go-template variables in installer.wxs.
# Goreleaser passes .Binary and .Version; we mirror that here with sed.
TMP_DIR="$(mktemp -d -t build-msi.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

BINARY_UNDERSCORE="${BINARY_NAME//-/_}"
WXS_OUT="${TMP_DIR}/installer.wxs"

sed \
    -e "s/{{ \.Version }}/${VERSION}/g" \
    -e "s/{{ \.Binary }}/${BINARY_NAME}/g" \
    -e "s/{{ replace \.Binary \"-\" \"_\"}}/${BINARY_UNDERSCORE}/g" \
    "${WXS_TEMPLATE}" > "${WXS_OUT}"

# Stage files into a flat layout that the installer.wxs Source paths can resolve.
# The project's installer.wxs uses relative paths like Source="config.yaml" and Source="${BINARY_NAME}.exe".
cp "${WIN_EXE}" "${TMP_DIR}/${BINARY_NAME}.exe"
cp "${CONFIG_FILE}" "${TMP_DIR}/config.yaml"

echo ""
echo "Staging directory: ${TMP_DIR}"
ls -lh "${TMP_DIR}"

echo ""
echo "Running wixl in Ubuntu container..."
docker run --rm \
    -v "${TMP_DIR}:/work" \
    -w /work \
    --platform linux/amd64 \
    ubuntu:22.04 \
    bash -c "
        set -e
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq msitools wixl >/dev/null 2>&1
        wixl --arch x64 -o /work/output.msi /work/installer.wxs
    "

mkdir -p "$(dirname "${OUTPUT_MSI}")"
cp "${TMP_DIR}/output.msi" "${OUTPUT_MSI}"

echo ""
echo "================================================================"
echo "  ✅ MSI built successfully"
echo "================================================================"
ls -lh "${OUTPUT_MSI}"
echo ""
echo "SHA256:"
shasum -a 256 "${OUTPUT_MSI}"
