"""Runfiles-preserving executable adapter with an executor-native launcher."""

load("//wine:actions.bzl", "windows_actions")
load("//wine/private:payload.bzl", "payload", "payload_attrs")

def _rlocation(ctx, file):
    return file.short_path[3:] if file.short_path.startswith("../") else ctx.workspace_name + "/" + file.short_path

def adapter_impl(ctx):
    arch = ctx.attr._arch
    group = ctx.attr._group
    runner = ctx.toolchains[Label("//wine:adapter_" + arch + "_toolchain_type")].windows if group == "default" else ctx.exec_groups[group].toolchains[windows_actions.toolchain_type(arch)].windows
    binary = payload(ctx, arch)
    suffix = ".exe" if runner.backend == "native" else ""
    executable = ctx.actions.declare_file(ctx.label.name + suffix)
    config = ctx.actions.declare_file(ctx.label.name + suffix + ".json")
    ctx.actions.symlink(output = executable, target_file = runner.launcher, is_executable = True)
    config_data = {
        "backend": runner.backend,
        "arch": arch,
        "payload": _rlocation(ctx, binary.file),
        "args": [ctx.expand_location(arg, targets = ctx.attr.binary + ctx.attr.data) for arg in ctx.attr.arguments],
        "env": ctx.attr.env,
        "runfiles": True,
    }
    runtime = []
    if runner.runtime:
        config_data.update({"loader": _rlocation(ctx, runner.runtime.loader), "runtime_env": runner.runtime.env, "server": _rlocation(ctx, runner.runtime.server)})
        runtime = [runner.runtime.files]
    ctx.actions.write(config, json.encode(config_data))
    runfiles = ctx.runfiles(files = [config, executable, runner.launcher, binary.file] + binary.data, transitive_files = depset(transitive = runtime)).merge(binary.runfiles)
    return [DefaultInfo(files = depset([executable, config]), executable = executable, runfiles = runfiles)]

def adapter_attrs(arch, group):
    attrs = payload_attrs()
    attrs.update({"_arch": attr.string(default = arch), "_group": attr.string(default = group), "arguments": attr.string_list(), "env": attr.string_dict()})
    return attrs

def _rule(arch):
    return rule(implementation = adapter_impl, executable = True, attrs = adapter_attrs(arch, "default"), toolchains = [Label("//wine:adapter_" + arch + "_toolchain_type")])

_x86_64 = _rule("x86_64")
_aarch64 = _rule("aarch64")

def windows_binary(name, binary, arch, **kwargs):
    """Wrap a prebuilt or source-built PE; arguments/env/data join payload runfiles.

    `target_platform` transitions only payload and data. Adapter target platform
    remains host by default, or the consuming executor when used as an exec tool.
    """
    if arch not in ["x86_64", "aarch64"]:
        fail("unsupported Windows payload architecture: " + arch)
    (_x86_64 if arch == "x86_64" else _aarch64)(name = name, binary = binary, **kwargs)
