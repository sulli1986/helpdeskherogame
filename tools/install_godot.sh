#!/usr/bin/env bash
# Install Godot + web export templates into ~/godot (skips if present) and link templates.
set -euo pipefail
V="${GODOT_VERSION:-4.5.1}"
if [ ! -x ~/godot/godot ]; then
  mkdir -p ~/godot && cd ~/godot
  base=https://github.com/godotengine/godot/releases/download/${V}-stable
  dl() { curl -fSL --retry 5 --retry-all-errors --retry-delay 5 --connect-timeout 30 -o "$1" "$2"; }
  dl g.zip "$base/Godot_v${V}-stable_linux.x86_64.zip"; unzip -q g.zip; rm g.zip
  mv Godot_v*_linux.x86_64 godot; chmod +x godot
  dl t.tpz "$base/Godot_v${V}-stable_export_templates.tpz"
  unzip -q t.tpz 'templates/web_nothreads_*' 'templates/version.txt'; rm t.tpz
fi
dest=~/.local/share/godot/export_templates/${V}.stable
mkdir -p "$dest" && cp ~/godot/templates/* "$dest/"
