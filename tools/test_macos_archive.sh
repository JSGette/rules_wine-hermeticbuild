#!/bin/sh
# Diagnostic consumer for a trusted native ARM64 macOS Wine archive.
# The DiagBridge research archive currently rejects this independent PE (status53).
# No download, Rosetta, security-setting changes, or publication.
set -eu
archive=${1:?usage: tools/test_macos_archive.sh archive.tar.gz sha256}
checksum=${2:?archive sha256 required}
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d /tmp/rules-wine-macos-consumer.XXXXXX)
cat > "$scratch/MODULE.bazel" <<MODULE
module(name = "macos_wine_consumer")
bazel_dep(name = "rules_wine", version = "0.1.0")
local_path_override(module_name = "rules_wine", path = "$root")
wine = use_extension("@rules_wine//wine/extension:wine.bzl", "wine")
wine.prebuilt(name = "native_macos_arm64", arch = "aarch64", exec_os = "osx", urls = ["file://$archive"], sha256 = "$checksum", strip_prefix = "DiagBridge.app", loader = "Contents/Resources/wine/bin/wine", server = "Contents/Resources/wine/bin/wineserver", identity = "DiagBridge research runtime; local verified repack", requirements = "macOS26.5.2; signed runtime with upstream entitlements; bundled dylibs", env = {"DYLD_FALLBACK_LIBRARY_PATH": "{loader_dir}/../../libs"})
wine.toolchains(name = "macos_toolchains", macos_aarch64 = "native_macos_arm64")
use_repo(wine, "macos_toolchains")
register_toolchains("@macos_toolchains//:all")
MODULE
cat > "$scratch/BUILD.bazel" <<'BUILD'
load("@rules_wine//wine:windows_binary.bzl", "windows_binary")
load("@rules_wine//wine:windows_test.bzl", "windows_test")
windows_binary(name = "native_arm64", binary = "@rules_wine//tests:fixture/minimal_aarch64.exe", arch = "aarch64", arguments = ["space value", "", "café", "--isolated"])
windows_test(name = "native_arm64_test", binary = "@rules_wine//tests:fixture/minimal_aarch64.exe", arch = "aarch64", arguments = ["--contract", "with spaces", "", "café", "--isolated"], shard_count = 2)
BUILD
printf '%s\n' "Verification consumer: $scratch"
cd "$scratch"
bazel --output_base="$scratch/output" run //:native_arm64
bazel --output_base="$scratch/output" test //:native_arm64_test --test_output=errors
