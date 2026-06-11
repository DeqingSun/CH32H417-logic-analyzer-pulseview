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
        PYTHON_PREFIX="$(brew --prefix python@3.12 2>/dev/null || brew --prefix python3 2>/dev/null || true)"
        if [ -n "$QT_PREFIX" ]; then
            export PATH="$QT_PREFIX/bin:$PATH"
        fi
        if [ -n "$PYTHON_PREFIX" ] && [ -d "$PYTHON_PREFIX/Frameworks/Python.framework/Versions" ]; then
            PYVER="$(ls "$PYTHON_PREFIX/Frameworks/Python.framework/Versions" | grep -E '^[0-9]' | head -1)"
            export PKG_CONFIG_PATH="$PYTHON_PREFIX/Frameworks/Python.framework/Versions/$PYVER/lib/pkgconfig:${PKG_CONFIG_PATH}"
        fi
        for formula in qt@5 boost python@3.12 glib glibmm@2.66 libsigc++@2 libusb hidapi libzip; do
            p="$(brew --prefix "$formula" 2>/dev/null || true)"
            [ -z "$p" ] && continue
            export CMAKE_PREFIX_PATH="${p}${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
            [ -d "$p/lib" ] && export LDFLAGS="-L$p/lib ${LDFLAGS}"
            [ -d "$p/include" ] && export CPPFLAGS="-I$p/include ${CPPFLAGS}"
            [ -d "$p/lib/pkgconfig" ] && export PKG_CONFIG_PATH="$p/lib/pkgconfig:${PKG_CONFIG_PATH}"
        done
        if ! pkg-config --exists 'glibmm-2.4 >= 2.32.0'; then
            echo "[error] glibmm-2.4 not found. Install: brew install glibmm@2.66 libsigc++@2"
            echo "PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
            exit 1
        fi
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
        FRAMEWORKS_DIR="$APP/Contents/Frameworks"
        MAIN_BIN="$MACOS_DIR/LogicAnalyzer"
        mkdir -p "$MACOS_DIR" "$RES_DIR" "$FRAMEWORKS_DIR"

        # install_name_tool invalidates code signatures; always re-sign Mach-O files after.
        MACOS_BUNDLE_VISITED="$(mktemp)"
        macos_is_macho() {
            file "$1" 2>/dev/null | grep -q 'Mach-O'
        }
        macos_should_bundle_dep() {
            local dep="$1"
            case "$dep" in
                @executable_path/*|@loader_path/*|@rpath/*) return 1 ;;
                /usr/lib/*|/System/Library/*) return 1 ;;
            esac
            [[ "$dep" == "$APP/Contents/"* ]] && return 1
            return 0
        }
        macos_bundle_framework() {
            local dep="$1"
            local fw_root fw_name fw_dest rel_path inner
            fw_root="${dep%%.framework/*}.framework"
            [ -d "$fw_root" ] || return 0
            grep -qxF "$fw_root" "$MACOS_BUNDLE_VISITED" 2>/dev/null && return 0
            echo "$fw_root" >> "$MACOS_BUNDLE_VISITED"

            fw_name="$(basename "$fw_root" .framework)"
            fw_dest="$FRAMEWORKS_DIR/$fw_name.framework"
            rm -rf "$fw_dest"
            cp -R "$fw_root" "$fw_dest"
            echo "    $fw_name.framework"
            rel_path="${dep#*${fw_name}.framework}"
            for inner in \
                "$fw_dest/Versions/5/$fw_name" \
                "$fw_dest/Versions/A/$fw_name" \
                "$fw_dest/Versions/Current/$fw_name"; do
                if [ -f "$inner" ]; then
                    install_name_tool -change "$dep" \
                        "@executable_path/../Frameworks/$fw_name.framework$rel_path" \
                        "$2" 2>/dev/null || true
                    macos_fixup_binary "$inner"
                    break
                fi
            done
        }
        macos_bundle_dylib() {
            local dep="$1"
            local binary="$2"
            macos_should_bundle_dep "$dep" || return 0
            [ -f "$dep" ] || return 0
            grep -qxF "$dep" "$MACOS_BUNDLE_VISITED" 2>/dev/null && return 0
            echo "$dep" >> "$MACOS_BUNDLE_VISITED"

            local base dest new_path
            base="$(basename "$dep")"
            dest="$FRAMEWORKS_DIR/$base"
            cp -f "$dep" "$dest"
            chmod 755 "$dest"
            install_name_tool -id "@loader_path/$base" "$dest" 2>/dev/null || true
            echo "    $base"
            if [[ "$binary" == "$MAIN_BIN" ]]; then
                new_path="@executable_path/../Frameworks/$base"
            else
                new_path="@loader_path/$base"
            fi
            install_name_tool -change "$dep" "$new_path" "$binary" 2>/dev/null || true
            macos_fixup_binary "$dest"
        }
        macos_fixup_binary() {
            local binary="$1"
            local dep
            macos_is_macho "$binary" || return 0
            while read -r dep; do
                [ -n "$dep" ] || continue
                macos_should_bundle_dep "$dep" || continue
                [ -f "$dep" ] || continue
                if [[ "$dep" == *".framework/"* ]]; then
                    macos_bundle_framework "$dep" "$binary"
                else
                    macos_bundle_dylib "$dep" "$binary"
                fi
            done < <(otool -L "$binary" 2>/dev/null | tail -n +2 | awk '{print $1}')
        }
        macos_has_external_deps() {
            local f dep
            for f in "$@"; do
                [ -f "$f" ] || continue
                while read -r dep; do
                    macos_should_bundle_dep "$dep" || continue
                    [ -f "$dep" ] && return 0
                done < <(otool -L "$f" 2>/dev/null | tail -n +2 | awk '{print $1}')
            done
            return 1
        }
        macos_bundle_all_deps() {
            local round=0
            while [ "$round" -lt 25 ]; do
                round=$((round + 1))
                : > "$MACOS_BUNDLE_VISITED"
                macos_fixup_binary "$MAIN_BIN"
                for lib in "$FRAMEWORKS_DIR"/*.dylib; do
                    [ -f "$lib" ] || continue
                    macos_fixup_binary "$lib"
                done
                for fw in "$FRAMEWORKS_DIR"/*.framework; do
                    [ -d "$fw" ] || continue
                    local fwname inner
                    fwname="$(basename "$fw" .framework)"
                    for inner in "$fw/Versions/"*"/$fwname"; do
                        [ -f "$inner" ] && macos_fixup_binary "$inner"
                    done
                done
                macos_has_external_deps "$MAIN_BIN" "$FRAMEWORKS_DIR"/*.dylib || break
            done
        }
        macos_sign_file() {
            codesign --force --sign - --timestamp=none "$1" || {
                echo "[error] codesign failed: $1"
                exit 1
            }
        }
        macos_sign_app() {
            local app="$1" f fw fwname inner
            echo "  Ad-hoc signing app bundle (inner libraries first)..."
            for f in "$app/Contents/Frameworks"/*.dylib; do
                [ -f "$f" ] && macos_sign_file "$f"
            done
            for fw in "$app/Contents/Frameworks"/*.framework; do
                [ -d "$fw" ] || continue
                fwname="$(basename "$fw" .framework)"
                for inner in \
                    "$fw/Versions/5/$fwname" \
                    "$fw/Versions/A/$fwname" \
                    "$fw/Versions/Current/$fwname"; do
                    if [ -f "$inner" ]; then
                        macos_sign_file "$inner"
                        break
                    fi
                done
                macos_sign_file "$fw"
            done
            while IFS= read -r -d '' f; do
                macos_sign_file "$f"
            done < <(find "$app/Contents/PlugIns" -name '*.dylib' -type f -print0 2>/dev/null)
            macos_sign_file "$MAIN_BIN"
            macos_sign_file "$app"
            codesign --verify --deep --strict "$app" || {
                echo "[error] codesign verification failed"
                exit 1
            }
            echo "  codesign verification OK"
        }

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

        cp "$BUILD_DIR/logicanalyzer_build/LogicAnalyzer" "$MAIN_BIN"
        chmod +x "$MAIN_BIN"
        echo "  LogicAnalyzer.app/Contents/MacOS/LogicAnalyzer"

        MACDEPLOYQT=""
        if command -v macdeployqt &>/dev/null; then
            MACDEPLOYQT="$(command -v macdeployqt)"
        elif [ -n "${QT_PREFIX:-}" ] && [ -x "$QT_PREFIX/bin/macdeployqt" ]; then
            MACDEPLOYQT="$QT_PREFIX/bin/macdeployqt"
        fi
        if [ -n "$MACDEPLOYQT" ]; then
            echo "  Running macdeployqt..."
            "$MACDEPLOYQT" "$APP" -always-overwrite -codesign=-
        else
            echo "  (macdeployqt not found, Qt frameworks must be installed separately)"
        fi

        echo "  Bundling non-Qt libraries into Contents/Frameworks..."
        macos_bundle_all_deps
        rm -f "$MACOS_BUNDLE_VISITED"

        DECODERS_SRC="$PREFIX/share/libsigrokdecode/decoders"
        if [ -d "$DECODERS_SRC" ]; then
            echo "  Protocol decoders..."
            cp -r "$DECODERS_SRC" "$RES_DIR/decoders"
            echo "    $(ls "$RES_DIR/decoders" | wc -l) decoders"
        fi

        macos_sign_app "$APP"

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

