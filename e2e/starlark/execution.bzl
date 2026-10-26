"""Execution-group selection independent of the final output platform."""

load("@rules_wine//wine:actions.bzl", "windows_actions")

def _impl(ctx):
    outputs = []
    for group in ["wine", "native"]:
        runner = windows_actions.resolve(ctx, exec_group = group)
        output = ctx.actions.declare_file(ctx.label.name + "/" + group)
        args = ctx.actions.args()
        windows_actions.add_path(runner, args, output)
        windows_actions.run(
            ctx,
            runner = runner,
            executable = getattr(ctx.attr, group)[DefaultInfo].files_to_run,
            arguments = [args],
            outputs = [output],
            mnemonic = "WineFixture" if group == "wine" else "NativeFixture",
        )
        outputs.append(output)
    return [DefaultInfo(files = depset(outputs))]

grouped_actions = rule(
    implementation = _impl,
    attrs = {
        # Synthetic executables only: inspect their configuration and runfiles,
        # never execute them as Windows programs.
        "wine": attr.label(executable = True, cfg = config.exec("wine"), mandatory = True),
        "native": attr.label(executable = True, cfg = config.exec("native"), mandatory = True),
    },
    exec_groups = {
        "wine": exec_group(
            toolchains = [windows_actions.toolchain_type],
            exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:aarch64"],
        ),
        "native": exec_group(
            toolchains = [windows_actions.toolchain_type],
            exec_compatible_with = ["@platforms//os:windows", "@platforms//cpu:x86_64"],
        ),
    },
)
