#!/bin/sh
# Maintenance only: same Go compiler as the runtime; clang/lld for no-CRT DLL.
set -eu
cd "$(dirname "$0")/../tests/fixture"
GO=${1:?usage: tools/build_fixtures.sh /absolute/path/to/go1.25.3}
for cpu in amd64 arm64; do
  arch=x86_64; [ "$cpu" != arm64 ] || arch=aarch64
  CGO_ENABLED=0 GOOS=windows GOARCH=$cpu "$GO" build -trimpath -buildvcs=false -ldflags='-s -w -buildid=' -o "fixture_${arch}.exe" .
done
scratch=$(mktemp -d)
trap 'trash "$scratch"' EXIT
clang -target x86_64-pc-windows-msvc -c companion.c -o "$scratch/companion.obj"
lld-link /dll /noentry /out:companion.dll "/implib:$scratch/companion.lib" "$scratch/companion.obj"
shasum -a 256 fixture_x86_64.exe fixture_aarch64.exe companion.dll > SHA256SUMS
