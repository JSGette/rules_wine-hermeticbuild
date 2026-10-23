"""Analysis-level runner inspection without a payload compiler."""

def _impl(ctx):
    info = ctx.toolchains[ctx.attr._type].windows
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    ctx.actions.write(output, json.encode({"backend": info.backend, "arch": info.arch, "launcher": info.launcher.path, "loader": info.runtime.loader.path if info.runtime else None}))
    return [DefaultInfo(files = depset([output]))]

def _probe(arch):
    label = Label("//wine:runner_" + arch + "_toolchain_type")
    return rule(implementation = _impl, attrs = {"_type": attr.string(default = str(label))}, toolchains = [label])

runner_probe_x86_64 = _probe("x86_64")
runner_probe_aarch64 = _probe("aarch64")

def _runtime_impl(ctx):
    info = ctx.toolchains[Label("//wine:runner_x86_64_toolchain_type")].windows
    if not info.runtime:
        fail("runtime_probe requires a Wine execution platform")
    out = ctx.actions.declare_file(ctx.label.name + ".json")
    config = ctx.actions.declare_file(ctx.label.name + ".config.json")
    ctx.actions.write(config, json.encode({"backend": "wine", "arch": "x86_64", "loader": info.runtime.loader.path, "server": info.runtime.server.path, "payload": ctx.file.binary.path, "args": ["--output", "{windows_path:" + out.path + "}", "a b", "", "café"]}))
    ctx.actions.run(executable = info.launcher, arguments = ["--config", config.path], inputs = depset([config, ctx.file.binary], transitive = [info.runtime.files]), outputs = [out], toolchain = Label("//wine:runner_x86_64_toolchain_type"), mnemonic = "WineRuntimeProbe")
    return [DefaultInfo(files = depset([out]))]

runtime_probe = rule(implementation = _runtime_impl, attrs = {"binary": attr.label(allow_single_file = True, mandatory = True)}, toolchains = [Label("//wine:runner_x86_64_toolchain_type")])
