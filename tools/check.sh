#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/.tools:$PATH"
mkdir -p build
rojo build default.project.json -o build/escape-the-chad.rbxlx
lune run tests/rules.spec.luau
lune run tests/place.spec.luau
lune run tests/world.spec.luau
