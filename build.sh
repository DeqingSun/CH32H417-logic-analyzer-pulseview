#!/bin/bash
# ============================================================================
# build.sh - CH32H417 LogicAnalyzer Build + Package
# Usage:
#   ./build.sh              # Build only
#   ./build.sh --package    # Build + create dist/LogicAnalyzer/ package
#   ./build.sh --clean      # Clean build
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build_cmake"
PREFIX="${SCRIPT_DIR}/install"
DIST_DIR="${SCRIPT_DIR}/dist/LogicAnalyzer"
CLEAN=0
PACKAGE=0
IS_WINDOWS=0
IS_MACOS=0

# Platform detection
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$MSYSTEM" ]]; then
    IS_WINDOWS=1
    export PATH="/mingw64/bin:/usr/bin:$PATH"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    IS_MACOS=1
    if command -v brew &>/dev/null; then
        QT_PREFIX="$(brew --prefix qt@5 2>/dev/null || brew --prefix qt 2>/dev/null || true)"
        BOOST_PREFIX="$(brew --prefix boost 2>/dev/null || true)"
        PYTHON_PREFIX="$(brew --prefix python@3.12 2>/dev/null || brew --prefix python3 2>/dev/null || true)"
        if [ -n "$QT_PREFIX" ]; then
            export PATH="$QT_PREFIX/bin:$PATH"
            export PKG_CONFIG_PATH="$QT_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH}"
        fi
        if [ -n "$PYTHON_PREFIX" ] && [ -d "$PYTHON_PREFIX/Frameworks/Python.framework/Versions" ]; then
            PYVER="$(ls "$PYTHON_PREFIX/Frameworks/Python.framework/Versions" | grep -E '^[0-9]' | head -1)"
            export PKG_CONFIG_PATH="$PYTHON_PREFIX/Frameworks/Python.framework/Versions/$PYVER/lib/pkgconfig:${PKG_CONFIG_PATH}"
        fi
        for p in "$QT_PREFIX" "$BOOST_PREFIX"; do
            [ -n "$p" ] && export CMAKE_PREFIX_PATH="${p}${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
        done
    fi
fi

JOBS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

for arg in "$@"; do
    case $arg in
        --clean) CLEAN=1 ;;
        --package) PACKAGE=1 ;;
        --prefix) PREFIX="$2"; shift ;;
    esac
    shift 2>/dev/null || true
done

echo "============================================"
echo " CH32H417 LogicAnalyzer Build"
echo "============================================"
echo "Source:  $SCRIPT_DIR"
echo "Build:   $BUILD_DIR"
echo "Install: $PREFIX"
[ $PACKAGE -eq 1 ] && echo "Package: $DIST_DIR"
echo ""

if [ $CLEAN -eq 1 ]; then
    echo "[CLEAN] Removing build directory..."
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# MinGW detection
MINGW_EXTRA=""
if [ $IS_WINDOWS -eq 1 ]; then
    echo "Detected Windows/MinGW build environment"
    MINGW_EXTRA="-DWIN32=ON"
elif [ $IS_MACOS -eq 1 ]; then
    echo "Detected macOS build environment"
fi

# ============================================================================
# Step 1: libsigrok (CH32H417 + Demo)
# ============================================================================
echo ""
echo "===== Step 1/4: libsigrok (CH32H417 + Demo) ====="

mkdir -p libsigrok_build && cd libsigrok_build
cmake "${SCRIPT_DIR}/libsigrok" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DDISABLE_WERROR=ON $MINGW_EXTRA
cmake --build . -j"$JOBS"
cmake --install .
echo "[OK] libsigrok"

# ============================================================================
# Step 2: libsigrokcxx (C++ bindings)
# ============================================================================
echo ""
echo "===== Step 2/4: libsigrokcxx ====="

cd "$BUILD_DIR" && mkdir -p libsigrokcxx_build && cd libsigrokcxx_build
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH}"
cmake "${SCRIPT_DIR}/libsigrok/bindings/cxx" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$PREFIX" $MINGW_EXTRA
cmake --build . -j"$JOBS"
cmake --install .
echo "[OK] libsigrokcxx"

# ============================================================================
# Step 3: libsigrokdecode
# ============================================================================
echo ""
echo "===== Step 3/4: libsigrokdecode ====="

cd "$BUILD_DIR" && mkdir -p libsigrokdecode_build && cd libsigrokdecode_build
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH}"
cmake "${SCRIPT_DIR}/libsigrokdecode" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DDISABLE_WERROR=ON $MINGW_EXTRA
cmake --build . -j"$JOBS"
cmake --install .
echo "[OK] libsigrokdecode"

# ============================================================================
# Step 4: LogicAnalyzer
# ============================================================================
echo ""
echo "===== Step 4/4: LogicAnalyzer ====="

# Generate .qm translation files from .ts sources
if ls "${SCRIPT_DIR}/pulseview/l10n/"*.ts >/dev/null 2>&1; then
    echo "  Generating translations..."
    if [ $IS_WINDOWS -eq 1 ]; then
        export PATH="/mingw64/qt5-static/bin:$PATH"
    fi
    for ts in "${SCRIPT_DIR}/pulseview/l10n/"*.ts; do
        [ -f "$ts" ] && lrelease "$ts" -qm "${ts%.ts}.qm" 2>/dev/null || true
    done
    echo "  [OK] Translations generated"
fi

cd "$BUILD_DIR" && mkdir -p logicanalyzer_build && cd logicanalyzer_build
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH}"
cmake "${SCRIPT_DIR}/pulseview" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DSTATIC_PKGDEPS_LIBS=OFF \
    -DENABLE_DECODE=ON \
    -DENABLE_FLOW=OFF \
    -DENABLE_TESTS=OFF \
    -DENABLE_SIGNALS=OFF \
    -DDISABLE_WERROR=ON $MINGW_EXTRA
cmake --build . -j"$JOBS"

PVDIR="$BUILD_DIR/logicanalyzer_build"
PV_BIN="$PVDIR/LogicAnalyzer"
[ $IS_WINDOWS -eq 1 ] && PV_BIN="$PVDIR/LogicAnalyzer.exe"

if [ $IS_WINDOWS -eq 1 ]; then
    # Deploy DLLs and create run.bat in build dir
    echo ""
    echo "  Deploying DLLs..."
    for dll in libsigrok.dll libsigrokcxx.dll libsigrokdecode.dll; do
        cp "$PREFIX/bin/$dll" "$PVDIR/" 2>/dev/null || true
        cp "$BUILD_DIR/libsigrok_build/$dll" "$PVDIR/" 2>/dev/null || true
        cp "$BUILD_DIR/libsigrokdecode_build/$dll" "$PVDIR/" 2>/dev/null || true
    done
    for dll in libglib-2.0-0.dll libglibmm-2.4-1.dll libgobject-2.0-0.dll \
        libsigc-2.0-0.dll libstdc++-6.dll libwinpthread-1.dll \
        libgcc_s_seh-1.dll libgmodule-2.0-0.dll libusb-1.0.dll libhidapi-0.dll \
        libintl-8.dll libiconv-2.dll libpcre2-8-0.dll libffi-8.dll \
        libzip.dll libbz2-1.dll liblzma-5.dll zlib1.dll libzstd.dll libpython3.14.dll; do
        cp "/mingw64/bin/$dll" "$PVDIR/" 2>/dev/null || true
    done

    cat > "$PVDIR/run.bat" << 'RBEOF'
@echo off
cd /d "%~dp0"
set "PATH=%~dp0;%PATH%"
set "PYTHONHOME=%~dp0python-portable"
set "SIGROKDECODE_DIR=%~dp0decoders"
if exist "..\..\install\share\libsigrokdecode\decoders" (
    set "SIGROKDECODE_DIR=..\..\install\share\libsigrokdecode\decoders"
    set "PYTHONHOME="
)
start "" "LogicAnalyzer.exe"
RBEOF

    echo "  $(ls "$PVDIR"/*.dll 2>/dev/null | wc -l) DLLs, run.bat created"
    echo "  Stripping debug symbols..."
    strip "$PVDIR/LogicAnalyzer.exe" 2>/dev/null || echo "  (strip not available, skipping)"
    echo "  $(du -sh "$PVDIR/LogicAnalyzer.exe" | cut -f1) after strip"
fi

echo ""
echo "===== BUILD COMPLETE ====="
echo "  LogicAnalyzer: $PV_BIN"
echo ""

# ============================================================================
# Package: create self-contained distribution
# ============================================================================
if [ $PACKAGE -eq 1 ]; then
    echo "===== Packaging to $DIST_DIR ====="
    rm -rf "$DIST_DIR"
    mkdir -p "$DIST_DIR"

    if [ $IS_WINDOWS -eq 1 ]; then
        cp "$BUILD_DIR/logicanalyzer_build/LogicAnalyzer.exe" "$DIST_DIR/"
        echo "  LogicAnalyzer.exe"

        for dll in libsigrok.dll libsigrokcxx.dll libsigrokdecode.dll; do
            cp "$PREFIX/bin/$dll" "$DIST_DIR/" 2>/dev/null || \
            cp "$BUILD_DIR/libsigrok_build/$dll" "$DIST_DIR/" 2>/dev/null || \
            cp "$BUILD_DIR/libsigrokdecode_build/$dll" "$DIST_DIR/" 2>/dev/null || true
            [ -f "$DIST_DIR/$dll" ] && echo "  $dll"
        done

        echo "  System DLLs..."
        for dll in \
            libglib-2.0-0.dll libglibmm-2.4-1.dll libgobject-2.0-0.dll \
            libsigc-2.0-0.dll libstdc++-6.dll libwinpthread-1.dll \
            libgcc_s_seh-1.dll libgmodule-2.0-0.dll \
            libusb-1.0.dll libhidapi-0.dll \
            libintl-8.dll libiconv-2.dll libpcre2-8-0.dll libffi-8.dll \
            libzip.dll libbz2-1.dll liblzma-5.dll \
            zlib1.dll libzstd.dll libpython3.14.dll; do
            cp "/mingw64/bin/$dll" "$DIST_DIR/" 2>/dev/null || true
        done

        echo "  Python standard library..."
        PYTHON_SRC="/mingw64/lib/python3.14"
        if [ -d "$PYTHON_SRC" ]; then
            mkdir -p "$DIST_DIR/python-portable/lib/python3.14"
            if [ -d "$PYTHON_SRC/lib-dynload" ]; then
                cp -r "$PYTHON_SRC/lib-dynload" "$DIST_DIR/python-portable/lib/python3.14/"
            fi
            for dir in asyncio collections concurrent ctypes distutils email encodings \
                       html http importlib json lib logging multiprocessing \
                       pydoc_data re sqlite3 unittest urllib wsgi xml xmlrpc \
                       _collections_abc.py _compat_pickle.py _py_abc.py \
                       _sitebuiltins.py site.py string.py \
                       abc.py ast.py base64.py bisect.py calendar.py cgi.py \
                       codecs.py copy.py copyreg.py csv.py dataclasses.py \
                       datetime.py decimal.py dis.py enum.py fnmatch.py \
                       functools.py glob.py hashlib.py heapq.py inspect.py io.py \
                       keyword.py linecache.py locale.py math.py operator.py \
                       os.py pathlib.py pickle.py platform.py plistlib.py \
                       pprint.py queue.py random.py reprlib.py selectors.py \
                       shutil.py signal.py socket.py sre_compile.py \
                       sre_constants.py sre_parse.py stat.py string string.py \
                       struct.py subprocess.py sysconfig.py tempfile.py \
                       textwrap.py threading.py token.py tokenize.py \
                       types.py typing.py uuid.py warnings.py weakref.py; do
                cp -r "$PYTHON_SRC/$dir" "$DIST_DIR/python-portable/lib/python3.14/" 2>/dev/null || true
            done
            echo "    $(find "$DIST_DIR/python-portable" -type f | wc -l) files"
        fi

        DECODERS_SRC="$PREFIX/share/libsigrokdecode/decoders"
        if [ -d "$DECODERS_SRC" ]; then
            echo "  Protocol decoders..."
            cp -r "$DECODERS_SRC" "$DIST_DIR/decoders"
            echo "    $(ls "$DIST_DIR/decoders" | wc -l) decoders"
        fi

        cat > "$DIST_DIR/run.bat" << 'EOF'
@echo off
cd /d "%~dp0"
set "PATH=%~dp0;%PATH%"
set "PYTHONHOME=%~dp0python-portable"
set "SIGROKDECODE_DIR=%~dp0decoders"
echo Starting LogicAnalyzer...
LogicAnalyzer.exe
if %ERRORLEVEL% neq 0 (
    echo.
    echo LogicAnalyzer exited with error code %ERRORLEVEL%
    pause
)
EOF
        echo "  run.bat"
        echo ""
        echo "To distribute: copy the entire dist/LogicAnalyzer/ folder."
        echo "To run: double-click run.bat or LogicAnalyzer.exe"

    elif [ $IS_MACOS -eq 1 ]; then
        APP="$DIST_DIR/LogicAnalyzer.app"
        MACOS_DIR="$APP/Contents/MacOS"
        RES_DIR="$APP/Contents/Resources"
        mkdir -p "$MACOS_DIR" "$RES_DIR"

        cp "$BUILD_DIR/logicanalyzer_build/LogicAnalyzer" "$MACOS_DIR/LogicAnalyzer"
        chmod +x "$MACOS_DIR/LogicAnalyzer"
        echo "  LogicAnalyzer.app/Contents/MacOS/LogicAnalyzer"

        echo "  Bundling libsigrok libraries..."
        for dylib in "$PREFIX/lib"/libsigrok*.dylib "$PREFIX/lib"/libsigrokdecode*.dylib; do
            [ -f "$dylib" ] || continue
            cp "$dylib" "$MACOS_DIR/"
            echo "    $(basename "$dylib")"
        done

        install_name_tool -add_rpath @executable_path "$MACOS_DIR/LogicAnalyzer" 2>/dev/null || true
        otool -L "$MACOS_DIR/LogicAnalyzer" | awk '/^\t\// {print $1}' | while read -r old; do
            case "$old" in
                "$PREFIX"/*|/usr/local/*|/opt/homebrew/*)
                    base=$(basename "$old")
                    if [ -f "$MACOS_DIR/$base" ]; then
                        install_name_tool -change "$old" "@executable_path/$base" "$MACOS_DIR/LogicAnalyzer" 2>/dev/null || true
                    fi
                    ;;
            esac
        done
        for dylib in "$MACOS_DIR"/*.dylib; do
            [ -f "$dylib" ] || continue
            install_name_tool -id "@executable_path/$(basename "$dylib")" "$dylib" 2>/dev/null || true
            otool -L "$dylib" | awk '/^\t\// {print $1}' | while read -r old; do
                case "$old" in
                    "$PREFIX"/*)
                        install_name_tool -change "$old" "@executable_path/$(basename "$old")" "$dylib" 2>/dev/null || true
                        ;;
                esac
            done
        done

        cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LogicAnalyzer</string>
    <key>CFBundleIdentifier</key>
    <string>com.q2h2.logicanalyzer</string>
    <key>CFBundleName</key>
    <string>LogicAnalyzer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>0.2</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

        MACDEPLOYQT=""
        if command -v macdeployqt &>/dev/null; then
            MACDEPLOYQT="$(command -v macdeployqt)"
        elif [ -n "${QT_PREFIX:-}" ] && [ -x "$QT_PREFIX/bin/macdeployqt" ]; then
            MACDEPLOYQT="$QT_PREFIX/bin/macdeployqt"
        fi
        if [ -n "$MACDEPLOYQT" ]; then
            echo "  Running macdeployqt..."
            "$MACDEPLOYQT" "$APP" -always-overwrite
        else
            echo "  (macdeployqt not found, Qt frameworks must be installed separately)"
        fi

        DECODERS_SRC="$PREFIX/share/libsigrokdecode/decoders"
        if [ -d "$DECODERS_SRC" ]; then
            echo "  Protocol decoders..."
            cp -r "$DECODERS_SRC" "$RES_DIR/decoders"
            echo "    $(ls "$RES_DIR/decoders" | wc -l) decoders"
        fi

        mv "$MACOS_DIR/LogicAnalyzer" "$MACOS_DIR/LogicAnalyzer.bin"
        cat > "$MACOS_DIR/LogicAnalyzer" << 'WRAPPER'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
export SIGROKDECODE_DIR="$DIR/../Resources/decoders"
exec "$DIR/LogicAnalyzer.bin" "$@"
WRAPPER
        chmod +x "$MACOS_DIR/LogicAnalyzer"

        cat > "$DIST_DIR/run.sh" << 'EOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
open "$DIR/LogicAnalyzer.app"
EOF
        chmod +x "$DIST_DIR/run.sh"
        echo "  run.sh"

        echo ""
        echo "To distribute: copy dist/LogicAnalyzer/ (LogicAnalyzer.app + run.sh)."
        echo "To run: open LogicAnalyzer.app or ./run.sh"
    fi

    echo ""
    echo "===== PACKAGE COMPLETE ====="
    echo "  $DIST_DIR/"
fi

