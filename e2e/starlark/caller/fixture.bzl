"""External executable owning its data, independent of the adapter."""

def _impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name + ".exe")
    ctx.actions.symlink(output = executable, target_file = ctx.file.binary, is_executable = True)
    return [DefaultInfo(
        executable = executable,
        runfiles = ctx.runfiles(files = [executable] + ctx.files.data),
    )]

payload = rule(
    implementation = _impl,
    executable = True,
    attrs = {
        "binary": attr.label(allow_single_file = True, mandatory = True),
        "data": attr.label_list(allow_files = True),
    },
)
