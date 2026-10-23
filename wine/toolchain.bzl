"""Windows runner providers and user-authored toolchain implementation."""

WineRuntimeInfo = provider(fields = {
    "loader": "Wine ELF loader File; installation layout preserved.",
    "server": "Matching wineserver File.",
    "files": "Complete immutable distribution depset.",
    "identity": "Distribution/version provenance.",
    "requirements": "Host library requirements, not inferred hermeticity.",
    "env": "Distribution loader environment; {loader_dir} and {server_dir} placeholders.",
})
WindowsRunnerInfo = provider(fields = {
    "arch": "Same-CPU Windows payload architecture.",
    "backend": "wine or native.",
    "launcher": "Executor-native supervisor/adapter File.",
    "runtime": "WineRuntimeInfo or None.",
})

def _impl(ctx):
    runtime = None
    if ctx.attr.backend == "wine":
        if not ctx.file.loader or not ctx.file.server:
            fail("wine backend requires loader and server")
        runtime = WineRuntimeInfo(
            loader = ctx.file.loader,
            server = ctx.file.server,
            files = depset([ctx.file.loader, ctx.file.server], transitive = [ctx.attr.files[DefaultInfo].files] if ctx.attr.files else []),
            identity = ctx.attr.identity,
            requirements = ctx.attr.requirements,
            env = ctx.attr.env,
        )
    elif ctx.file.loader or ctx.file.server or ctx.attr.files:
        fail("native backend must not depend on Wine")
    info = WindowsRunnerInfo(arch = ctx.attr.arch, backend = ctx.attr.backend, launcher = ctx.file.launcher, runtime = runtime)
    return [info, platform_common.ToolchainInfo(windows = info)] + ([runtime] if runtime else [])

windows_runner_toolchain = rule(
    implementation = _impl,
    attrs = {
        "arch": attr.string(mandatory = True, values = ["x86_64", "aarch64"]),
        "backend": attr.string(mandatory = True, values = ["native", "wine"]),
        "launcher": attr.label(allow_single_file = True, mandatory = True),
        "loader": attr.label(allow_single_file = True),
        "server": attr.label(allow_single_file = True),
        "files": attr.label(),
        "identity": attr.string(),
        "requirements": attr.string(),
        "env": attr.string_dict(),
    },
)
