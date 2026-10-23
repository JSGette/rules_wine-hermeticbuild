#!/bin/sh
# Rebuild development-only PE fixtures with Bazel's declared compiler/toolchain.
set -eu
cd "$(dirname "$0")/.."
for arch in x86_64 aarch64; do
  bazel build //tests:fixture_build --platforms="@llvm//platforms:windows_$arch" "$@"
  cp bazel-bin/tests/fixture_build.exe "tests/fixture/fixture_$arch.exe"
done
bazel build //tests:companion_build --platforms=@llvm//platforms:windows_x86_64 "$@"
cp bazel-bin/tests/libcompanion_build.so tests/fixture/companion.dll
(cd tests/fixture && shasum -a 256 fixture_x86_64.exe fixture_aarch64.exe companion.dll > SHA256SUMS)
