#!/bin/sh
# Rebuild independent Windows test programs and the native Linux verifier.
set -eu
cd "$(dirname "$0")/.."
for arch in x86_64 aarch64; do
  bazel build //tests:fixture_build --platforms="@llvm//platforms:windows_$arch" "$@"
  cp bazel-bin/tests/fixture_build.exe "tests/fixture/fixture_$arch.exe"
done
bazel build //tests:verify_build --platforms=@llvm//platforms:linux_x86_64_musl "$@"
cp bazel-bin/tests/verify_build tests/verify/verify_linux_x86_64
scratch=$(mktemp -d)
trap 'trash "$scratch"' EXIT
clang -target x86_64-pc-windows-msvc -c tests/fixture/companion.c -o "$scratch/companion.obj"
lld-link /timestamp:0 /dll /noentry /out:tests/fixture/companion.dll "/implib:$scratch/companion.lib" "$scratch/companion.obj"
(cd tests/fixture && shasum -a 256 fixture_x86_64.exe fixture_aarch64.exe companion.dll > SHA256SUMS)
