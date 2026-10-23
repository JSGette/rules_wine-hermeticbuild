#!/bin/sh
# Exercise the extension through real module graphs and generated BUILD targets.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
rules=${1:-$root}
scratch=$(mktemp -d /tmp/rules-wine-extension.XXXXXX)
cp "$root/.bazelversion" "$scratch/.bazelversion"
printf 'Verification workspace: %s\n' "$scratch"
mkdir "$scratch/first" "$scratch/second"
printf '\n' > "$scratch/BUILD.bazel"
printf 'import %s/.bazelrc\n' "$rules" > "$scratch/.bazelrc"
dependency() {
  printf 'module(name = "%s", version = "0.1.0")\nbazel_dep(name = "rules_wine", version = "0.1.0")\nwine = use_extension("@rules_wine//wine/extension:wine.bzl", "wine")\nwine.toolchains(name = "shared"%s)\nuse_repo(wine, "shared")\n' "$1" "$2" > "$scratch/$1/MODULE.bazel"
  printf '\n' > "$scratch/$1/BUILD.bazel"
}
root_module() {
  printf 'module(name = "extension_checks")\nbazel_dep(name = "rules_wine", version = "0.1.0")\nlocal_path_override(module_name = "rules_wine", path = "%s")\nbazel_dep(name = "first", version = "0.1.0")\nbazel_dep(name = "second", version = "0.1.0")\nlocal_path_override(module_name = "first", path = "first")\nlocal_path_override(module_name = "second", path = "second")\nwine = use_extension("@rules_wine//wine/extension:wine.bzl", "wine")\n%s\nuse_repo(wine, "shared")\n' "$rules" "$1" > "$scratch/MODULE.bazel"
}
cd "$scratch"
trap 'bazel shutdown >/dev/null 2>&1' EXIT
dependency first ', x86_64 = "default"'
dependency second ', x86_64 = "default"'
root_module ''
bazel cquery '@shared//:all' --config=remote --extra_execution_platforms=@rules_wine//platforms:remote_linux_x86_64 > equal.txt
grep -q 'windows_x86_64' equal.txt
grep -q 'linux_x86_64' equal.txt
dependency second ''
root_module 'wine.toolchains(name = "shared")'
bazel cquery '@shared//:all' --config=remote --extra_execution_platforms=@rules_wine//platforms:remote_linux_x86_64 > override.txt
if grep -q 'linux_' override.txt; then exit 1; fi
root_module ''
if bazel cquery '@shared//:all' --config=remote --extra_execution_platforms=@rules_wine//platforms:remote_linux_x86_64 > conflict.txt 2>&1; then
  printf '%s\n' 'expected conflicting dependency declarations to fail' >&2
  exit 1
fi
grep -q 'conflicting Wine toolchains repository shared' conflict.txt
root_module 'wine.toolchains(name = "shared")
wine.toolchains(name = "shared", x86_64 = "default")'
if bazel cquery '@shared//:all' --config=remote --extra_execution_platforms=@rules_wine//platforms:remote_linux_x86_64 > root-conflict.txt 2>&1; then exit 1; fi
grep -q 'conflicting Wine toolchains repository shared' root-conflict.txt
root_module 'wine.toolchains(name = "shared")
wine.toolchains(name = "wine_default")'
if bazel cquery '@shared//:all' --config=remote --extra_execution_platforms=@rules_wine//platforms:remote_linux_x86_64 > reserved.txt 2>&1; then exit 1; fi
grep -q 'reserved Wine distribution namespace' reserved.txt
printf '%s\n' 'PASS: equivalent dependency configurations, root override, conflicts and internal repository names'
