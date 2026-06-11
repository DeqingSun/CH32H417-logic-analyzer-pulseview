#!/bin/bash
# ============================================================================
# setup_env_macos.sh - CH32H417 LogicAnalyzer macOS build environment
# Requires Homebrew: https://brew.sh
# ============================================================================
set -e

if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "[error] This script is for macOS only"
    exit 1
fi

if ! command -v brew &>/dev/null; then
    echo "[error] Homebrew is required. Install from https://brew.sh"
    exit 1
fi

echo ">>> Installing build dependencies via Homebrew..."

brew update
brew install \
    cmake ninja pkg-config \
    glib glibmm libsigc++ libusb hidapi libzip \
    boost qt@5 python@3.12

QT_PREFIX="$(brew --prefix qt@5)"
PYTHON_PREFIX="$(brew --prefix python@3.12)"

cat <<EOF

============================================
 Environment setup complete!
============================================

Then build (./build.sh sets Homebrew pkg-config paths automatically):

  ./build.sh --package
  open dist/LogicAnalyzer/LogicAnalyzer.app
EOF
