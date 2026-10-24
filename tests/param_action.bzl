"""Real Args param-file and depset-input consumer of the public helper."""

load("//wine:actions.bzl", "windows_actions")

def _impl(ctx):
    runner = windows_actions.resolve(ctx, exec_group = "windows")
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    response = ctx.actions.args()
    response.add_all(["response one", "café", ""])
    response.use_param_file("@%s", use_always = True)
    response.set_param_file_format("multiline")
    windows_actions.run(
        ctx,
        runner = runner,
        executable = ctx.file.binary,
        arguments = [
            "--output",
            windows_actions.path(runner, output),
            "/option:one/two",
            "https://example.test/a/b",
            response,
        ],
        inputs = depset(),
        outputs = [output],
        env = {"FIXTURE_VALUE": "opaque/unchanged"},
    )
    return [DefaultInfo(files = depset([output]))]

param_action = rule(
    implementation = _impl,
    attrs = {
        "binary": attr.label(allow_single_file = True, cfg = config.exec("windows"), mandatory = True),
    },
    exec_groups = {
        "windows": exec_group(
            toolchains = [windows_actions.toolchain_type],
            exec_compatible_with = ["@platforms//cpu:x86_64"],
        ),
    },
)
