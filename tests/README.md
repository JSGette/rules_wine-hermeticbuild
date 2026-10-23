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
  --config=remote
bazel test //tests:runfiles_test --config=remote --noenable_runfiles
```

These use independent Windows executables to check output generation, DLL loading,
child processes, argument preservation, generated/external data, test XML,
sharding, and writable directories. The lifecycle test checks concurrent private
prefixes, cancellation ownership, descendant cleanup, exit status, architecture
rejection, and unchanged input files. The layout test creates real symlinks because
remote execution can materialize ordinary runfiles and hide local layout bugs.

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
tools/test_custom_archive.sh /absolute/path/to/wine-11.0-amd64-wow64.tar.xz SHA256
```

The consumer exercises the public module setup. The script tests a named custom
archive through `http_archive`; supplying an incorrect checksum must fail fetching.
Keep fixture compilers and test helpers out of production dependency paths.

Bazel 7.7.0, 8.5.0 and 9.3.1 have been exercised. With Bazelisk, set
`USE_BAZEL_VERSION` when running the common suite. Bazel 9's execution-group check
lives separately because its attributes are unavailable in older versions:

```sh
bazel test //tests/bazel9:wine_group_test --config=remote \
  --extra_execution_platforms=//platforms:windows_x86_64,//platforms:remote_linux_x86_64
```

Inspect its `TestRunner` action: the actual test group must select Linux/Wine even
when the default group selects Windows.

## Maintenance binaries

```sh
tools/build_runtime.sh /absolute/path/to/go1.25.3
tools/build_fixtures.sh /absolute/path/to/go1.25.3
/absolute/path/to/go1.25.3 -C wine/runtime test ./...
(cd wine/runtime && shasum -a 256 -c SHA256SUMS)
(cd tests/fixture && shasum -a 256 -c SHA256SUMS)
```

The fixture build also needs clang/lld. These are maintenance tools; consuming the
ruleset needs no compiler. Keep source and checked-in binaries in sync. Binary
release packaging can change independently of the public rules.

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
action graphs verify selection and inputs, not runtime behavior. Full source
compiler/SDK integration and native local Linux sandbox execution remain unverified.

An experimental native ARM64 macOS build
([DiagBridge 0.2.5](https://github.com/citi94/diagbridge/releases/tag/v0.2.5)) ran its
bundled `cmd.exe` on macOS 26.5.2, but independent ARM64 executables failed outside
Bazel too. It is not a supported default. Always test an independent program when
evaluating a new Wine archive; a bundled program alone does not prove compatibility.
