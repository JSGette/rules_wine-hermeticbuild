"""Convenience output-producing Windows action."""

load("//wine:actions.bzl", "windows_actions")
load("//wine/private:payload.bzl", "payload", "payload_attrs")

def _native_paths(arg):
    parts = arg.split("{windows_path:")
    result = parts[0]
    for part in parts[1:]:
        path, separator, tail = part.partition("}")
        if not separator:
            fail("unterminated Windows path interpolation")
        result += path + tail
    return result

def _impl(ctx):
    arch = ctx.attr._arch
    binary = payload(ctx, arch)
    locations = ctx.attr.srcs + ctx.attr.binary + ctx.attr.data
    args = ctx.actions.args()
    variables = {"OUTS": " ".join([f.path for f in ctx.outputs.outs]), "SRCS": " ".join([f.path for f in ctx.files.srcs])}
    if len(ctx.outputs.outs) == 1:
        variables["@"] = ctx.outputs.outs[0].path
    expanded = [ctx.expand_make_variables("arguments", ctx.expand_location(arg, targets = locations), variables) for arg in ctx.attr.arguments]
    runner = ctx.exec_groups["windows"].toolchains[windows_actions.toolchain_type(arch)].windows
    args.add_all([_native_paths(arg) for arg in expanded] if runner.backend == "native" else expanded)
    windows_actions.run(ctx, executable = binary.files_to_run, arch = arch, arguments = [args], inputs = ctx.files.srcs, outputs = ctx.outputs.outs, runtime_files = binary.data + binary.runfiles.files.to_list(), env = ctx.attr.env, exec_group = "windows")
    return [DefaultInfo(files = depset(ctx.outputs.outs))]

def _rule(arch):
    attrs = payload_attrs()
    attrs.update({"_arch": attr.string(default = arch), "srcs": attr.label_list(allow_files = True), "outs": attr.output_list(mandatory = True), "arguments": attr.string_list(), "env": attr.string_dict()})
    return rule(implementation = _impl, attrs = attrs, exec_groups = {"windows": exec_group(toolchains = [windows_actions.toolchain_type(arch)])})

_x86_64 = _rule("x86_64")
_aarch64 = _rule("aarch64")

def windows_run(name, binary, arch, **kwargs):
    """Run a same-CPU Windows executable; target platform of outputs is unrestricted."""
    if arch not in ["x86_64", "aarch64"]:
        fail("unsupported Windows payload architecture: " + arch)
    (_x86_64 if arch == "x86_64" else _aarch64)(name = name, binary = binary, **kwargs)
