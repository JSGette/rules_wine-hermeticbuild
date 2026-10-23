#!/bin/sh
# Maintenance only. Pass an absolute Go 1.25.3 binary; no downstream compiler.
set -eu
cd "$(dirname "$0")/../wine/runtime"
GO=${1:?usage: tools/build_runtime.sh /absolute/path/to/go1.25.3}
case "$("$GO" version)" in 'go version go1.25.3 '*) ;; *) echo 'Go 1.25.3 required' >&2; exit 1;; esac
for os in linux windows darwin; do
  for cpu in amd64 arm64; do
    arch=x86_64; [ "$cpu" != arm64 ] || arch=aarch64
    suffix=; [ "$os" != windows ] || suffix=.exe
    CGO_ENABLED=0 GOOS=$os GOARCH=$cpu "$GO" build -trimpath -buildvcs=false -ldflags='-s -w -buildid=' -o "${os}_${arch}${suffix}" .
  done
done
shasum -a 256 linux_x86_64 linux_aarch64 windows_x86_64.exe windows_aarch64.exe darwin_x86_64 darwin_aarch64 > SHA256SUMS
