"""Consumers exercise default execution and additional tool runfiles."""

load("//wine:actions.bzl", "windows_actions")

def _impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    group = "default" if ctx.attr.default_group else "windows"
    arguments = ["--output", windows_actions.path(ctx, output, "x86_64", exec_group = group)]
    kwargs = {}
    if ctx.attr.additional_tools:
        extra = ctx.attr.extra[DefaultInfo]
        data = [f for f in extra.default_runfiles.files.to_list() if f.basename == "data café.txt"][0]
        runfile = extra.files_to_run.executable.path + ".runfiles/" + ctx.workspace_name + "/" + data.short_path
        arguments.append(windows_actions.path(ctx, runfile, "x86_64", format = "@%s", exec_group = group))
        kwargs["tools"] = [extra.files_to_run]
    windows_actions.run(ctx, executable = ctx.file.binary, arch = "x86_64", arguments = arguments, outputs = [output], exec_group = group, **kwargs)
    return [DefaultInfo(files = depset([output]))]

tools_action = rule(
    implementation = _impl,
    attrs = {
        "binary": attr.label(allow_single_file = True),
        "extra": attr.label(executable = True, cfg = "exec"),
        "additional_tools": attr.bool(),
        "default_group": attr.bool(),
    },
    toolchains = [windows_actions.toolchain_type("x86_64")],
    exec_groups = {"windows": exec_group(toolchains = [windows_actions.toolchain_type("x86_64")])},
)
