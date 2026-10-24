"""Run Windows executables through Wine on same-CPU Linux/macOS platforms."""

load("//wine/private:adapter.bzl", "adapter_attrs", "adapter_impl")

def _rule(arch):
    return rule(
        implementation = adapter_impl,
        executable = True,
        attrs = adapter_attrs(arch),
        toolchains = [
            Label("//wine:adapter_" + arch + "_toolchain_type"),
            "@hermetic_launcher//launcher:finalizer_toolchain_type",
            "@hermetic_launcher//launcher:template_exec_toolchain_type",
        ],
    )

# Toolchain requirements are static in Bazel 8.5. The CPU-specific type selects
# a same-CPU executor matching the adapter target; the payload may transition.
_x86_64 = _rule("x86_64")
_aarch64 = _rule("aarch64")

def windows_binary(name, binary, arch, **kwargs):
    """Adapt a Windows executable for a non-Windows platform.

    Args:
        name: Adapter target name.
        binary: Executable target or a single prebuilt PE file.
        arch: x86_64 or aarch64, matching the adapter's configured CPU.
        **kwargs: Rule attributes, including the optional payload target_platform.
    """
    if arch not in ["x86_64", "aarch64"]:
        fail("unsupported Windows payload architecture: " + arch)
    (_x86_64 if arch == "x86_64" else _aarch64)(name = name, binary = binary, **kwargs)
