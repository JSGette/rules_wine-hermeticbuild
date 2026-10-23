"""Runfiles-preserving executable adapter with an executor-native launcher."""

load("//wine:actions.bzl", "windows_actions")
load("//wine/private:payload.bzl", "payload", "payload_attrs")

def _rlocation(ctx, file):
    return file.short_path[3:] if file.short_path.startswith("../") else ctx.workspace_name + "/" + file.short_path

def _location_runfiles(ctx, expression, targets, keys):
    expanded = ctx.expand_location("$(" + expression + ")", targets = targets)
    if expanded in keys:
        return expanded, "{windows_runfile:" + keys[expanded] + "}"

    # $(locations) returns space-separated paths; match complete known paths so
    # filenames containing spaces remain one runfile reference.
    result = []
    consumed = 0
    for index in range(len(expanded)):
        if index < consumed:
            continue
        if expanded[index] == " ":
            result.append(" ")
            continue
        match = ""
        for path in keys:
            end = index + len(path)
            if expanded.startswith(path, index) and (end == len(expanded) or expanded[end] == " ") and len(path) > len(match):
                match = path
        if not match:
            fail("location expansion is not a declared payload/data path: " + expanded)
        result.append("{windows_runfile:" + keys[match] + "}")
        consumed = index + len(match)
    return expanded, "".join(result)

def _adapter_arguments(ctx):
    targets = ctx.attr.binary + ctx.attr.data
    keys = {}
    for target in targets:
        info = target[DefaultInfo]
        files = info.files.to_list()
        if info.files_to_run.executable:
            files.append(info.files_to_run.executable)
        for file in files:
            keys[file.path] = _rlocation(ctx, file)
    arguments = []
    for argument in ctx.attr.arguments:
        parts = argument.split("$(")
        result = parts[0]
        for part in parts[1:]:
            expression, separator, tail = part.partition(")")
            if not separator or expression.split(" ", 1)[0] not in ["location", "locations"]:
                result += "$(" + part
                continue
            expanded, converted = _location_runfiles(ctx, expression, targets, keys)
            wrapped = False
            for wrapper in ["{windows_path:", "{windows_runfile:"]:
                if result.endswith(wrapper) and expanded in keys:
                    suffix, close, remainder = tail.partition("}")
                    if close:
                        result = result[:-len(wrapper)] + "{windows_runfile:" + keys[expanded] + suffix + "}"
                        tail = remainder
                        wrapped = True
                        break
            if not wrapped:
                result += converted
            result += tail
        arguments.append(result)
    return arguments

def adapter_impl(ctx):
    arch = ctx.attr._arch
    group = ctx.attr._group
    adapter_type = Label("//wine:" + ("adapter_" if group == "default" else "test_adapter_") + arch + "_toolchain_type")
    runner = ctx.toolchains[adapter_type].windows if group == "default" else ctx.exec_groups[group].toolchains[adapter_type].windows
    if not runner.launcher:
        fail("adapter toolchain requires a launcher")
    binary = payload(ctx, arch)
    suffix = ".exe" if runner.backend == "native" else ""
    executable = ctx.actions.declare_file(ctx.label.name + suffix)
    config = ctx.actions.declare_file(ctx.label.name + suffix + ".json")
    ctx.actions.symlink(output = executable, target_file = runner.launcher, is_executable = True)
    config_data = {
        "backend": runner.backend,
        "arch": arch,
        "payload": _rlocation(ctx, binary.file),
        "args": _adapter_arguments(ctx),
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
