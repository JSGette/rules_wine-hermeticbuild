# rules_wine

Run Windows executables as Bazel actions, executable tools, and tests. Wine runs
same-CPU payloads on Linux or macOS; Windows actions execute the payload directly.
The rules do not own your compiler, SDK, language, or final output platform.

Bazel 7.7.0, 8.5.0 and 9.3.1 are exercised. Initial runtime status:

| Executor / Windows payload | Acquisition | Validation |
| --- | --- | --- |
| Linux x86_64 / x86_64 | Pinned Wine 11.0 default | Remote actions/tests and lifecycle pass |
| Linux ARM64 / ARM64 | User-supplied native archive | Configuration implemented; execution untested |
| Windows x86_64 / x86_64 | No Wine required | Direct-action graph verified; execution untested |
| Windows ARM64 / ARM64 | No Wine required | Configuration implemented; execution untested |
| macOS Intel / x86_64 | User-supplied native archive | Configuration implemented; execution untested |
| macOS ARM64 / ARM64 | User-supplied native archive | Experimental runtime limitation; see below |

No Rosetta, QEMU, Box64, FEX, x86 payloads, or cross-CPU fallback. The default Wine
archive contains extra upstream components, but these rules accept only x86_64
and ARM64 PE payload declarations.

## Setup

Until this module is published, consume a checkout through a local override:

```starlark
bazel_dep(name = "rules_wine", version = "0.1.0")
local_path_override(module_name = "rules_wine", path = "../rules_wine")
wine = use_extension("@rules_wine//wine/extension:wine.bzl", "wine")
wine.toolchains(name = "wine_toolchains", x86_64 = "default")
use_repo(wine, "wine_toolchains")
register_toolchains("@wine_toolchains//:all")
```

Register execution platforms appropriate to your local or remote workers. The
ruleset does not infer remote worker capabilities from the machine running Bazel.
Native-only Windows consumers can omit `x86_64 = "default"`; native registrations
then have no Wine archive dependency. Archives are fetched only when referenced.

The default is [Kron4ek Wine 11.0 amd64 WoW64](https://github.com/Kron4ek/Wine-Builds/releases/tag/11.0),
SHA256 `39574efa1132c3ca0d5c77dd2eddbe4a49cca0d6cc2c290ff4924493a1c40314`.
It requires the host glibc ELF interpreter, libc/libdl/libpthread and libgcc_s.
Ubuntu 24.04 console execution was verified; missing FreeType emits warnings.
Other Windows subsystems can require additional host libraries. A pinned archive
is not a fully bundled Linux userspace. See [validation evidence](VALIDATION.md).

## Actions, binaries and tests

```starlark
load("@rules_wine//wine:windows_run.bzl", "windows_run")
load("@rules_wine//wine:windows_binary.bzl", "windows_binary")
load("@rules_wine//wine:windows_test.bzl", "windows_test")

windows_run(
    name = "generated",
    binary = "generator.exe",
    arch = "x86_64",
    srcs = ["schema.txt"],
    outs = ["generated.txt"],
    arguments = ["--output", "{windows_path:$@}", "{windows_path:$(location schema.txt)}"],
)
windows_binary(
    name = "generator",
    binary = "generator.exe",
    arch = "x86_64",
    arguments = ["space value", "", "café"],
    data = ["companion.dll"],
)
windows_test(
    name = "unit_test",
    binary = "unit_test.exe",
    arch = "x86_64",
    arguments = ["--mode", "test"],
    env = {"TEST_MODE": "unit"},
    shard_count = 2,
)
```

`binary` accepts one prebuilt PE file or an executable target. No transition is
required for prebuilts. For source-built inputs, optionally set
`target_platform = "//platforms:windows_x86_64"` to transition only the payload
and its `data`; the platform must declare Windows and the same CPU as `arch`.
Your own compiler/toolchain must support that configuration. `windows_run`'s final
output configuration can be Linux, ARM64, or any other unrelated platform.

`windows_binary` follows its own executable target platform: the host by default,
the consuming executor when used as a `cfg = "exec"` tool. Remote execution
platform registration alone cannot produce a foreign launcher for local
`bazel run`. Explicitly cross-configuring the adapter itself follows normal Bazel
executable semantics; use `target_platform` to cross-configure just its payload.

`arguments` preserves list elements, including empty strings and spaces. Tests
also accept standard Bazel `args` and `--test_arg` with normal Bazel tokenization.
`env`, transitive runfiles and `data` are preserved. Companion files retain their
existing relative layout; DLLs requiring executable adjacency must already be
adjacent in that layout. Merely adding an unrelated file to `data` does not move
it beside the executable. Arrange source-generated executable/DLL outputs in the
same directory. This iteration does not automatically forward arbitrary wrapped
test providers or instrument coverage; wrap a test executable explicitly.

Path conversion is explicit: `{windows_path:execroot/relative/path}` converts only
that path to Wine's `Z:` namespace, leaving options and opaque strings intact.
Embedded options work, e.g. `/out:{windows_path:$@}`. For adapter runfiles use
`{windows_runfile:_main/package/file}` (or the external canonical runfiles key).
Response-file contents and encoding belong to the payload; UTF-8 fixture content
and Args parameter-file transport are exercised. Do not rewrite every slash.

Tests receive Bazel sharding variables, writable `TEST_TMPDIR`, result paths,
runfiles paths, and XML output paths; Wine converts only declared test-protocol
paths. On Bazel 9, constrain the actual test executor with
`exec_group_compatible_with = {"test": [...]}`; the launcher is selected from that
same `test` group. Older Bazel versions inherit default test constraints.

## Other rule authors

```starlark
load("@rules_wine//wine:actions.bzl", "windows_actions")

def _impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".txt")
    response = ctx.actions.args()
    response.add_all(["opaque value", "café"])
    response.use_param_file("@%s", use_always = True)  # Only if your tool supports it.
    response.set_param_file_format("multiline")
    windows_actions.run(
        ctx,
        executable = ctx.attr.tool[DefaultInfo].files_to_run,
        arch = "x86_64",
        arguments = [
            "--output",
            windows_actions.path(ctx, out, arch = "x86_64", exec_group = "windows"),
            response,
        ],
        outputs = [out],
        exec_group = "windows",
    )
    return [DefaultInfo(files = depset([out]))]

my_rule = rule(
    implementation = _impl,
    attrs = {"tool": attr.label(executable = True, cfg = "exec")},
    exec_groups = {"windows": exec_group(toolchains = [windows_actions.toolchain_type("x86_64")])},
)
```

Declare the toolchain type on the group before calling the helper. A native
Windows action uses the payload's FilesToRunProvider directly; Wine uses its
supervisor, config and complete distribution as declared inputs. `inputs` accepts
a list or depset; `runtime_files`, outputs, environment, mnemonic and additional
`ctx.actions.run` keyword arguments are supported. Args stay lazy. Explicit path
markers inside a response file are not interpreted by the supervisor; use
payload-native relative paths or format response content in the consumer rule.

## Custom distributions and toolchains

```starlark
wine.prebuilt(
    name = "my_arm64",
    arch = "aarch64",
    exec_os = "linux",  # "osx" for native macOS Wine.
    urls = ["https://your-artifact-store/wine-arm64.tar.xz"],
    sha256 = "<actual archive sha256>",  # Or integrity, exactly one.
    strip_prefix = "wine-arm64",
    loader = "bin/wine",
    server = "bin/wineserver",
    files = ["**"],
    identity = "your Wine build and revision",
    requirements = "your audited host dependency baseline",
)
wine.toolchains(name = "my_toolchains", aarch64 = "my_arm64")
use_repo(wine, "my_toolchains")
register_toolchains("@my_toolchains//:all")
```

`http_archive` owns download, checksum, mirror retry and extraction. Archive paths
must stay relative. Loader/server must be native ELF or Mach-O executables;
the supervisor checks their CPU headers before launch (no Rosetta fallback).
Shell-script Wine launchers are not accepted. Keep the complete installation layout. Named distributions
are module-local; generated distribution identities are module-qualified.
Registration repository names must be globally unique across users of the same
extension. Select `x86_64`, `aarch64`, `macos_x86_64`, and `macos_aarch64`
independently; absent Linux/macOS entries are omitted, never substituted.

Distribution `env` may supply loader library paths using `{loader_dir}` and
`{server_dir}`, e.g. `DYLD_FALLBACK_LIBRARY_PATH = "{loader_dir}/../../libs"`.
Lifecycle variables such as WINEPREFIX, WINESERVER and WINELOADER are reserved.
The supervisor initializes through a distribution-relative builtin cmd.exe when
available, falling back to Wine's builtin lookup for other layouts.

For a complete override, define `windows_runner_toolchain` from
`@rules_wine//wine:toolchain.bzl` with `arch`, `backend`, `launcher`, and for Wine
`loader`, `server`, `files`, `identity`, `requirements`, `env`. Register it against
`@rules_wine//wine:runner_<arch>_toolchain_type` with executor OS/CPU constraints
and **no final-output target constraints**. For executable adapters also register
`adapter_<arch>_toolchain_type` against the same implementation, with matching
executor and adapter-target OS/CPU constraints. Native overrides omit all Wine
files. `WindowsRunnerInfo` and `WineRuntimeInfo` expose the advanced contract.

## Isolation, runtime maintenance and limits

Each invocation creates a private prefix, home/cache/temp directories and a fresh
Wine server. Mono/Gecko and menu-builder integration are disabled. The pinned
loader/server paths are explicit. Initial setup has a 60-second deadline;
prefix-scoped server stop/wait each have a 5-second deadline. Linux cancellation
kills the payload process group, stops the owned server, reaps children, then
removes scratch state. Cleanup errors are reported without replacing the payload
result. Exit statuses 0–255 pass through on Unix; signals use 128+signal. Wine's
CLI can truncate full Windows statuses before the Unix supervisor receives them;
lossless full Windows exit reporting is not supplied. Native Windows actions
retain the native process interface; native adapters retain the native status.

Prefix isolation is not a security sandbox. No shared/prepared prefixes,
winetricks, machine Wine, shell utilities or Python are in the production runtime.
Stronger filesystem/process/network isolation, immutable prefix seeds, GUI/.NET,
coverage and workers remain future work. Windows adapter descendant cancellation
has not been runtime-verified. See VALIDATION.md for exact tested boundaries.

Support binaries are checked in for Linux, Windows and macOS, x86_64 and ARM64.
Downstream builds need no compiler. Maintenance uses Go 1.25.3 and no third-party
Go modules: `tools/build_runtime.sh /absolute/path/to/go`; SHA256SUMS records the
bytes. `tools/build_fixtures.sh` builds development-only payloads with Go and
clang/lld; these tools never become consumer dependencies.

Native macOS ARM64 Wine exists experimentally. A signed DiagBridge runtime
([v0.2.5](https://github.com/citi94/diagbridge/releases/tag/v0.2.5)) ran its shipped
ARM64 cmd.exe on macOS26.5.2 without Rosetta. Independent ARM64 Go and minimal
no-CRT payloads failed or hung in the same runtime, including raw unwrapped
reproductions. The custom macOS backend is implemented; general external-payload
execution is **not validated** with this distribution. Upstream ships a DMG, so
there is no invented public tar default: supply an appropriately licensed,
compatible native archive yourself. No signing/security settings are changed.
