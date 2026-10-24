# Testing and maintenance

Run from the repository root. The `remote` config uses a native Linux x86_64
BuildBuddy executor with Ubuntu 24.04; authentication belongs in your user config.
For a native local Linux worker, omit `--config=remote`.

## Behavior checks

```sh
bazel test //tests:integration --config=remote
bazel build //tests:generate //tests:adapter_tool \
  //tests:param_file \
  //tests:additional_tools //tests:default_group //tests:default_group_tools \
  //tests:external_tools //tests:distinct_actions \
  --config=remote
bazel test //tests:argv_test --config=remote --noenable_runfiles
```

These use independent Windows executables to check output generation, DLL loading,
child processes, argument preservation, and generated/external data. The lifecycle
test checks concurrent private
prefixes, cancellation ownership, descendant cleanup, exit status, architecture
rejection, and unchanged input files. The layout test creates real symlinks because
remote execution can materialize ordinary runfiles and hide local layout bugs.
The argv regression passes arguments through the generated launcher and asserts
exact records for spaces, empty strings, Unicode, literal dollar/location strings,
opaque options and leading `--config`/`--` arguments. Invocation arguments belong
to the consumer; the adapter has no expression-expansion API. A source-built
Windows consumer uses the standard C++ runfiles
library through `windows_actions.run` with its `FilesToRunProvider` to verify
apparent-repository mapping and alias-only runfiles. Bazel supplies the runfiles
layout; the ruleset does not write a replacement manifest.

Inspect the generated JSON files as well as the test results. Use `bazel aquery`
to inspect executables, platforms, declared tools and inputs. Native actions must
invoke the PE directly without Wine inputs:

```sh
bazel aquery //tests:generate --config=remote \
  --extra_execution_platforms=//platforms:windows_x86_64
```

## Consumers and Bazel versions

```sh
(cd e2e/smoke && bazel build //:generate --config=remote)
jq -e '.args | index("external-consumer") != null' e2e/smoke/bazel-bin/external.json
jq -e '.args | index("adapter-consumer") != null' e2e/smoke/bazel-bin/adapter.json
e2e/test_custom_archive.sh /absolute/path/to/wine-11.0-amd64-wow64.tar.xz SHA256
e2e/test_starlark.sh
e2e/test_extension.sh
```

The consumer exercises the public module setup, action helper and binary adapter.
The script tests a custom
archive through `http_archive`; supplying an incorrect checksum must fail fetching.
Keep fixture compilers and test helpers out of production dependency paths.
The Starlark and extension scripts retain their temporary workspaces for
inspection. Each accepts an optional ruleset checkout path. The extension checks
automatic default registration, per-platform archive overrides, identical
dependency declarations, root precedence, conflicts, and dev-only usage. Its
no-tag setup fails against `d6b9e95`, which required a `.toolchains(...)` call.
The Starlark script checks the Aa/BB action configuration collision (failing on
`0f17c44`), aliases under `select()`, executable sidecar outputs,
an external executable's data and expected payload-platform analysis errors.

Bazel 8.5.0 and 9.3.1 have been exercised. With Bazelisk, set
`USE_BAZEL_VERSION` when running the common suite.

## Source build and fixture maintenance

```sh
tests/compile_platforms.sh --config=remote
tests/update_fixtures.sh --config=remote
(cd tests/fixture && shasum -a 256 -c SHA256SUMS)
```

The supervisor builds from source for each executor and is not checked in. Fixture
maintenance uses Bazel's declared compiler/toolchain for PE executables and the
companion DLL. Lifecycle and argv verifiers build from source in the actual test
execution configuration; no verifier binary is checked in. Keep fixture sources
and checked-in Windows test binaries in sync.

The supervisor uses `rules_cc`'s runfiles library for discovery and manifest
parsing. Its `EnvVars()` are forwarded to the payload, with Wine path conversion.
`hermetic_launcher` resolves the supervisor/configuration and forwards argv.
Explicit action environment, Windows path markers and Wine lifecycle management
remain supervisor responsibilities. The supervisor is Linux/macOS-only; its
cross-compilation check covers those four OS/CPU combinations.

## Verification boundaries

Linux x86_64 console execution is verified on native remote workers. The default
Wine archive requires host glibc and libgcc_s; some subsystems need additional
libraries. Docker's x86_64 emulation on an ARM64 host failed the raw Wine baseline
and is not a substitute for native execution testing.

Native Windows, Linux ARM64 and Intel macOS execution remain untested. Windows
action graphs verify selection and inputs, not runtime behavior. Native local Linux
sandbox execution remains unverified.

The source-built C++ runfiles fixture runs through both a direct
`FilesToRunProvider` action and `windows_binary` as an action tool. Both verify
external-repository mapping and alias-only data. The adapter case fails against
`4ff2f7e` because its supervisor did not export the discovered runfiles environment.
The layout test also exercises a manifest whose payload entry points outside the
runfiles directory, verifying that adjacent DLL lookup retains the logical layout.

The pinned `@llvm` 0.7.6 macOS SDK URL returns 403. Both macOS supervisor
architectures were cross-compiled with a temporary root-module `osx.from_archive`
override using [Apple's SDK 26.5 package](https://swcdn.apple.com/content/downloads/33/19/140-17812-A_21ZLMMLY4E/zu3xwktttpoe71qiawhzgzvqss6rovawsa/CLTools_macOSNMOS_SDK.pkg).
The package was found through `hermetic-llvm`'s `tools/update_osx_sdk.py` catalog
parser, downloaded with HTTP 200, and its embedded SDK version and SHA-256 verified:
`debe353b27a13cd678b26ab216a040acf07b62c0639d8ac522df4ca07d121eb2`.
For the override, set `type = "pkg"` and
`strip_prefix = "Payload/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"`.
This verification does not update the pinned LLVM dependency's default SDK URL;
downstream macOS builds need the override until that dependency is updated.

An experimental native ARM64 macOS build
([DiagBridge 0.2.5](https://github.com/citi94/diagbridge/releases/tag/v0.2.5)) ran its
bundled `cmd.exe` on macOS 26.5.2, but independent ARM64 executables failed outside
Bazel too. It is not a supported default. Always test an independent program when
evaluating a new Wine archive; a bundled program alone does not prove compatibility.
