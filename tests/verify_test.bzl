"""Actual runtime integration test; native Linux helper, Wine Windows payloads."""

load("//wine:actions.bzl", "windows_actions")

def _rloc(ctx, file):
    return file.short_path[3:] if file.short_path.startswith("../") else ctx.workspace_name + "/" + file.short_path

def _impl(ctx):
    runner = ctx.exec_groups["test"].toolchains[windows_actions.toolchain_type("x86_64")].windows
    executable = ctx.actions.declare_file(ctx.label.name)
    config = ctx.actions.declare_file(ctx.label.name + ".json")
    ctx.actions.symlink(output = executable, target_file = ctx.executable._verify, is_executable = True)
    ctx.actions.write(config, json.encode({
        "PayloadLayout": ctx.attr.payload_layout,
        "Companion": _rloc(ctx, ctx.file.companion) if ctx.file.companion else "",
        "Launcher": _rloc(ctx, runner.launcher.executable),
        "Loader": _rloc(ctx, runner.runtime.loader),
        "Server": _rloc(ctx, runner.runtime.server),
        "Payload": _rloc(ctx, ctx.file.payload),
        "WrongArch": _rloc(ctx, ctx.file.wrong_arch),
    }))
    runfiles = ctx.runfiles(
        files = [
            config,
            runner.launcher.executable,
            ctx.executable._verify,
            ctx.file.payload,
            ctx.file.wrong_arch,
        ] + ([ctx.file.companion] if ctx.file.companion else []),
        transitive_files = runner.runtime.files,
    ).merge_all([runner.runfiles, ctx.attr._verify[DefaultInfo].default_runfiles])
    return [DefaultInfo(executable = executable, runfiles = runfiles)]

runtime_contract_test = rule(
    implementation = _impl,
    test = True,
    attrs = {
        "payload_layout": attr.bool(),
        "companion": attr.label(allow_single_file = True),
        "payload": attr.label(allow_single_file = True, mandatory = True),
        "wrong_arch": attr.label(allow_single_file = True, mandatory = True),
        "_verify": attr.label(default = "//tests:verify_build", executable = True, cfg = config.exec("test")),
    },
    exec_groups = {
        "test": exec_group(
            toolchains = [windows_actions.toolchain_type("x86_64")],
            exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
        ),
    },
)
