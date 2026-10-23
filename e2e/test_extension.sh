#!/bin/sh
# Exercise the extension through real module graphs and generated BUILD targets.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
rules=${1:-$root}
scratch=$(mktemp -d /tmp/rules-wine-extension.XXXXXX)
cp "$root/.bazelversion" "$scratch/.bazelversion"
printf 'Verification workspace: %s\n' "$scratch"
mkdir "$scratch/first" "$scratch/second"
mkdir -p "$scratch/archive/bin"
printf 'archive loader\n' > "$scratch/archive/bin/wine"
printf 'archive server\n' > "$scratch/archive/bin/wineserver"
tar -cf "$scratch/wine.tar" -C "$scratch/archive" bin
checksum=$(shasum -a 256 "$scratch/wine.tar" | cut -d ' ' -f 1)
printf '\n' > "$scratch/BUILD.bazel"
printf 'import %s/.bazelrc\n' "$rules" > "$scratch/.bazelrc"
dependency() {
  printf 'module(name = "%s", version = "0.1.0")\nbazel_dep(name = "rules_wine", version = "0.1.0")\nwine = use_extension("@rules_wine//wine/extension:wine.bzl", "wine")\n%s\nuse_repo(wine, "wine_toolchains")\n' "$1" "$2" > "$scratch/$1/MODULE.bazel"
  printf '\n' > "$scratch/$1/BUILD.bazel"
}
root_module() {
  printf 'module(name = "extension_checks")\nbazel_dep(name = "rules_wine", version = "0.1.0")\nlocal_path_override(module_name = "rules_wine", path = "%s")\nbazel_dep(name = "first", version = "0.1.0")\nbazel_dep(name = "second", version = "0.1.0")\nlocal_path_override(module_name = "first", path = "first")\nlocal_path_override(module_name = "second", path = "second")\nwine = use_extension("@rules_wine//wine/extension:wine.bzl", "wine"%s)\n%s\nuse_repo(wine, "wine_toolchains")\n' "$rules" "${2:-}" "$1" > "$scratch/MODULE.bazel"
}
prebuilt() {
  printf 'wine.prebuilt(exec_os = "%s", arch = "%s", urls = ["file://%s/wine.tar"], sha256 = "%s", identity = "%s", requirements = "analysis fixture")\n' "$1" "$2" "$scratch" "$checksum" "$3"
}
query() {
  bazel cquery '@wine_toolchains//:all' --config=remote --extra_execution_platforms=@rules_wine//platforms:remote_linux_x86_64 --output=starlark --starlark:expr='str(target.label) + " " + str(providers(target))' > "$1" 2> "$1.log"
}
reject() {
  if query "$1"; then
    printf 'expected extension failure: %s\n' "$1" >&2
    exit 1
  fi
  grep -q "$2" "$1.log"
}
cd "$scratch"
trap 'bazel shutdown >/dev/null 2>&1' EXIT
dependency first ''
dependency second ''
root_module ''
query default.txt
grep -q 'Kron4ek Wine 11.0' default.txt
grep -q ':windows_x86_64 ' default.txt
grep -q ':windows_aarch64 ' default.txt
if grep -Eq ':linux_aarch64 |:osx_' default.txt; then exit 1; fi
dependency first "$(prebuilt linux x86_64 shared)"
dependency second "$(prebuilt linux x86_64 shared)"
query equal.txt
grep -q 'identity = "shared"' equal.txt
dependency second "$(prebuilt linux x86_64 conflicting)"
root_module "$(prebuilt linux x86_64 root)"
query override.txt
grep -q 'identity = "root"' override.txt
root_module ''
reject conflict.txt 'conflicting Wine prebuilts for linux_x86_64'
dependency first ''
dependency second ''
root_module "$(prebuilt linux x86_64 root)
$(prebuilt linux x86_64 root)"
reject duplicate.txt 'duplicate Wine prebuilt for linux_x86_64'
root_module "$(prebuilt linux aarch64 linux_arm)
$(prebuilt osx x86_64 mac_intel)
$(prebuilt osx aarch64 mac_arm)"
query platforms.txt
grep -q 'identity = "linux_arm"' platforms.txt
grep -q 'identity = "mac_intel"' platforms.txt
grep -q 'identity = "mac_arm"' platforms.txt
grep -q 'Kron4ek Wine 11.0' platforms.txt
root_module '' ', dev_dependency = True'
query dev.txt
if grep -q 'WARNING.*extension' dev.txt.log; then exit 1; fi
printf '%s\n' 'PASS: automatic defaults, archive overrides, dependency sharing, root precedence, conflicts, platforms and dev usage'
