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
# PulseView requires glibmm-2.4 / sigc++-2.0 (not Homebrew's default glibmm 2.88)
brew install \
    cmake ninja pkg-config \
    glib glibmm@2.66 libsigc++@2 libusb hidapi libzip \
    boost qt@5 python@3.12

QT_PREFIX="$(brew --prefix qt@5)"
PYTHON_PREFIX="$(brew --prefix python@3.12)"
GLIBMM_PREFIX="$(brew --prefix glibmm@2.66)"
SIGC_PREFIX="$(brew --prefix libsigc++@2)"
GLIB_PREFIX="$(brew --prefix glib)"

export PKG_CONFIG_PATH="$GLIBMM_PREFIX/lib/pkgconfig:$SIGC_PREFIX/lib/pkgconfig:$GLIB_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH}"
if ! pkg-config --exists 'glibmm-2.4 >= 2.32.0'; then
    echo "[error] glibmm-2.4 not found after install"
    echo "PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
    pkg-config --list-all | grep -i glib || true
    exit 1
fi

cat <<EOF

============================================
 Environment setup complete!
============================================

Then build (./build.sh sets Homebrew pkg-config paths automatically):

  ./build.sh --package
  open dist/LogicAnalyzer/LogicAnalyzer.app
EOF
