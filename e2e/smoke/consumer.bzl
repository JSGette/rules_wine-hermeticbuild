"""Downstream consumer of Windows actions and executable adapters."""

load("@rules_wine//wine:actions.bzl", "windows_actions")

def _impl(ctx):
    runner = windows_actions.resolve(ctx)
    action_output = ctx.actions.declare_file("external.json")
    action_args = ctx.actions.args()
    action_args.add("--output")
    windows_actions.add_path(runner, action_args, action_output)
    action_args.add("external-consumer")
    windows_actions.run(
        ctx,
        runner = runner,
        executable = ctx.file.binary,
        arguments = [action_args],
        outputs = [action_output],
    )
    adapter_output = ctx.actions.declare_file("adapter.json")
    adapter_args = ctx.actions.args()
    adapter_args.add("--output")
    windows_actions.add_path(runner, adapter_args, adapter_output)
    adapter_args.add("adapter-consumer")
    ctx.actions.run(
        executable = ctx.attr.adapter[DefaultInfo].files_to_run,
        arguments = [adapter_args],
        outputs = [adapter_output],
        mnemonic = "WineAdapterConsumer",
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
