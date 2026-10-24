"""Runfiles-preserving executable adapter with an executor-native launcher."""

load("//wine/private:adapter.bzl", "adapter_attrs", "adapter_impl")

def _rule(arch):
    return rule(
        implementation = adapter_impl,
        executable = True,
        attrs = adapter_attrs(arch),
        toolchains = [Label("//wine:adapter_" + arch + "_toolchain_type")],
    )

# Toolchain requirements are static in Bazel 8.5. The CPU-specific type selects
# a same-CPU executor without constraining the payload/output target platform.
_x86_64 = _rule("x86_64")
_aarch64 = _rule("aarch64")

def windows_binary(name, binary, arch, **kwargs):
    """Wrap a prebuilt or source-built PE; preserve payload/data runfiles."""
    if arch not in ["x86_64", "aarch64"]:
        fail("unsupported Windows payload architecture: " + arch)
    (_x86_64 if arch == "x86_64" else _aarch64)(name = name, binary = binary, **kwargs)
