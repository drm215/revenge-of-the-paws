#!/usr/bin/env bash
# Builds a slim Godot web export template for this game: only the engine parts it uses (2D, GUI,
# GDScript, fonts, PNG/WebP images, HTTP and the browser bridge). No 3D, physics, navigation, XR,
# video, Ogg/MP3, networking modules or the ICU text shaper. tools/deploy_web.sh uses the result
# when it's there, and the official template when it isn't.
#
# Needs: the Godot source at the editor's version (GODOT_SRC, default C:/dev/godot-src, tag
# <version>-stable), Emscripten at the version Godot's CI uses (EMSDK, default C:/dev/emsdk) and
# SCons (python -m pip install scons). Rebuild after every Godot upgrade.
#
# If the game starts using something left out here (a 3D node, RegEx, Ogg music...), it will fail
# on the web only: add the module below and rebuild.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_SRC="${GODOT_SRC:-/c/dev/godot-src}"
EMSDK="${EMSDK:-/c/dev/emsdk}"
OUT="$ROOT/build/web_template"

# emsdk runs "python3", which on Windows may be only the Microsoft Store stub.
EMSDK_PYTHON="${EMSDK_PYTHON:-$(command -v python)}"
export EMSDK_PYTHON
# shellcheck disable=SC1091
source "$EMSDK/emsdk_env.sh" >/dev/null
command -v emcc >/dev/null || { echo "emcc not found: is Emscripten installed in $EMSDK?"; exit 1; }
cd "$GODOT_SRC"
python -m SCons platform=web target=template_release threads=no \
	production=yes optimize=size lto=full \
	disable_3d=yes disable_physics_2d=yes disable_navigation_2d=yes \
	vulkan=no accesskit=no sdl=no \
	modules_enabled_by_default=no \
	module_gdscript_enabled=yes \
	module_freetype_enabled=yes \
	module_text_server_fb_enabled=yes \
	module_mbedtls_enabled=yes \
	module_webp_enabled=yes \
	module_svg_enabled=yes \
	-j"$(nproc)"

mkdir -p "$OUT"
cp bin/godot.web.template_release.wasm32.nothreads.zip "$OUT/web_nothreads_release.zip"
echo "Built $OUT/web_nothreads_release.zip"
