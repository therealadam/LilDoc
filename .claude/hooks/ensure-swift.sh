#!/bin/bash
#
# SessionStart hook: ensure the Swift toolchain is installed.
# Downloads and installs Swift from swift.org if `swift` is not on PATH.
#

set -euo pipefail

SWIFT_VERSION="6.0.3"
PLATFORM="ubuntu24.04"
PLATFORM_DIR="ubuntu2404"
INSTALL_DIR="/usr/local/swift"

if command -v swift &>/dev/null; then
  echo "Swift is already installed: $(swift --version 2>&1 | head -1)"
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "export PATH=\"${INSTALL_DIR}/usr/bin:\${PATH}\"" >> "$CLAUDE_ENV_FILE"
  fi
  exit 0
fi

echo "Swift not found. Installing Swift ${SWIFT_VERSION} for ${PLATFORM} (x86_64)..."

TARBALL="swift-${SWIFT_VERSION}-RELEASE-${PLATFORM}.tar.gz"
URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/${PLATFORM_DIR}/swift-${SWIFT_VERSION}-RELEASE/${TARBALL}"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

echo "Downloading ${URL}..."
curl -fSL --retry 4 --retry-delay 2 -o "${WORKDIR}/${TARBALL}" "$URL"

echo "Extracting..."
tar xzf "${WORKDIR}/${TARBALL}" -C "$WORKDIR"

EXTRACTED_DIR="${WORKDIR}/swift-${SWIFT_VERSION}-RELEASE-${PLATFORM}"
if [ ! -d "$EXTRACTED_DIR" ]; then
  echo "ERROR: Expected directory ${EXTRACTED_DIR} not found after extraction." >&2
  exit 2
fi

echo "Installing to ${INSTALL_DIR}..."
mv "$EXTRACTED_DIR" "$INSTALL_DIR"

# Make Swift available for the rest of this session
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"${INSTALL_DIR}/usr/bin:\${PATH}\"" >> "$CLAUDE_ENV_FILE"
fi

export PATH="${INSTALL_DIR}/usr/bin:${PATH}"

echo "Swift installed successfully: $(swift --version 2>&1 | head -1)"
