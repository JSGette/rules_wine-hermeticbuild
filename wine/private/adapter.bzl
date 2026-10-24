"""Implementation of the runfiles-preserving executable adapter."""

load(":paths.bzl", "expand_arguments", "runfile_path")
load(":payload.bzl", "payload", "payload_attrs")
load(":runfiles.bzl", "runfile_entries")

def adapter_impl(ctx):
    """Produce an executable using the default group's adapter toolchain.

    Args:
        ctx: Executable rule context with adapter_attrs.

    Returns:
        DefaultInfo for the native executable and complete runfiles.
    """
    arch = ctx.attr._arch
    adapter_type = Label("//wine:adapter_" + arch + "_toolchain_type")
    runner = ctx.toolchains[adapter_type].windows
    if not runner.launcher:
        fail("adapter toolchain requires an executable launcher")
    binary = payload(ctx, arch)
    executable = ctx.actions.declare_file(ctx.label.name + (".exe" if runner.backend == "native" else ""))
    config = ctx.actions.declare_file(executable.basename + ".json", sibling = executable)
    ctx.actions.symlink(output = executable, target_file = runner.launcher.executable, is_executable = True)
    config_data = {
        "backend": runner.backend,
        "arch": arch,
        "payload": runfile_path(ctx, binary.file),
        "args": expand_arguments(
            ctx,
            ctx.attr.binary + ctx.attr.data,
            runfile_entries = runfile_entries(ctx, binary.runfiles),
        ),
        "env": ctx.attr.env,
        "runfiles": True,
    }
    runtime = []
    if runner.runtime:
        config_data.update({
            "loader": runfile_path(ctx, runner.runtime.loader),
            "runtime_env": runner.runtime.env,
            "server": runfile_path(ctx, runner.runtime.server),
        })
        runtime = [runner.runtime.files]
    ctx.actions.write(config, json.encode(config_data))
    runfiles = ctx.runfiles(
        files = [config, executable, runner.launcher.executable],
        transitive_files = depset(transitive = runtime),
    ).merge_all([binary.runfiles, runner.runfiles])
    return [DefaultInfo(files = depset([executable, config]), executable = executable, runfiles = runfiles)]

def adapter_attrs(arch):
    attrs = payload_attrs()
    attrs.update({
        "_arch": attr.string(default = arch),
        "arguments": attr.string_list(),
        "env": attr.string_dict(),
    })
    return attrs
