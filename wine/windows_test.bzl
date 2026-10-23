"""Explicit Windows test adapter, using the actual test execution group."""

load("//wine/private:adapter.bzl", "adapter_attrs", "adapter_impl")

def _rule(arch):
    return rule(implementation = adapter_impl, test = True, attrs = adapter_attrs(arch, "test"), exec_groups = {"test": exec_group(toolchains = [Label("//wine:test_adapter_" + arch + "_toolchain_type")])})

_x86_64_test = _rule("x86_64")
_aarch64_test = _rule("aarch64")

def windows_test(name, binary, arch, **kwargs):
    """Preserve Bazel test args/env, sharding and writable result paths.

    Wine paths are converted only for the test protocol and explicit path
    interpolation. Automatic coverage instrumentation is not provided.
    """
    if arch not in ["x86_64", "aarch64"]:
        fail("unsupported Windows payload architecture: " + arch)
    (_x86_64_test if arch == "x86_64" else _aarch64_test)(name = name, binary = binary, **kwargs)
