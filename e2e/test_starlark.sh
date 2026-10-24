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
  bazel aquery "$1" --config=remote --extra_execution_platforms=//:audit_exec --extra_toolchains="$2" --lockfile_mode=off > "$scratch/$3"
}
query 'deps(//:collision)' '//:runner' actions.txt
grep -q 'launcher_data' actions.txt
query '//:collision' '//:generated_runner' generated.txt
grep -Eq 'bazel-out/[^ /]*-opt-exec[^ /]*/bin/built_loader.sh' generated.txt
query 'deps(//:collision)' '//:sidecar_runner' sidecar.txt
grep -q 'sidecar_launcher.json' sidecar.txt
grep -q 'launcher_data' sidecar.txt
bazel aquery '//:collision' --config=remote --extra_execution_platforms=//:audit_windows --extra_toolchains=//:native_runner --lockfile_mode=off > native.txt
if grep -Eq 'wine.json|launcher_data|supervisor' native.txt; then
  printf '%s\n' 'native action acquired a launcher or Wine configuration' >&2
  exit 1
fi
bazel build //:data_adapter //:apparent_platform @caller//:mapped --config=remote --jobs=80 --lockfile_mode=off --platforms=//:audit_exec --extra_execution_platforms=//:audit_exec --extra_toolchains=//:adapter
jq -e '.runfiles == true and .arch == "x86_64" and .args == null and .env == null' bazel-bin/data_adapter.json
grep -q 'launcher_data' bazel-bin/data_adapter.runfiles_manifest
grep -q 'alias.txt.*only_via_alias' bazel-bin/data_adapter.runfiles_manifest
bazel cquery //:data_adapter --config=remote --platforms=//:audit_exec --extra_execution_platforms=//:audit_exec --extra_toolchains=//:adapter --lockfile_mode=off --output=starlark --starlark:expr='providers(target)["RunEnvironmentInfo"].environment' > environment.txt
grep -q 'binary-owned environment' environment.txt
bazel aquery 'deps(//:data_adapter)' --config=remote --platforms=//:audit_exec --extra_execution_platforms=//:audit_exec --extra_toolchains=//:adapter > adapter.txt
grep -q 'finalize' adapter.txt
for target in wrong_platform wrong_cpu; do
  if bazel aquery "//:$target" --config=remote --platforms=//:audit_exec --extra_execution_platforms=//:audit_exec --extra_toolchains=//:adapter > "$target.txt" 2> "$target.log"; then
    printf 'expected analysis failure: %s\n' "$target" >&2
    exit 1
  fi
  grep -q 'target_platform must be Windows/x86_64' "$target.log"
done
printf '%s\n' 'PASS: executable runfiles, payload platforms, action identity, exec dependencies and native actions'
