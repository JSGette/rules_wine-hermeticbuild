# rules_wine

Run Windows executables as Bazel actions and executable tools. Wine runs
same-CPU payloads on Linux or macOS; Windows actions execute the payload directly.
The rules do not own your compiler, SDK, language, or final output platform.

Bazel 8.5.0 and 9.3.1 are exercised. Initial runtime status:

| Executor / Windows payload | Acquisition | Validation |
| --- | --- | --- |
| Linux x86_64 / x86_64 | Pinned Wine 11.0 default | Remote actions, adapters and lifecycle pass |
| Linux ARM64 / ARM64 | User-supplied native archive | Supervisor cross-compiled; execution untested |
| Windows x86_64 / x86_64 | No Wine required | Direct-action graph verified; execution untested |
| Windows ARM64 / ARM64 | No Wine required | Supervisor cross-compiled; direct-action graph verified; execution untested |
| macOS Intel / x86_64 | User-supplied native archive | Supervisor cross-compiled with local SDK; execution untested |
| macOS ARM64 / ARM64 | User-supplied native archive | Supervisor cross-compiled with local SDK; experimental runtime limitation below |

No Rosetta, QEMU, Box64, FEX, x86 payloads, or cross-CPU fallback. The default Wine
archive contains extra upstream components, but these rules accept only x86_64
and ARM64 PE payload declarations.

## Setup

Until this module is published, consume a checkout through a local override:

```starlark
bazel_dep(name = "rules_wine", version = "0.1.0")
local_path_override(module_name = "rules_wine", path = "../rules_wine")
wine = use_extension("@rules_wine//wine/extension:wine.bzl", "wine")
use_repo(wine, "wine_toolchains")
register_toolchains("@wine_toolchains//:all")
```

Register execution platforms appropriate to your local or remote workers. The
ruleset does not infer remote worker capabilities from the machine running Bazel.
The supervisor is a C++ source target built with the execution-platform compiler.
This module depends on `rules_cc` and `@llvm` and registers `@llvm` C++ toolchains;
downstream builds compile the supervisor on demand.
`@llvm` 0.7.6 uses Bazel APIs unavailable in Bazel 7.7, so this source-built
version requires Bazel 8.5 or newer.
Native Windows registrations have no Wine archive dependency. Archives are fetched
only when referenced.

The default is [Kron4ek Wine 11.0 amd64 WoW64](https://github.com/Kron4ek/Wine-Builds/releases/tag/11.0),
SHA256 `39574efa1132c3ca0d5c77dd2eddbe4a49cca0d6cc2c290ff4924493a1c40314`.
It requires the host glibc ELF interpreter, libc/libdl/libpthread and libgcc_s.
Ubuntu 24.04 console execution was verified; missing FreeType emits warnings.
Other Windows subsystems can require additional host libraries. A pinned archive
is not a fully bundled Linux userspace. See [testing and maintenance](tests/README.md).

## Executable adapters

```starlark
load("@rules_wine//wine:windows_binary.bzl", "windows_binary")

windows_binary(
    name = "generator",
    binary = "generator.exe",
    arch = "x86_64",
    arguments = ["space value", "", "café"],
    data = ["companion.dll"],
)
```

`windows_binary` adapts a Windows executable for `bazel run` or use as a normal
`cfg = "exec"` action tool. Rules that invoke Windows programs directly use
`windows_actions.run`, described below. There is no public output-generation rule
or test adapter.

`binary` accepts one prebuilt PE file or an executable target. No transition is
required for prebuilts. For source-built inputs, optionally set
`target_platform = "//platforms:windows_x86_64"` to transition only the payload
and its `data`; the platform must declare Windows and the same CPU as `arch`.
Your own compiler/toolchain must support that configuration.

`windows_binary` follows its own executable target platform: the host by default,
the consuming executor when used as a `cfg = "exec"` tool. Remote execution
platform registration alone cannot produce a foreign launcher for local
`bazel run`. Explicitly cross-configuring the adapter itself follows normal Bazel
executable semantics; use `target_platform` to cross-configure just its payload.

`arguments` preserves list elements, including empty strings and spaces. `env`,
transitive runfiles and `data` are preserved. Companion files retain their existing
relative layout; DLLs requiring executable adjacency must already be adjacent in
that layout. Adding an unrelated file to `data` does not move it beside the
executable. Arrange generated executable/DLL outputs in the same directory.

Adapter arguments accept `$(location label)` for one declared payload/data file
and `$(locations label)` for multiple files. A standalone plural expression expands
to separate argv elements; an embedded plural must identify one file.
`$(runfile logical/key)` names declared runfiles, including workspace symlinks,
root symlinks and empty entries. The adapter preserves the complete Bazel runfiles
object; locations use logical runfiles keys and convert to Windows paths at runtime.
`$$` escapes a literal dollar. Expansion happens once, so dollars, spaces and braces
inside filenames remain literal. Action output/source variables and arbitrary Make
variables are unsupported.

Locations of executable targets name their executable; other targets expose
their files in sorted path order. Location targets must produce at least one file.
Aliases and configurable arguments are supported on Bazel 8.5 and 9.3. Bazel hides
original alias labels from Starlark; a small compatibility bridge compares complete
native expansions against typed File sets, with no shell parsing. If an alias
ambiguously identifies both an executable and a different output set, reference
the actual canonical target. Standard Bazel runfiles carry repository mappings.
Response-file contents and encoding belong to the payload.

The adapter resolves its own runfiles but does not yet export discovered runfiles
environment variables to the payload. Programs relying on a runfiles library's
automatic discovery can fail when used as action tools. Direct invocation through
`windows_actions.run` with a `FilesToRunProvider` is verified; see the
[adapter limitation](tests/README.md#verification-boundaries).

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

The low-level `windows_actions.path` helper encodes a path as a JSON string inside
`{windows_path:...}` for Wine and returns the ordinary path for native Windows.
This encoding handles braces, quotes and backslashes without delimiter escaping.
Use the helper instead of constructing markers by concatenating strings.
Each wrapped action must have at least one output; its first output identifies
the configuration under the rule's reserved `<name>.wine/` output directory.

Optional Bazel output path mapping is not supported yet. The action helper's JSON
configuration and explicit path helper currently capture execution paths during
analysis. Removing the convenience action/test APIs does not fix those remaining
boundaries. A future implementation can use action-owned `Args` parameter files
and deferred conversion of typed `File` arguments; callers will still own whether
their payloads and outputs are safe to opt in.

The two CPU-specific `windows_binary` rule declarations are intentional: Bazel
8.5 requires static toolchain requirements. Their adapter toolchains match both
executor and target OS/CPU. A configuration setting/transition solely to merge
these declarations would add a public configuration contract. Action helpers use
the runner type declared by the consuming rule; it selects a same-CPU executor
without restricting the final output platform.

## Custom distributions and toolchains

```starlark
wine.prebuilt(
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
use_repo(wine, "wine_toolchains")
register_toolchains("@wine_toolchains//:all")
```

`http_archive` owns download, checksum, mirror retry and extraction. Archive paths
must stay relative. Loader/server must be native ELF or Mach-O executables;
the supervisor checks their CPU headers before launch (no Rosetta fallback).
Shell-script Wine launchers are not accepted. Keep the complete installation layout.

The extension always generates `wine_toolchains`, like `rules_qemu`'s conventional
toolchain repository. It includes pinned Linux x86-64 Wine and native Windows
x86-64/ARM64 registrations. Each `prebuilt` overrides or adds one `exec_os`/`arch`
pair directly; no named distribution sets or `.toolchains(...)` call is needed.
Linux ARM64 and macOS require a custom prebuilt; missing platforms are omitted,
never substituted. A root override takes precedence over dependency declarations
for the same platform. Identical dependency declarations share an archive;
conflicting ones require a root override. Each module may declare a platform only
once. Internal archive names are derived from the executor OS and CPU.

Distribution `env` may supply loader library paths using `{loader_dir}` and
`{server_dir}`, e.g. `DYLD_FALLBACK_LIBRARY_PATH = "{loader_dir}/../../libs"`.
Lifecycle variables such as WINEPREFIX, WINESERVER and WINELOADER are reserved.
The supervisor initializes each private prefix with Wine's `wineboot.exe --init`.
Wine owns lookup of its builtin programs; no distribution-specific DLL directory
is assumed.

For a complete override, define `windows_runner_toolchain` from
`@rules_wine//wine:toolchain.bzl`. A Wine implementation needs `arch`, `backend`,
`launcher`, `loader`, `server`, `files`, `identity`, `requirements`, and `env`; it
can serve runner and binary adapter registrations. Native Windows
uses two implementations: a direct action runner without `launcher` or Wine files,
and an adapter with the source-built launcher but no Wine files. Register each
against `runner_<arch>_toolchain_type` or `adapter_<arch>_toolchain_type` as
appropriate. Both have executor OS/CPU constraints. Runners impose no final-output
constraints; binary adapters additionally have matching target OS/CPU constraints.
`WindowsRunnerInfo` and `WineRuntimeInfo` expose
the advanced contract. `launcher` is an executable dependency in execution
configuration; its FilesToRunProvider and full runfiles are preserved, including
executable targets with sidecar outputs. Runtime
loader/server/files dependencies also use execution configuration.

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
has not been runtime-verified. See [testing and maintenance](tests/README.md) for
the verification commands and platform gaps.

The supervisor is compiled from source for the selected execution platform. No
supervisor binary is checked in. `tests/compile_platforms.sh --config=remote` checks
the six cross-compilation targets; `tests/update_fixtures.sh --config=remote`
rebuilds development-only fixtures, which are not consumer dependencies.

macOS ARM64 requires a compatible native Wine archive. The experimental build
evaluated so far could run its bundled programs but failed independent ARM64
executables outside Bazel too. General external-program execution remains
**unverified**, and no macOS archive is selected by default.
