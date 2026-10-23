"""Use windows_binary as a real exec-configured action tool."""

def _impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    args = ctx.actions.args()
    args.add_all(["--output", "{windows_path:" + json.encode(output.path) + "}", "adapter-tool"])
    ctx.actions.run(
        executable = ctx.attr.tool[DefaultInfo].files_to_run,
        arguments = [args],
        outputs = [output],
        mnemonic = "AdapterTool",
    )
    return [DefaultInfo(files = depset([output]))]

adapter_action = rule(
    implementation = _impl,
    attrs = {
        "tool": attr.label(executable = True, cfg = "exec", mandatory = True),
    },
    exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
)
