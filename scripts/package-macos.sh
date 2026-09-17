#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Minutes"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-macos-arm64.dmg"
ZIP_PATH="$DIST_DIR/$APP_NAME-macos-arm64.zip"
CONFIGURATION="${CONFIGURATION:-release}"
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
BUNDLE_PYTHON="${BUNDLE_PYTHON:-1}"

# Version defaults to the nearest release tag (v0.1.0 -> 0.1.0), then to
# pyproject.toml. Release builds pass the exact tag via APP_VERSION.
derive_version() {
  local tag py
  if tag="$(git -C "$ROOT_DIR" describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null)"; then
    tag="${tag#v}"
    if [[ "$tag" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
      printf '%s' "$tag"
      return
    fi
  fi
  py="$(sed -n 's/^version *= *"\([^"]*\)".*/\1/p' "$ROOT_DIR/pyproject.toml" | head -1)"
  printf '%s' "${py:-0.1.0}"
}

# CFBundleVersion must be an integer and increase with every release.
APP_VERSION="${APP_VERSION:-$(derive_version)}"
APP_BUILD="${APP_BUILD:-1}"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required tool '$1' was not found" >&2
    exit 1
  fi
}

require_tool swift
require_tool codesign
require_tool ditto

if [[ "$BUNDLE_PYTHON" == "1" ]]; then
  require_tool uv
fi

rm -rf "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

echo "==> Building Swift app ($CONFIGURATION)"
pushd "$APP_DIR" >/dev/null
swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
popd >/dev/null

echo "==> Creating app bundle"
cp "$BIN_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
sed -e "s/__APP_VERSION__/$APP_VERSION/g" \
    -e "s/__APP_BUILD__/$APP_BUILD/g" \
  "$APP_DIR/Sources/Minutes/Info.plist" \
  > "$APP_BUNDLE/Contents/Info.plist"
cp "$APP_DIR/Sources/Minutes/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

RESOURCE_BUNDLE="$BIN_DIR/${APP_NAME}_Minutes.bundle"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  RESOURCE_BUNDLE="$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle"
fi

if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "error: SwiftPM resource bundle was not found in $BIN_DIR" >&2
  exit 1
fi

cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"

if [[ "$BUNDLE_PYTHON" == "1" ]]; then
  PYTHON_ENV="$APP_BUNDLE/Contents/Resources/Python"
  PYTHON_RUNTIME="$APP_BUNDLE/Contents/Resources/PythonRuntime"
  REQUIREMENTS_FILE="$DIST_DIR/requirements.txt"

  echo "==> Exporting locked Python dependencies"
  uv export \
    --project "$ROOT_DIR" \
    --frozen \
    --no-dev \
    --no-emit-project \
    --format requirements.txt \
    --output-file "$REQUIREMENTS_FILE" \
    >/dev/null

  # A managed-python venv only symlinks the interpreter, and --relocatable does
  # not make that link relative, so it dangles on every machine except the build
  # host. Install a standalone interpreter *inside* the bundle instead, so the
  # venv resolves to a path that travels with the app.
  echo "==> Bundling standalone Python runtime ($PYTHON_VERSION)"
  UV_PYTHON_INSTALL_DIR="$PYTHON_RUNTIME" uv python install \
    --no-bin \
    "$PYTHON_VERSION"

  # Use the versioned interpreter directory, not uv's `cpython-3.11-...` alias:
  # that alias is an absolute symlink back into the build tree.
  RUNTIME_PYTHON=""
  for candidate in "$PYTHON_RUNTIME"/cpython-*/bin/python"$PYTHON_VERSION"; do
    runtime_dir="$(dirname "$(dirname "$candidate")")"
    [[ -L "$runtime_dir" ]] && continue
    [[ -x "$candidate" ]] && RUNTIME_PYTHON="$candidate" && break
  done

  if [[ -z "$RUNTIME_PYTHON" ]]; then
    echo "error: no standalone interpreter was installed under $PYTHON_RUNTIME" >&2
    exit 1
  fi

  echo "==> Creating bundled virtual environment"
  uv venv \
    --clear \
    --relocatable \
    --python "$RUNTIME_PYTHON" \
    "$PYTHON_ENV"

  echo "==> Installing Python dependencies into app bundle"
  uv pip install \
    --python "$PYTHON_ENV/bin/python" \
    --requirements "$REQUIREMENTS_FILE" \
    --link-mode copy \
    --compile-bytecode

  echo "==> Making the bundled environment relocatable"
  # bin/python must reach the interpreter through the bundle, never through the
  # directory the app happened to be built in.
  ln -sfn "$(python3 -c 'import os.path, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' \
    "$RUNTIME_PYTHON" "$PYTHON_ENV/bin")" \
    "$PYTHON_ENV/bin/python"

  for alias in "$PYTHON_RUNTIME"/cpython-*; do
    [[ -L "$alias" ]] || continue
    target="$(python3 -c 'import os, sys; print(os.readlink(sys.argv[1]))' "$alias")"
    [[ "$target" == /* ]] || continue
    ln -sfn "$(python3 -c 'import os.path, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' \
      "$target" "$(dirname "$alias")")" "$alias"
  done

  python3 - "$PYTHON_ENV/pyvenv.cfg" "$(dirname "$RUNTIME_PYTHON")" "$PYTHON_ENV/bin" <<'PY'
import os.path
import sys

cfg, runtime_bin, venv_bin = sys.argv[1:4]
home = os.path.relpath(runtime_bin, venv_bin)
lines = open(cfg).read().splitlines()
with open(cfg, "w") as handle:
    handle.write("\n".join(f"home = {home}" if line.startswith("home =") else line
                          for line in lines) + "\n")
PY

  rm -rf "$PYTHON_RUNTIME/.temp" "$PYTHON_RUNTIME/.lock"

  # Compile the bundled standard library up front. Any module that is still
  # uncompiled on first launch would be written into the (already sealed) app
  # bundle, and the app must never modify itself.
  echo "==> Pre-compiling bundled standard library"
  "$PYTHON_ENV/bin/python3" -m compileall -q "$PYTHON_RUNTIME"/cpython-*/lib/python"$PYTHON_VERSION" \
    >/dev/null

  echo "==> Verifying bundled Python runtime"
  if [[ ! -x "$PYTHON_ENV/bin/python3" ]]; then
    echo "error: bundled interpreter is not executable: $PYTHON_ENV/bin/python3" >&2
    exit 1
  fi

  # A link that resolves outside the bundle works on the build host and breaks
  # the moment the app is moved to /Applications, so fail the build instead.
  python3 - "$APP_BUNDLE" <<'PY'
import os
import sys

root = os.path.realpath(sys.argv[1])
escaped = []
for dirpath, dirnames, filenames in os.walk(root):
    for name in dirnames + filenames:
        path = os.path.join(dirpath, name)
        if not os.path.islink(path):
            continue
        target = os.path.realpath(path)
        if target != root and not target.startswith(root + os.sep):
            escaped.append((os.path.relpath(path, root), os.readlink(path)))

for rel, link in escaped:
    print(f"  escapes the bundle: {rel} -> {link}", file=sys.stderr)
if escaped:
    print(f"error: {len(escaped)} link(s) resolve outside {root}", file=sys.stderr)
    sys.exit(1)
print("  no link escapes the bundle")
PY

  "$PYTHON_ENV/bin/python3" - "$APP_BUNDLE" <<'PY'
import os
import platform
import sys

root = os.path.realpath(sys.argv[1])
real = os.path.realpath(sys.executable)
if not real.startswith(root + os.sep):
    sys.exit(f"error: interpreter {real} is outside {root}")
print(f"Bundled Python: {sys.version.split()[0]} ({platform.machine()})")
print(f"  interpreter: {real}")
print(f"  site-packages: {sys.prefix}/lib")
PY
fi

echo "==> Codesigning app bundle"
# Sign only the executable, then seal the app
# (SwiftPM resource bundles are flat and not individually codesignable)
codesign --force --options runtime --sign "$CODESIGN_IDENTITY" \
  "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
codesign --force --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"

echo "==> Creating DMG artifact"
# -fs HFS+: the default APFS-in-UDZO image is ~45% larger for the same payload.
TEMP_DMG_DIR="$(mktemp -d)"
ditto "$APP_BUNDLE" "$TEMP_DMG_DIR/$APP_NAME.app"
ln -s /Applications "$TEMP_DMG_DIR/Applications"
hdiutil create \
  -fs HFS+ \
  -volname "$APP_NAME $APP_VERSION" \
  -srcfolder "$TEMP_DMG_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"
rm -rf "$TEMP_DMG_DIR"

echo "==> Creating ZIP artifact"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "Packaged:"
echo "  $APP_BUNDLE"
echo "  $DMG_PATH"
echo "  $ZIP_PATH"
