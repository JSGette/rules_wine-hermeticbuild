"""Downstream consumer of Windows actions and executable adapters."""

load("@rules_wine//wine:actions.bzl", "windows_actions")

def _impl(ctx):
    runner = windows_actions.resolve(ctx)
    action_output = ctx.actions.declare_file("external.json")
    windows_actions.run(
        ctx,
        runner = runner,
        executable = ctx.file.binary,
        arguments = [
            "--output",
            windows_actions.path(runner, action_output),
            "external-consumer",
        ],
        outputs = [action_output],
    )
    adapter_output = ctx.actions.declare_file("adapter.json")
    ctx.actions.run(
        executable = ctx.attr.adapter[DefaultInfo].files_to_run,
        arguments = ["--output", windows_actions.path(runner, adapter_output), "adapter-consumer"],
        outputs = [adapter_output],
    )
    return [DefaultInfo(files = depset([action_output, adapter_output]))]

consumer = rule(
    implementation = _impl,
    attrs = {
        "binary": attr.label(allow_single_file = True, cfg = "exec", mandatory = True),
        "adapter": attr.label(executable = True, cfg = "exec", mandatory = True),
    },
    toolchains = [windows_actions.toolchain_type],
    exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
)
