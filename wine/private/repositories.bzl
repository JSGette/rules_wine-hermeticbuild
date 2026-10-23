"""Registration only; archive extraction belongs to http_archive."""

def _impl(ctx):
    lines = [
        'load("@rules_wine//wine:toolchain.bzl", "windows_runner_toolchain")',
        'package(default_visibility = ["//visibility:public"])',
    ]
    for arch in ["x86_64", "aarch64"]:
        for os in ["windows", "linux", "osx"]:
            key = os + "_" + arch
            repo = ctx.attr.distributions.get(key)
            if os != "windows" and not repo:
                continue
            launcher = "@rules_wine//wine/runtime:supervisor"
            if os == "windows":
                lines.append("windows_runner_toolchain(name = {name}, arch = {arch}, backend = 'native')".format(name = repr(key + "_impl"), arch = repr(arch)))
                lines.append("windows_runner_toolchain(name = {name}, arch = {arch}, backend = 'native', launcher = {launcher})".format(name = repr(key + "_adapter_impl"), arch = repr(arch), launcher = repr(launcher)))
            else:
                lines.append("windows_runner_toolchain(name = {name}, arch = {arch}, backend = 'wine', launcher = {launcher}{runtime})".format(
                    name = repr(key + "_impl"),
                    arch = repr(arch),
                    launcher = repr(launcher),
                    runtime = ', loader = "@{}//:loader", server = "@{}//:server", files = "@{}//:files", identity = {}, requirements = {}, env = {}'.format(repo, repo, repo, repr(ctx.attr.identities.get(key, repo)), repr(ctx.attr.requirements.get(key, "User supplied distribution: host dependencies unverified")), repr(json.decode(ctx.attr.environments.get(key, "{}")))),
                ))
            lines.append('toolchain(name = {name}, toolchain = {impl}, toolchain_type = "@rules_wine//wine:runner_{arch}_toolchain_type", exec_compatible_with = ["@platforms//os:{os}", "@platforms//cpu:{arch}"])'.format(name = repr(key), impl = repr(key + "_impl"), arch = arch, os = os))
            lines.append('toolchain(name = {name}, toolchain = {impl}, toolchain_type = "@rules_wine//wine:adapter_{arch}_toolchain_type", exec_compatible_with = ["@platforms//os:{os}", "@platforms//cpu:{arch}"], target_compatible_with = ["@platforms//os:{os}", "@platforms//cpu:{arch}"])'.format(name = repr(key + "_adapter"), impl = repr(key + ("_adapter_impl" if os == "windows" else "_impl")), arch = arch, os = os))
            lines.append('toolchain(name = {name}, toolchain = {impl}, toolchain_type = "@rules_wine//wine:test_adapter_{arch}_toolchain_type", exec_compatible_with = ["@platforms//os:{os}", "@platforms//cpu:{arch}"])'.format(name = repr(key + "_test_adapter"), impl = repr(key + ("_adapter_impl" if os == "windows" else "_impl")), arch = arch, os = os))
    ctx.file("BUILD.bazel", "\n".join(lines) + "\n")

registration_repository = repository_rule(implementation = _impl, attrs = {
    "distributions": attr.string_dict(),
    "identities": attr.string_dict(),
    "requirements": attr.string_dict(),
    "environments": attr.string_dict(),
})
