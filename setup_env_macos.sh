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
    glib glibmm libusb hidapi libzip \
    boost qt@5 python@3.12

QT_PREFIX="$(brew --prefix qt@5)"
PYTHON_PREFIX="$(brew --prefix python@3.12)"

cat <<EOF

============================================
 Environment setup complete!
============================================

Add to your shell before building (or run ./build.sh directly):

  export PATH="$QT_PREFIX/bin:\$PATH"
  export PKG_CONFIG_PATH="$QT_PREFIX/lib/pkgconfig:\$PKG_CONFIG_PATH"
  export PKG_CONFIG_PATH="$PYTHON_PREFIX/Frameworks/Python.framework/Versions/3.12/lib/pkgconfig:\$PKG_CONFIG_PATH"
  export CMAKE_PREFIX_PATH="$QT_PREFIX:$(brew --prefix boost)"

Then:

  ./build.sh --package
  open dist/LogicAnalyzer/LogicAnalyzer.app
EOF
