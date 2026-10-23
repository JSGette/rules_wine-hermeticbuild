"""Actual runtime integration test; native Linux helper, Wine Windows payloads."""

load("//wine:actions.bzl", "windows_actions")

def _rloc(ctx, file):
    return file.short_path[3:] if file.short_path.startswith("../") else ctx.workspace_name + "/" + file.short_path

def _impl(ctx):
    runner = ctx.exec_groups["test"].toolchains[windows_actions.toolchain_type("x86_64")].windows
    executable = ctx.actions.declare_file(ctx.label.name)
    config = ctx.actions.declare_file(ctx.label.name + ".json")
    ctx.actions.symlink(output = executable, target_file = ctx.file._verify, is_executable = True)
    ctx.actions.write(config, json.encode({"AdapterCLI": ctx.attr.adapter_cli_only, "PayloadLayout": ctx.attr.payload_layout, "Companion": _rloc(ctx, ctx.file.companion) if ctx.file.companion else "", "Launcher": _rloc(ctx, runner.launcher), "Loader": _rloc(ctx, runner.runtime.loader), "Server": _rloc(ctx, runner.runtime.server), "Payload": _rloc(ctx, ctx.file.payload), "WrongArch": _rloc(ctx, ctx.file.wrong_arch)}))
    return [DefaultInfo(executable = executable, runfiles = ctx.runfiles(files = [config, runner.launcher, ctx.file._verify, ctx.file.payload, ctx.file.wrong_arch] + ([ctx.file.companion] if ctx.file.companion else []), transitive_files = runner.runtime.files))]

runtime_contract_test = rule(implementation = _impl, test = True, attrs = {
    "adapter_cli_only": attr.bool(),
    "payload_layout": attr.bool(),
    "companion": attr.label(allow_single_file = True),
    "payload": attr.label(allow_single_file = True),
    "wrong_arch": attr.label(allow_single_file = True),
    "_verify": attr.label(default = "//tests:verify/verify_linux_x86_64", allow_single_file = True),
}, exec_groups = {"test": exec_group(toolchains = [windows_actions.toolchain_type("x86_64")], exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"])})
