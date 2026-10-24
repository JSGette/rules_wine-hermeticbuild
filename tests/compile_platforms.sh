#!/bin/sh
# Cross-compile the source-built supervisor for each supported executor platform.
set -eu
cd "$(dirname "$0")/.."
for platform in \
  linux_x86_64_musl \
  linux_aarch64_musl \
  macos_x86_64 \
  macos_aarch64; do
  bazel build //wine/runtime:supervisor --platforms="@llvm//platforms:$platform" "$@"
done
