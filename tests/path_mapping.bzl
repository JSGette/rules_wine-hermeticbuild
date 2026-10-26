"""Real Wine actions with generated paths and conflicting configurations."""

load("//wine:actions.bzl", "windows_actions")

_VariantInfo = provider("Content selected by the test configuration.", fields = ["value"])

def _variant_impl(ctx):
    return [_VariantInfo(value = ctx.build_setting_value)]

mapping_variant = rule(implementation = _variant_impl, build_setting = config.string())

def _input_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + "/data café {input}.txt")
    ctx.actions.write(output, ctx.attr._variant[_VariantInfo].value)
    return [DefaultInfo(files = depset([output]))]

mapping_input = rule(
    implementation = _input_impl,
    attrs = {"_variant": attr.label(default = "//tests:mapping_variant")},
)

def _split_impl(_settings, _attr):
    return {value: {"//tests:mapping_variant": value} for value in ["first", "second"]}

_split = transition(
    implementation = _split_impl,
    inputs = [],
    outputs = ["//tests:mapping_variant"],
)

def _payload_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".exe")
    ctx.actions.symlink(output = output, target_file = ctx.file.binary, is_executable = True)
    return [DefaultInfo(executable = output)]

mapping_payload = rule(
    implementation = _payload_impl,
    executable = True,
    attrs = {"binary": attr.label(allow_single_file = True, mandatory = True)},
)

def _impl(ctx):
    runner = windows_actions.resolve(ctx)
    inputs = [ctx.split_attr.src[key][DefaultInfo].files.to_list()[0] for key in ["first", "second"]]
    if not ctx.attr.collision:
        inputs = inputs[:1]
    output = ctx.actions.declare_file(ctx.label.name + "/result café {output}.json")
    args = ctx.actions.args()
    args.add("--output")
    windows_actions.add_path(runner, args, output)
    for file in inputs:
        windows_actions.add_path(runner, args, file, format = "@%s")
    response = ctx.actions.args()
    response.add_all(inputs)
    response.use_param_file("@%s", use_always = True)
    response.set_param_file_format("multiline")
    windows_actions.run(
        ctx,
        runner = runner,
        executable = ctx.attr.binary[DefaultInfo].files_to_run,
        arguments = [args, response],
        inputs = inputs,
        outputs = [output],
        env = {"FIXTURE_VALUE": "space café\nquote\"backslash\\"},
        execution_requirements = {"supports-path-mapping": "1"},
    )
    return [DefaultInfo(files = depset([output]))]

mapping_action = rule(
    implementation = _impl,
    attrs = {
        "binary": attr.label(executable = True, cfg = "exec", mandatory = True),
        "src": attr.label(cfg = _split, mandatory = True),
        "collision": attr.bool(),
        "_allowlist_function_transition": attr.label(default = "@bazel_tools//tools/allowlists/function_transition_allowlist"),
    },
    toolchains = [windows_actions.toolchain_type],
    exec_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
)
