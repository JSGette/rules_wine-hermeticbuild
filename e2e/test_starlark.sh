#!/bin/sh
# Analysis/configuration regression checks; no execution of synthetic payloads.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
rules=${1:-$root}
scratch=$(mktemp -d /tmp/rules-wine-starlark.XXXXXX)
cp -R "$root/e2e/starlark/." "$scratch/"
cp "$root/.bazelversion" "$scratch/.bazelversion"
printf 'module(name = "wine_audit")\nbazel_dep(name = "rules_wine", version = "0.1.0")\nlocal_path_override(module_name = "rules_wine", path = "%s")\nbazel_dep(name = "platforms", version = "1.0.0")\n' "$rules" > "$scratch/MODULE.bazel"
printf 'bazel_dep(name = "caller", version = "0.1.0")\nlocal_path_override(module_name = "caller", path = "caller")\n' >> "$scratch/MODULE.bazel"
printf 'import %s/.bazelrc\n' "$rules" > "$scratch/.bazelrc"
printf 'Verification workspace: %s\n' "$scratch"
cd "$scratch"
trap 'bazel shutdown >/dev/null 2>&1' EXIT
query() {
  bazel aquery "$1" --config=remote --extra_execution_platforms=//:audit_exec --extra_toolchains="$2" > "$scratch/$3"
}
query 'deps(//:collision + //:dollar_path + //:data_action + //:apparent_platform)' '//:runner' actions.txt
grep -q 'only_via_alias' actions.txt
grep -q 'launcher_data' actions.txt
grep -q 'cash\$money' actions.txt
query '//:dollar_path' '//:generated_runner' generated.txt
grep -Eq 'bazel-out/[^ /]*-opt-exec[^ /]*/bin/built_loader.sh' generated.txt
query 'deps(//:dollar_path)' '//:sidecar_runner' sidecar.txt
grep -q 'sidecar_launcher.json' sidecar.txt
grep -q 'launcher_data' sidecar.txt
query '//:only_test_adapter_test' '//:test_adapter' test.txt
bazel aquery '//:collision' --config=remote --extra_execution_platforms=//:audit_windows --extra_toolchains=//:native_runner > native.txt
if grep -Eq 'wine.json|launcher_data|supervisor' native.txt; then
  printf '%s\n' 'native action acquired a launcher or Wine configuration' >&2
  exit 1
fi
bazel build //:root_location //:space_adapter //:ambiguous //:escaped //:braces //:data_adapter //:executable_locations //:selected_aliases @caller//:mapped --config=remote --extra_execution_platforms=//:audit_exec --extra_toolchains=//:adapter
jq -e '.args == ["{windows_runfile:\"_main/a\"}"]' bazel-bin/root_location.json
jq -e '.args == ["{windows_runfile:\"_main/data/a\"}", "{windows_runfile:\"_main/data/b\"}"]' bazel-bin/ambiguous.json
jq -e '.args == ["$(location :data/a)"]' bazel-bin/escaped.json
jq -e '.args == ["{windows_runfile:\"_main/data/a}b\"}"]' bazel-bin/braces.json
jq -e '.args == ["{windows_runfile:\"_main/root_location\"}", "{windows_runfile:\"_main/root_location\"}"]' bazel-bin/executable_locations.json
jq -e '.args | length == 3' bazel-bin/selected_aliases.json
grep -q 'launcher_data' bazel-bin/data_adapter.runfiles_manifest
for target in embedded_plural single_multiple undeclared empty_location empty_alias_location; do
  if query "//:$target" '//:adapter' "$target.txt" 2> "$target.log"; then
    printf 'expected analysis failure: %s\n' "$target" >&2
    exit 1
  fi
done
grep -q 'plural file expression must be a complete argument' embedded_plural.log
grep -q 'requires one file' single_multiple.log
grep -Eq 'must be declared|not a declared prerequisite' undeclared.log
grep -q 'must produce at least one file' empty_location.log
grep -q 'expands to no files' empty_alias_location.log
printf '%s\n' 'PASS: typed argv, action identity, exec dependencies, aliases, native actions and independent test group'
