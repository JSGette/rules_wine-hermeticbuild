#!/bin/sh
# External-consumer acquisition/override verification, validating a caller-supplied checksum.
set -eu
archive=${1:?usage: e2e/test_custom_archive.sh archive.tar.xz sha256}
checksum=${2:?archive sha256 required}
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d /tmp/rules-wine-custom-consumer.XXXXXX)
cat > "$scratch/MODULE.bazel" <<MODULE
module(name = "custom_wine_consumer")
bazel_dep(name = "rules_wine", version = "0.1.0")
bazel_dep(name = "platforms", version = "1.1.0")
local_path_override(module_name = "rules_wine", path = "$root")
wine = use_extension("@rules_wine//wine/extension:wine.bzl", "wine")
wine.prebuilt(exec_os = "linux", arch = "x86_64", urls = ["file://$archive"], sha256 = "$checksum", strip_prefix = "wine-11.0-amd64-wow64", identity = "Local Kron4ek Wine11.0 archive override", requirements = "Ubuntu24.04 console baseline")
use_repo(wine, "wine_toolchains")
register_toolchains("@wine_toolchains//:all")
MODULE
cp "$root/e2e/smoke/BUILD.bazel" "$scratch/BUILD.bazel"
cp "$root/e2e/smoke/consumer.bzl" "$scratch/consumer.bzl"
cp "$root/e2e/smoke/.bazelrc" "$scratch/.bazelrc"
cp "$root/.bazelversion" "$scratch/.bazelversion"
printf '%s\n' "Verification consumer: $scratch"
cd "$scratch"
trap 'bazel --output_base="$scratch/output" shutdown >/dev/null 2>&1' EXIT
bazel --output_base="$scratch/output" build //:generate --config=remote
jq -e '.args | index("external-consumer") != null' bazel-bin/external.json
jq -e '.args | index("adapter-consumer") != null' bazel-bin/adapter.json
