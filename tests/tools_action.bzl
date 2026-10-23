"""Consumers exercise default execution, additional FTR tools and File inputs."""

load("//wine:actions.bzl", "windows_actions")

def _impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    group = "default" if ctx.attr.default_group else "windows"
    arguments = ["--output", windows_actions.path(ctx, output, "x86_64", exec_group = group)]
    kwargs = {}
    if ctx.attr.additional_tools:
        extra = ctx.attr.extra[DefaultInfo]
        arguments.append(windows_actions.path(ctx, ctx.file.extra_data, "x86_64", format = "@%s", exec_group = group))
        kwargs["tools"] = [extra.files_to_run]

        # A directly addressed File is an input. FTR runfiles have their own
        # logical layout and do not imply this execroot path is materialized.
        kwargs["runtime_files"] = [ctx.file.extra_data]
    windows_actions.run(
        ctx,
        executable = ctx.file.binary,
        arch = "x86_64",
        arguments = arguments,
        outputs = [output],
        exec_group = group,
        **kwargs
    )
    return [DefaultInfo(files = depset([output]))]

tools_action = rule(
    implementation = _impl,
    attrs = {
        "binary": attr.label(allow_single_file = True, mandatory = True),
        "extra": attr.label(executable = True, cfg = "exec"),
        "extra_data": attr.label(allow_single_file = True, cfg = "exec", default = "//tests:fixture/data café.txt"),
        "additional_tools": attr.bool(),
        "default_group": attr.bool(),
    },
    toolchains = [windows_actions.toolchain_type("x86_64")],
    exec_groups = {
        "windows": exec_group(toolchains = [windows_actions.toolchain_type("x86_64")]),
    },
)
