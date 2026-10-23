"""Optional compilation transition; never transitions the final output platform."""

PayloadPlatformInfo = provider(fields = ["windows", "arch"])

def _transition_impl(settings, attr):
    return {"//command_line_option:platforms": [attr.target_platform] if attr.target_platform else settings["//command_line_option:platforms"]}

payload_transition = transition(implementation = _transition_impl, inputs = ["//command_line_option:platforms"], outputs = ["//command_line_option:platforms"])

def _check(ctx):
    return [PayloadPlatformInfo(windows = ctx.target_platform_has_constraint(ctx.attr._windows[platform_common.ConstraintValueInfo]), arch = "x86_64" if ctx.target_platform_has_constraint(ctx.attr._x86[platform_common.ConstraintValueInfo]) else ("aarch64" if ctx.target_platform_has_constraint(ctx.attr._arm[platform_common.ConstraintValueInfo]) else "unsupported"))]

payload_platform = rule(implementation = _check, attrs = {
    "_windows": attr.label(default = "@platforms//os:windows"),
    "_x86": attr.label(default = "@platforms//cpu:x86_64"),
    "_arm": attr.label(default = "@platforms//cpu:aarch64"),
})

def payload_attrs():
    return {
        "binary": attr.label(allow_files = True, mandatory = True, cfg = payload_transition),
        "data": attr.label_list(allow_files = True, cfg = payload_transition),
        "target_platform": attr.string(doc = "Optional canonical Windows platform label for source compilation."),
        "_payload_platform": attr.label(default = Label("//wine/private:payload_platform"), cfg = payload_transition),
        "_allowlist_function_transition": attr.label(default = "@bazel_tools//tools/allowlists/function_transition_allowlist"),
    }

def payload(ctx, arch):
    target = ctx.attr.binary[0]
    if ctx.attr.target_platform:
        platform = ctx.attr._payload_platform[0][PayloadPlatformInfo]
        if not platform.windows or platform.arch != arch:
            fail("target_platform must be Windows/{}; got Windows={} CPU={}".format(arch, platform.windows, platform.arch))
    info = target[DefaultInfo]
    executable = info.files_to_run.executable
    if not executable:
        files = info.files.to_list()
        if len(files) != 1:
            fail("binary must be an executable target or exactly one prebuilt PE file")
        executable = files[0]
    data = []
    runfiles = info.default_runfiles.merge(info.data_runfiles)
    for target in ctx.attr.data:
        data.extend(target[DefaultInfo].files.to_list())
        runfiles = runfiles.merge(target[DefaultInfo].default_runfiles).merge(target[DefaultInfo].data_runfiles)
    return struct(file = executable, files_to_run = info.files_to_run if info.files_to_run.executable else executable, data = data, runfiles = runfiles)
