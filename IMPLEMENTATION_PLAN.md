# rules_wine implementation plan

Status: initial implementation reviewed and merged into main. This document
preserves the design plan; see [testing and maintenance](tests/README.md) for
current verification commands and unverified platform boundaries.

Scope amendment (2026-10-24): `windows_run` and `windows_test` were removed.
The supported APIs are `windows_binary` and `windows_actions`; the corresponding
sections below describe the original design, not current public APIs. Optional
path mapping remains a separate implementation step.

Architecture amendment: `windows_binary` now has one `adapter_toolchain_type` and
no `arch` argument. Platform constraints select the implementation; its `arch`
metadata supplies the runtime configuration and validates an optional Windows
payload platform. Fixed-CPU prebuilts declare `target_compatible_with`. The
architecture-specific runner types and `windows_actions` API remain unchanged.
The original explicit-architecture adapter design below is superseded.

### Path mapping reassessment after removal

The removal eliminates the custom action runfiles manifest, source/output argument
expansion, and separate test-adapter toolchains. `windows_binary` already stores
logical runfiles keys in its configuration, so it does not need configuration-prefix
rewriting. Its action callers still need to preserve typed paths in runtime arguments.
The independent adapter discovery gap is addressed by using the `rules_cc`
runfiles library and forwarding its `EnvVars()` to the payload. A source-built
Windows program verifies repository mapping and alias-only data through the
adapter. This is independent of path mapping.

Two boundaries remain in `windows_actions`:

1. The Wine configuration is a separately written JSON file containing analysis-time
   execution paths. Replace it with an action-owned `Args` parameter file, serializing
   typed `File` fields through `map_each` when Bazel expands that action's arguments.
2. `windows_actions.path` returns a string immediately. Replace or supplement it with
   an API that adds a typed `File` to `Args`, deferring Windows marker encoding until
   argument expansion. Ordinary strings must remain opaque.

This follows [Bazel's path-mapping guidance](https://github.com/bazelbuild/bazel/discussions/22658).
Use the action's parameter-file transport on both supported versions: Bazel 8.5's
[standalone parameter-file write action](https://github.com/bazelbuild/bazel/blob/8.5.0/src/main/java/com/google/devtools/build/lib/analysis/actions/ParameterFileWriteAction.java)
uses `PathMapper.NOOP`. A separate write action is therefore not the portable fix.
No manually rewritten `bazel-out` prefix, configuration name, or collision logic
belongs in this ruleset.

Earlier isolated experiments on 8.5.0 and 9.3.1 verified action-owned JSON parameter
files with mapping on/off, typed generated paths, executable runfiles, and automatic
fallback for conflicting mapped inputs. They did not verify a complete Wine fix.
The action helper is unchanged by this removal and remains unsupported for mapping.

Keep opt-in with the consuming action's `supports-path-mapping` execution requirement
and the user's `--experimental_output_paths=strip` flag. Consumers own their tools'
output semantics. Environment strings and payload-owned response-file contents are
not typed paths; do not guess or rewrite them. A future implementation must verify
real Wine execution, generated inputs/outputs, mapped/unmapped fallback, executable
runfiles and unchanged native Windows direct dispatch on Bazel 8 and 9. Cross-
configuration cache reuse and native Windows runtime behavior remain unproven.

Scope amendment (2026-10-23): user added native macOS execution and explicitly
rejected Rosetta. Darwin x86_64/ARM64 custom-runtime support is implemented; no
public ARM64 tar default is invented. The researched experimental native ARM64
runtime runs its shipped cmd but rejects independent payloads; see tests/README.md.
Date: 2026-10-23.

## 1. Purpose and design contract

Provide versatile Windows execution in Bazel: build actions, executable adapters,
and tests. Wine implements this contract on Linux; Windows executes the payload
natively. Keep the public surface small and composable, following rules_qemu.

The ruleset accepts executables. It does not own their compiler, SDK, language,
or application-specific behavior. No production dependency on @llvm, Windows
SDKs, mt.exe, or manifest processing. LLVM may be a development dependency for
building test fixtures or maintaining the ruleset's own native support binaries.

The execution contract is:

- Select the backend from the actual action/test execution platform.
- Execute a Windows payload of the same CPU architecture as that executor.
- Declare the executable, companion files, runtime, and configuration as inputs.
- Preserve arguments, working-directory semantics, output handling, and failure
  reporting as far as the host execution interface permits.
- Give each Wine invocation private writable state; do not modify inputs.
- Run directly on Windows when no adapter is necessary.

Wine does not require QEMU for these supported combinations. Cross-compiling a
Windows executable on Linux is allowed; translating instructions between CPU
architectures is out of scope.

## 2. Accepted scope

| Executor | Payload | Backend | Initial validation |
| --- | --- | --- | --- |
| Linux x86_64 | Windows x86_64 | x86_64 Wine | Execution tests required |
| Windows x86_64 | Windows x86_64 | Direct | Execution tests required |
| Linux ARM64 | Windows ARM64 | ARM64 Wine | Implement; execution untested initially |
| Windows ARM64 | Windows ARM64 | Direct | Implement; execution untested initially |

Use architecture-correct binaries for Wine, its Unix dependencies, and any
supervisor or launcher. Never substitute x86_64 Wine on ARM64. Native ARM64 Wine
support does not imply support for x86_64 Windows applications.

Defer x86/32-bit payloads, CPU translation, GUI integration,
prepared prefixes, persistent Wine sessions, and an owned wine-prebuilt project.
Research stronger isolation later; prefix isolation is not a security sandbox.

Third-party Wine builds may require host glibc initially. Document the verified
baseline and any other required host libraries per distribution. Do not claim
complete userspace hermeticity merely because the archive is checksum-pinned.

## 3. Reference implementation

Inspect and reuse patterns from rules_qemu revision
`3d083d5f2f1261a0e1b80d6187d6089a0f4038ed`:

- `qemu/extension/qemu.bzl`: pinned http_archive repositories and extension metadata.
- `qemu/declare_toolchains.bzl`: execution-platform-specific registrations.
- `qemu/qemu_binary.bzl`: explicit payload transition and native launcher/runfiles.
- `e2e/smoke`: external-consumer installation and behavior checks.

Do not copy its Linux-only backend assumptions or treat its no-remote user-mode
smoke tests as evidence of remote execution support. Aim to retain its Bazel
7.7 minimum where the required APIs permit; test the minimum plus Bazel 8 and 9.
Any necessary minimum-version increase must be justified before committing to it.

## 4. Public interfaces

Names below describe the intended API; signatures are provisional until the
small analysis prototype confirms configuration and execution-group behavior.

### windows_binary

Create a runnable adapter around a Windows executable and its declared runtime
files. Support source-built executable targets and prebuilt executable files.

- `binary`: executable target or prebuilt Windows executable.
- `arch`: explicit payload architecture, x86_64 or aarch64.
- `target_platform`: optional Windows compilation platform for source-built inputs.
- `args`, `env`, `data`: declared invocation arguments, environment, and runtime files.

If target_platform is omitted, consume the supplied executable configuration.
If supplied, transition the payload and configuration-dependent payload data,
not the runner, to that platform. Validate the requested Windows OS and CPU;
require consistency with arch. A prebuilt does not require this transition.

Preserve transitive runfiles and executable metadata. DLLs requiring adjacency
to the executable need an explicit layout contract; adding them to an arbitrary
runfiles directory is not sufficient.

Local bazel run and use as an action tool are distinct contexts. A top-level
local-run facade must select a runtime for the local host; when consumed as an
exec-configured tool, the adapter must match the consuming action's executor.
Do not select an arbitrary remote execution platform and emit a launcher that
bazel run then tries to execute locally. Prove this with a host/executor mismatch
analysis scenario before finalizing the adapter's transitions.

### windows_test

Execute a Windows test payload with Bazel test semantics: arguments, environment,
runfiles, sharding variables, writable test directories, and result-file paths.
Use the same payload attributes and runtime implementation as windows_binary.

Resolve the runner through an explicit test execution group. On Bazel 9, the
default rule execution group does not configure the test action. Compile or
select the launcher for the resolved test executor, even if launcher-generation
actions run elsewhere. Account for this on older supported Bazel versions too.

A scheduler-only default test toolchain does not insert Wine into arbitrary
cc_test commands. Initial support is the explicit windows_test adapter. Wrapping
an existing test must preserve the relevant test environment/providers where
applicable; do not promise automatic coverage integration in the first version.

### windows_run

Convenience rule for actions with explicit inputs, outputs, executable, arguments,
environment, runtime data, payload architecture, and optional payload transition.
Reuse the Starlark action helper; do not implement another runner lifecycle.

### windows_actions.run

Low-level helper for other rule authors. Accept FilesToRunProvider where available,
declared runtime files, Args objects, inputs/outputs, environment, mnemonic, and an
execution group. Preserve lazy argument construction and parameter-file support.

On Windows, register the payload itself as the action executable. On Linux,
register the supervisor and pass the payload plus immutable runtime configuration.
Declare the toolchain/exec_group association explicitly so automatic execution
groups cannot schedule the action against the wrong backend.

Provide a documented way to declare the required runner toolchain type when
defining a consumer rule. The helper cannot add toolchain requirements afterward.

## 5. Toolchain and provider model

Separate these concepts throughout the implementation:

1. The executor OS/CPU, which chooses native execution or Wine.
2. The Windows payload OS/CPU, which determines what can be executed.
3. The final output platform, which may be unrelated to the payload.

A Windows code generator can generate Linux output. An x86_64 Windows tool can
process ARM64 output files. Never constrain a generic action runner by the final
output platform as a proxy for the tool's architecture.

Use architecture-specific runner toolchain requirements internally, such as
runner_x86_64_toolchain_type and runner_aarch64_toolchain_type. Each type has
Linux/Wine and Windows/native implementations with matching exec constraints.
This lets Bazel select the right executor before analysis of the action, without
requiring both CPU toolchains simultaneously. Public macros can dispatch to the
appropriate private rule variant using the explicit arch attribute.

Keep these toolchains free of final-output target OS/CPU constraints. Validate
payload metadata separately. Explicitly transitioned source payloads can use a
companion platform-validation target in the same configuration; prebuilts carry
an explicit architecture declaration, with executable-header checks in validation.

Proposed runner provider data:

- backend: native or wine; supported payload architecture.
- supervisor: optional File built for the selected executor.
- wine runtime: loader, server, complete files depset, layout/configuration data.
- immutable distribution identity and environment defaults.
- documented runtime requirements and version metadata.

Native toolchains have no Wine runtime dependency. Also expose a Wine-specific
provider/toolchain rule for advanced consumers and custom distributions; the
generic action/test API should not require reading Wine implementation details.
The native action runner has no supervisor dependency. Executable adapters use a
separate source-built supervisor toolchain; tests select an adapter through their
test execution group without target-platform constraints.

## 6. Module extension and runtime acquisition

Use Bazel's http_archive implementation. Do not implement archive download,
checksum verification, extraction, or mirror retry logic independently.

Provide a simple default setup plus named custom distributions. Proposed tags:

- `wine.prebuilt(...)`: name, executor CPU, urls, integrity or sha256,
  strip_prefix, and runtime layout (loader/server paths and runtime file patterns).
- `wine.toolchains(...)`: assemble a named registration repository from the
  selected per-architecture distributions, including native Windows toolchains.

Generate BUILD files around the extracted layout; preserve relative directory
relationships. Restrict archive paths to the repository and reject conflicting
checksum fields, missing required metadata, and unsupported architectures early.
Keep arbitrary custom launch behavior in user-authored toolchain implementations.

Publish a pinned default x86_64 distribution after the runtime probe succeeds.
The researched bootstrap candidate is Kron4ek Wine 11.0 amd64 WoW64:

- URL: https://github.com/Kron4ek/Wine-Builds/releases/download/11.0/wine-11.0-amd64-wow64.tar.xz
- SHA-256: `39574efa1132c3ca0d5c77dd2eddbe4a49cca0d6cc2c290ff4924493a1c40314`
- strip_prefix: `wine-11.0-amd64-wow64`

Do not present that archive as an ARM64 distribution. Find and inspect a native
ARM64 artifact independently. If no acceptable default is available, implement
ARM64 custom-URL support and document that a user-supplied distribution is needed;
do not advertise turnkey default ARM64 Wine or invent download URLs.

Extension evaluation must not detect the local OS to decide remote toolchains.
Declare repositories for configured distributions and let Bazel fetch referenced
artifacts lazily. Verify a native Windows consumer does not fetch Wine.

Support multiple named distributions without ambiguous global version selection.
Use module-qualified identities internally; reject conflicting declarations in
one namespace. Consumers explicitly register the selected toolchains. A root
module can select its own archive and registration instead of the defaults.

Allow direct user-authored toolchains independently of the extension. Document
both the simple custom-URL route and the complete toolchain override route.

## 7. Wine execution lifecycle

Build one C++ supervisor from source in the selected execution configuration for
Linux, macOS, and Windows. Keep shell utilities, Python, and machine-installed Wine
out of the production execution path. `@llvm` and `rules_cc` are production
dependencies; downstream adapter/Wine builds compile the supervisor on demand.
Native build actions execute their PE directly and need no supervisor.

The adapter uses `rules_cc` for runfiles discovery, manifest parsing and environment
forwarding. Its own entrypoint retains the Wine environment and path-conversion
contract.

For each invocation:

1. Resolve declared runtime paths and payload files; establish the working directory.
2. Create private writable scratch and prefix directories in an allowed location.
3. Construct the environment explicitly, including home/cache/temp locations,
   deterministic locale/timezone policy, and declared DLL search paths.
4. Initialize the prefix without interactive or network-fetched components.
5. Start the payload, forward standard streams, wait, and retain its result.
6. On success, failure, or cancellation, stop and reap invocation-owned processes.
7. Remove owned scratch state without touching declared inputs or unrelated prefixes.

Preserve the runtime installation layout. Audit Wine's actual executable lookup:
an environment variable alone is not proof that every child uses the pinned binary.
No shared mutable prefix; no automatic Mono/Gecko downloads or winetricks installs.

Define cancellation and cleanup timeouts. Scope server termination to this prefix.
Do not let cleanup failures replace the original payload failure silently. Define
POSIX exit-code mapping and retain diagnostics for Windows codes that cannot be
represented losslessly in a Unix process exit status.

Convert only declared paths, including test output/environment paths when needed.
Avoid generic slash replacement in arguments: options and opaque values are not
paths. Support embedded path options through explicit formatting helpers. Treat
response-file content/encoding as a consumer contract, with tested common cases.

Preserve or materialize the layout needed by Windows runfiles libraries; Linux
runfiles environment values cannot simply be assumed usable by Windows code.

## 8. Implementation sequence and review boundaries

Historical planning context: the repository was created for this implementation.
The three layers below were implemented, reviewed, and merged into main.

The acceptance lists below remain the intended validation criteria, not a claim
that every platform has executed. tests/README.md records verification commands and the
explicit native Windows, ARM64, and experimental macOS limits.

1. **Runtime toolchains and acquisition** — extension, providers, native/Wine
   registrations, architecture modeling, and an executable runtime probe.
2. **Actions and executable adapters** — native supervisor, common action API,
   windows_run, windows_binary, transitions, and declared runtime layout.
3. **Test adapter and consumer validation** — windows_test, execution-group
   integration, end-to-end examples, compatibility matrix, and user documentation.

Use gh stack non-interactively after approval; draft submissions only. Each layer
must meet its focused acceptance criteria before building the next. If the runtime
probe reveals a packaging blocker, resolve it before expanding the public APIs.
The plan is not authorization to publish branches, releases, or PRs.

### Layer 1 acceptance

- URL overrides, checksum failures, archive layouts, and registration are exercised.
- Linux/Windows and x86_64/ARM64 toolchain resolution is inspected with cquery.
- Unsupported pairs fail clearly; no fallback to a different CPU.
- Native toolchain use does not pull Wine into the dependency closure.
- Inspect downloaded ELF/PE architectures and runtime dependencies, including ARM64
  artifacts when supplied; distinguish artifact inspection from execution testing.
- On Linux x86_64, run a small independent Windows executable and child process
  from a relocated runtime. Record actual host library requirements.

### Layer 2 acceptance

- A Windows code generator writes declared outputs through Wine and natively.
- Generated artifacts are inspected, not merely action exit status.
- Inspect aquery: selected executable, platform, tools, inputs, environment, outputs.
- Exercise source-built transitions and prebuilt payloads independently.
- A Windows generator can serve a Linux-targeted consumer.
- Cover DLL loading, data/runfiles, spaces/Unicode, empty arguments, response files,
  working directories, nonzero exits, missing dependencies, and child processes.
- Concurrent invocations do not share registry/files or terminate each other's server.
- Cancellation terminates descendants; read-only inputs remain unchanged.
- A local-run facade remains host-runnable with remote execution platforms registered.

### Layer 3 acceptance

- Tests run through the runner selected by the test execution group.
- Validate temp/output directories, XML output, sharding variables, and timeouts.
- External-consumer smoke module uses the documented setup and a custom archive.
- LLVM builds the production supervisor; fixture compilers stay test-only. Inspect
  the downstream consumer graph for a source-built executor-native supervisor.
- Exercise the supported Bazel minimum and newer test-resolution behavior.
- Run sandboxed Linux and native Windows x86_64 tests; run at least one remote
  Linux action/test and inspect outputs and cache reuse before claiming RBE support.
- ARM64 analysis/packaging paths exist, with execution explicitly marked untested.

Prefer small behavioral fixtures over implementation-mirroring tests. A fixture
that writes files, loads a DLL, and launches a child is more useful than treating
Wine's own cmd.exe as the only payload. Neither mt.exe nor an SDK is an acceptance
requirement. Request approval before creating/editing public README documentation,
as required by the supplied AGENTS.md.

## 9. Known limitations and follow-up research

- No CPU translation, including x86_64-on-ARM64 and ARM64-on-x86_64.
- ARM64 execution initially untested; default prebuilt availability unresolved.
- Host glibc and any audited distribution dependencies remain initial requirements.
- No general Windows compatibility guarantee; Wine behavior depends on the program.
- Fresh prefixes isolate mutable Wine state but do not isolate all host resources.
- Research stronger filesystem/process/network isolation, wineserver sockets/shared
  memory, cancellation under sandboxing, and worker-specific restrictions later.
- Research prepared immutable prefix seeds and startup-cost optimization later;
  preserve the no-shared-mutable-state contract.
- Defer owned Wine builds, a fully bundled Unix runtime, GUI/.NET profiles, coverage
  integration, persistent workers, and additional execution operating systems.
- Record unverified remote/platform behavior explicitly; a successful analysis is
  not evidence that the corresponding executable runs.

## 10. Evidence and sources

- [rules_qemu reference revision](https://github.com/hermeticbuild/rules_qemu/tree/3d083d5f2f1261a0e1b80d6187d6089a0f4038ed)
- [Kron4ek distribution requirements and build recipes](https://github.com/Kron4ek/Wine-Builds)
- [Wine 11.0 archive release](https://github.com/Kron4ek/Wine-Builds/releases/tag/11.0)
- [Wine prefix and environment documentation](https://github.com/wine-mirror/wine/blob/wine-11.0/tools/wine/wine.man.in)
- [Wine server lifecycle](https://github.com/wine-mirror/wine/blob/wine-11.0/server/wineserver.man.in)
- [Wine loader and child execution paths](https://github.com/wine-mirror/wine/blob/wine-11.0/dlls/ntdll/unix/loader.c)
- [Bazel toolchain configuration](https://bazel.build/extending/toolchains)
- [Bazel execution groups](https://bazel.build/extending/exec-groups)
- [Bazel test execution contract](https://bazel.build/reference/test-encyclopedia#execution-platform)
- [Bazel 9 migration changes](https://github.com/bazelbuild/bazel/releases/tag/9.0.0)
- [Hermetic launcher](https://github.com/hermeticbuild/hermetic-launcher)
- [Existing Wine wrapper precedent](https://github.com/JSGette/rules_wine/tree/6c4fbfcd9387bbeb0b49ba5df09c85b659d27813)

Prior research verified the Kron4ek archive checksum and inspected its loader,
wineserver, and ntdll ELF dependencies. These require the system ELF interpreter
and Unix libraries; ntdll also requires libgcc_s. That inspection did not execute
Wine. No runtime, remote-execution, or ARM64 success is implied by this plan.
