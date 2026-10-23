# Testing and maintenance

Run from the repository root. The `remote` config uses a native Linux x86_64
BuildBuddy executor with Ubuntu 24.04; authentication belongs in your user config.
For a native local Linux worker, omit `--config=remote`.

## Behavior checks

```sh
bazel test //tests:integration --config=remote
bazel build //tests:generate //tests:transitioned //tests:adapter_tool \
  //tests:dll //tests:response //tests:param_file //tests:location_tool \
  //tests:additional_tools //tests:default_group //tests:default_group_tools \
  //tests:external_tools //tests:distinct_actions \
  --config=remote
bazel test //tests:runfiles_test --config=remote --noenable_runfiles
```

These use independent Windows executables to check output generation, DLL loading,
child processes, argument preservation, generated/external data, test XML,
sharding, and writable directories. The lifecycle test checks concurrent private
prefixes, cancellation ownership, descendant cleanup, exit status, architecture
rejection, and unchanged input files. The layout test creates real symlinks because
remote execution can materialize ordinary runfiles and hide local layout bugs.
The argv regression asserts exact records for spaces, empty strings, dollars,
braces, Unicode, source/generated/external files, escaped expressions and plural
cardinality. A source-built Windows consumer uses the standard C++ runfiles
library to verify apparent-repository mapping and alias-only action data.

Inspect the generated JSON files as well as the test results. Use `bazel aquery`
to inspect executables, platforms, declared tools and inputs. Native actions must
invoke the PE directly without Wine inputs:

```sh
bazel aquery '//tests:generate + //tests:generate_arm64' --config=remote \
  --extra_execution_platforms=//platforms:windows_x86_64,//platforms:windows_aarch64
```

The following targets intentionally fail; they are excluded from the suite:

```sh
bazel build //tests:missing_dll --config=remote
bazel test //tests:timeout_test --config=remote --test_timeout=3 --nocache_test_results
```

The first must report the missing companion DLL; the second must time out.
The lifecycle test, rather than timeout status alone, verifies cleanup.

## Consumers and Bazel versions

```sh
(cd e2e/smoke && bazel test //:consumer_test --config=remote)
e2e/test_custom_archive.sh /absolute/path/to/wine-11.0-amd64-wow64.tar.xz SHA256
e2e/test_starlark.sh
e2e/test_extension.sh
```

The consumer exercises the public module setup. The script tests a named custom
archive through `http_archive`; supplying an incorrect checksum must fail fetching.
Keep fixture compilers and test helpers out of production dependency paths.
The Starlark and extension scripts retain their temporary workspaces for
inspection. Each accepts an optional ruleset checkout path: the same checks fail
against baseline `0f17c44` at the Aa/BB action configuration collision and duplicate
transitive registration name respectively, and pass after the cleanup. The
Starlark script also checks aliases under `select()`, executable sidecar outputs,
an external caller's apparent repository mapping and expected analysis errors.

Bazel 8.5.0 and 9.3.1 have been exercised. With Bazelisk, set
`USE_BAZEL_VERSION` when running the common suite. Bazel 9's execution-group check
lives separately because its attributes are unavailable in older versions:

```sh
bazel aquery 'mnemonic("TestRunner", //tests/bazel9:wine_group_test)' --config=remote \
  --extra_execution_platforms=//platforms:windows_x86_64,//platforms:remote_linux_x86_64
```

Inspect its `TestRunner` action: the actual test group must select Linux/Wine even
when the default group selects Windows. Running this synthetic mismatch also
requires a real Windows executor: source-building the Linux supervisor from the
default Windows execution configuration invokes a Windows-hosted C++ compiler.

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

The adapter currently also handles environment overrides, Windows path markers,
and arbitrary configured argument lists. `hermetic_launcher` v0.0.16 handles
runfiles entrypoints but has no equivalent environment/path API and limits embedded
arguments to ten entries of 256 bytes. Adding it around the supervisor would not
remove those responsibilities. Revisit reuse when it can replace that machinery
without another wrapper or a narrower public contract.

## Verification boundaries

Linux x86_64 console execution is verified on native remote workers. The default
Wine archive requires host glibc and libgcc_s; some subsystems need additional
libraries. Docker's x86_64 emulation on an ARM64 host failed the raw Wine baseline
and is not a substitute for native execution testing.

Native Windows, Linux ARM64 and Intel macOS execution remain untested. Windows
action graphs verify selection and inputs, not runtime behavior. Native local Linux
sandbox execution remains unverified. The pinned `@llvm` macOS SDK URL returned 403
during the source-build check. Both macOS architectures compiled using a temporary
archive of the locally installed SDK; downstream macOS builds need a reachable SDK
archive supplied through `@llvm`'s `osx.from_archive` extension until its default
URL works again.

An experimental native ARM64 macOS build
([DiagBridge 0.2.5](https://github.com/citi94/diagbridge/releases/tag/v0.2.5)) ran its
bundled `cmd.exe` on macOS 26.5.2, but independent ARM64 executables failed outside
Bazel too. It is not a supported default. Always test an independent program when
evaluating a new Wine archive; a bundled program alone does not prove compatibility.
