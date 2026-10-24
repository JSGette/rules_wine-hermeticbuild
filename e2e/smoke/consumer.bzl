"""Downstream consumer of Windows actions and executable adapters."""

load("@rules_wine//wine:actions.bzl", "windows_actions")

def _impl(ctx):
    action_output = ctx.actions.declare_file("external.json")
    windows_actions.run(
        ctx,
        executable = ctx.file.binary,
        arch = "x86_64",
        arguments = [
            "--output",
            windows_actions.path(ctx, action_output, "x86_64"),
            "external-consumer",
        ],
        outputs = [action_output],
    )
    adapter_output = ctx.actions.declare_file("adapter.json")
    ctx.actions.run(
        executable = ctx.attr.adapter[DefaultInfo].files_to_run,
        arguments = ["--output", windows_actions.path(ctx, adapter_output, "x86_64"), "adapter-consumer"],
        outputs = [adapter_output],
    )
    return [DefaultInfo(files = depset([action_output, adapter_output]))]

consumer = rule(
    implementation = _impl,
    attrs = {
        "binary": attr.label(allow_single_file = True, mandatory = True),
        "adapter": attr.label(executable = True, cfg = "exec", mandatory = True),
    },
    toolchains = [windows_actions.toolchain_type("x86_64")],
)
