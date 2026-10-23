"""Convenience output-producing Windows action."""

load("//wine:actions.bzl", "windows_actions")
load("//wine/private:paths.bzl", "expand_arguments")
load("//wine/private:payload.bzl", "payload", "payload_attrs")
load("//wine/private:runfiles.bzl", "action_runfiles")

def _impl(ctx):
    arch = ctx.attr._arch
    binary = payload(ctx, arch)
    runner = ctx.exec_groups["windows"].toolchains[windows_actions.toolchain_type(arch)].windows
    variables = {"OUTS": ctx.outputs.outs, "SRCS": ctx.files.srcs}
    if len(ctx.outputs.outs) == 1:
        variables["@"] = ctx.outputs.outs
    runfiles = binary.runfiles
    if binary.repo_mapping_manifest:
        runfiles = runfiles.merge(ctx.runfiles(root_symlinks = {"_repo_mapping": binary.repo_mapping_manifest}))
    runtime = action_runfiles(ctx, runfiles, ctx.label.name + ".payload")
    args = ctx.actions.args()
    args.add_all(expand_arguments(
        ctx,
        ctx.attr.srcs + ctx.attr.binary + ctx.attr.data,
        windows = runner.backend == "wine",
        variables = variables,
        runfile_entries = runtime.entries,
    ))
    env = dict(ctx.attr.env)
    env.update({"RUNFILES_DIR": "", "RUNFILES_MANIFEST_FILE": runtime.manifest.path, "RUNFILES_MANIFEST_ONLY": "1"})
    windows_actions.run(
        ctx,
        executable = binary.files_to_run,
        arch = arch,
        arguments = [args],
        inputs = depset(ctx.files.srcs, transitive = [runtime.files]),
        outputs = ctx.outputs.outs,
        env = env,
        exec_group = "windows",
    )
    return [DefaultInfo(files = depset(ctx.outputs.outs))]

def _rule(arch):
    attrs = payload_attrs()
    attrs.update({
        "_arch": attr.string(default = arch),
        "srcs": attr.label_list(allow_files = True),
        "outs": attr.output_list(mandatory = True, allow_empty = False),
        "arguments": attr.string_list(),
        "env": attr.string_dict(),
    })
    return rule(implementation = _impl, attrs = attrs, exec_groups = {"windows": exec_group(toolchains = [windows_actions.toolchain_type(arch)])})

# CPU-specific toolchain requirements are static; final outputs stay in the
# caller's configuration, including when that target has a different CPU.
_x86_64 = _rule("x86_64")
_aarch64 = _rule("aarch64")

def windows_run(name, binary, arch, **kwargs):
    """Run a same-CPU Windows executable; target platform of outputs is unrestricted."""
    if arch not in ["x86_64", "aarch64"]:
        fail("unsupported Windows payload architecture: " + arch)
    (_x86_64 if arch == "x86_64" else _aarch64)(name = name, binary = binary, **kwargs)
