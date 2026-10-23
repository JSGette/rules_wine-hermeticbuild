# Validation evidence

## Runtime acquisition and platform resolution (layer 1)

- Bazel 9.3.1, macOS ARM64 host. `bazel build //tests:probe_x86_64
  --extra_execution_platforms=//platforms:linux_x86_64` selected Linux x86_64 Wine.
- `bazel build //tests:probe_aarch64
  --extra_execution_platforms=//platforms:windows_aarch64` selected native ARM64.
- `bazel cquery 'deps(@wine_toolchains//:windows_x86_64_impl)' --output=label`
  showed the Windows launcher and platform definitions, no Wine archive.
- `file wine/runtime/*x86_64* wine/runtime/*aarch64*`: architecture-correct
  static Linux ELF, Windows PE, and Darwin Mach-O support executables.
- `bazel build //tests:runtime_probe --config=remote` passed on BuildBuddy
  Linux x86_64 with Ubuntu 24.04. Output JSON inspected: `child-ok`, arguments
  `a b`, empty string, and `café` preserved; output path converted explicitly;
  cwd `Z:\buildbuddy-execroot`; private `/tmp/rules-wine-4207179571/prefix`.
  Invocation: 6d6326be-69c3-43d6-addc-24c55e312a81.
- `bazel aquery //tests:runtime_probe --config=remote --output=text` inspected:
  actual executor `//platforms:remote_linux_x86_64`, supervisor executable,
  entire immutable runtime inputs, PE payload, config, declared JSON output.
  Output target configuration was Darwin ARM64: independently proves that the
  Windows tool architecture is not inferred from final output OS/CPU.
- Kron4ek Wine 11.0 archive checksum independently verified inside Ubuntu 24.04:
  `39574efa1132c3ca0d5c77dd2eddbe4a49cca0d6cc2c290ff4924493a1c40314`.
  `file` and `ldd` inspected loader/server/ntdll. Loader: glibc ELF interpreter,
  libc and libdl. ntdll additionally libpthread and libgcc_s. Runtime emits
  FreeType warnings with this minimal image, but the console probe succeeds.
  This is not a fully bundled Linux userspace or general GUI compatibility claim.
- Docker Desktop on ARM64, Ubuntu24.04 `--platform linux/amd64`: raw unwrapped
  Wine segfaults (139) before initialization under Docker's CPU emulation.
  This baseline failure is not a rules_wine runtime result. Native remote probe
  above avoids that environment failure. No production CPU translator is used.

The checked-in support executables are reproducibly built using Go 1.25.3,
CGO_ENABLED=0, no third-party Go modules. `tools/build_runtime.sh` maintains them;
SHA256SUMS records exact bytes. Downstream Bazel modules need neither Go nor a
C/C++ compiler. Go distribution source: https://go.dev/dl/ .

Native Windows, Linux ARM64 and macOS execution remain untested at this point.
macOS support was added to scope during implementation: architecture-correct
launchers and custom distributions, no implicit Rosetta or ARM64 archive fallback.

## Actions and adapters (layer 2)

`bazel build //tests:generate //tests:transitioned //tests:adapter_tool
//tests:dll //tests:response --config=remote` passed. All five JSON artifacts
inspected: child execution; output generation; spaces, Unicode and empty values;
a real companion DLL exported function returning 42; UTF-8 response-file content.
The adapter is consumed as a FilesToRunProvider in exec configuration by a
separate action rule. The payload transition validates Windows/x86_64 while the
output target remains Darwin ARM64. `aquery` confirms the executor and tools.

Adapters use separate toolchain types constrained by their own executable target
OS/CPU. Generic action runner types have no output target constraints. This is
necessary because Bazel's exec_compatible_with is not configurable: attempting
select there fails at package loading. Merely registering a Linux remote executor
cannot select a Linux adapter for a local Darwin target. On a host with no matching
configured Wine runtime, adapter analysis fails instead of emitting foreign code.

Companion DLL layout contract: declared data preserves its existing runfiles path.
DLLs requiring executable adjacency must already be adjacent in that layout (as
in tests/fixture); arbitrary data declarations do not relocate files. For source
outputs, arrange executable and companion outputs in the same relative directory.

## Tests, consumers and compatibility (layer 3)

- Bazel 9: `bazel test //tests:smoke_test //tests:runtime_contract_test
  //tests:runfiles_test --config=remote` passed. Smoke is two shards and asserts
  exact arguments (spaces, empty, café), writes its own XML, marks shard support,
  writes TEST_TMPDIR, and reports converted runfiles/result paths and custom env.
- Runtime contract test starts two real Wine invocations concurrently, creates a
  sentinel in each C: drive (rejecting shared mutable prefixes), and creates real
  children. Cancelling one invocation must preserve the other. Both owned scratch
  roots disappear and /proc environment audit finds no surviving owned descendant.
  Exit37 passes through; a supplied ARM64 PE is rejected before execution; loader
  and payload hashes remain unchanged. First isolated run took6.9s; later native
  remote run passed48.9s (scheduling/runtime contention included separately in Bazel
  timing). This is behavior coverage, not mocked Wine lifecycle verification.
- Baseline negative discovered by this integration test: explicitly empty
  XML_OUTPUT_FILE was converted into the working directory and caused the Windows
  fixture to attempt writing XML to a directory. Same test failed before the fix
  and passed after preserving empty protocol-path values. Empty values now stay
  empty; nonempty declared paths are converted.
- `//tests:param_file` passed: real lazy Args multiline parameter file, depset
  inputs, explicit output conversion, opaque `/option:one/two` and HTTPS arguments,
  and environment `opaque/unchanged` preserved. Response content is consumer-owned.
- Bazel7.7.0 and8.5.0 each executed the sharded smoke test through Wine remotely.
  No minimum-version increase required. Bazel9-only exec-group attribute examples
  live in tests/bazel9 so older Bazel can load the common tests.
- Bazel9 trap: `aquery //tests/bazel9:wine_group_test
  --extra_execution_platforms=//platforms:windows_x86_64,//platforms:linux_x86_64`
  selected Windows for default generation and Linux for the actual TestRunner.
  Config/supervisor follows the test group. The same mismatch was executed with
  the remote Linux platform and passed. A reverse Windows-test cross-host analysis
  reached Bazel's own launcher C++ toolchain requirement; no Windows runtime proof
  is claimed from that failed cross-host analysis.
- Native-action `aquery '//tests:generate + //tests:generate_arm64'
  --extra_execution_platforms=//platforms:windows_x86_64,//platforms:windows_aarch64`
  inspected: direct architecture-matching PE executables, no Wine config/runtime
  inputs. Native Windows execution still needs a real worker and is untested.
- External module e2e/smoke: `bazel --output_base=/tmp/rules-wine-external test
  //:consumer_test --config=remote` passed. `bazel mod graph` has no LLVM, Go,
  rules_python or rules_py dependency. Root maintenance/default registration is
  dev-only. Production imports require only the platforms module plus Bazel tools.
- `tools/test_custom_archive.sh <local Wine archive> <recorded sha256>` passed
  its external action and test, using http_archive, custom URL, checksum, layout
  and named registration. Default and custom distributions were used independently.
- Support and fixture rebuilds repeated with identical SHA256SUMS. Go1.25.3 host
  compiler archive inspected SHA256 is `7c083e3d2c00debfeb2f77d9a4c00a1aac97113b89b9ccc42a90487af3437382`.
  No compiler is fetched or executed by downstream production targets.

## Native macOS ARM64 research boundary

User added macOS execution after the original plan and explicitly rejected Rosetta.
Both Darwin support binaries and custom archive registrations are implemented.
No x86_64 binary is substituted for ARM64.

The original DiagBridge0.2.5 DMG is published at
https://github.com/citi94/diagbridge/releases/tag/v0.2.5 ; original archive SHA256
`1bc5c5cd6c504fb045d5142bffafdeb0f135ae6babda54dbf2c1c65cea0a3c9d`.
Research repack retained the signed application and resources, SHA256
`bdca4ae310d784103dcc63252f5d156d654353e4b27cfa4249a21047361d4b87`.
The repack is local evidence, not a published runtime URL. Loader/server are
Mach-O ARM64 and cmd/kernel32 are PE ARM64; codesign verification passed. Native
`wine --version` reports `usb-working-checkpoint-2026-06-16-13-g0cc8848b607`.

Raw successful baseline on macOS26.5.2 (RUNTIME is Contents/Resources under the
extracted signed application; SCRATCH is a new user-owned mktemp directory):

```sh
env -i HOME="$SCRATCH" WINEPREFIX="$SCRATCH/prefix" WINEDEBUG=-all \
  WINEDLLOVERRIDES='mscoree,mshtml,winemenubuilder.exe=' \
  WINESERVER="$RUNTIME/wine/bin/wineserver" \
  DYLD_FALLBACK_LIBRARY_PATH="$RUNTIME/libs" \
  "$RUNTIME/wine/bin/wine" \
  "$RUNTIME/wine/lib/wine/aarch64-windows/cmd.exe" /c echo native-arm64-wine
```

Result `native-arm64-wine`, status0. No WINEHYBRIDX86/Rosetta or security changes.
The adapter's prefix initialization also succeeds. Replacing the final cmd.exe
argument with the independently built `tests/fixture/minimal_aarch64.exe` fails
status53 with `could not load kernel32.dll, status c0000135`. Same failure occurs
raw, outside Bazel. PE source/import definitions and build command are checked in;
current fixture SHA256 is
`f3681ab970b649cc5b57a508739043092d8c6e807044179c257ff3b1fe9255ce`.
A separate64K section/file alignment variant also fails. The ARM64 Go fixture
fails/hangs in loader initialization. Module traces prove correct ARM64 PE mapping
and ntdll load, followed by failing kernel32 resolution for the independent PE.
No claim that the exact upstream root cause has been proven; no Wine patch made.

`tools/test_macos_archive.sh` materializes a local external consumer with the
recorded archive layout and loader dylib environment, reproducing this boundary.
It intentionally reports the independent-payload failure, not a support success.
macOS ARM64 backend implemented; shipped-cmd execution demonstrated; arbitrary
external-payload execution blocked/unverified with this experimental distribution.
Intel macOS and Linux ARM64 runtime execution remain untested.

## Remaining limits

No native Windows worker available; Windows execution, cancellation and result
paths are untested. Source payload platform transition/validation is implemented
and exercised with configured payload inputs; a full source compiler/SDK consumer
integration is not tested. Generic wrapped test providers/coverage are not copied.
No local native Linux sandbox execution was available (Docker ARM64's x64 CPU
emulation fails the raw Wine baseline). Real Linux actions/tests were remote,
inside the configured Ubuntu24.04 execution container. The Wine CLI's truncation
of full32-bit Windows exit status remains a protocol limit. Stronger security
isolation, GUI/.NET behavior and prepared-prefix performance are follow-up work.

Additional boundary checks: the supervisor validates Wine loader/server ELF or
Mach-O CPU headers before launch, including a matching native slice in fat Mach-O.
An inherited WINEHYBRIDX86 opt-in is removed; explicitly enabling it is rejected.
A custom archive cannot accidentally invoke a thin x86_64 Mach-O loader on ARM64
and let macOS start Rosetta. This checks main loader/server architecture; arbitrary
payload compatibility still belongs to the selected Wine distribution.

Final closeout results:

- Explicitly wrong custom-archive checksum rejected by http_archive: actual
  `39574efa...a1c40314`, requested64zeroes; fetch failed before any execution.
- Undeclared DLL negative failed with `companion.dll: Module not found`; declared
  DLL action succeeds and verifies exported answer42. This confirms inputs matter.
- `bazel test //tests:timeout_test --config=remote --test_timeout=3
  --nocache_test_results` reported expected TIMEOUT at3.0s. The separate real
  lifecycle test audits cleanup and ownership; timeout status alone is not that
  evidence.
- Manifest-only `bazel test //tests:runfiles_test --config=remote
  --noenable_runfiles --nocache_test_results` passed with a space/Unicode filename.
- Native-runtime header negative passed: an ARM64 ELF presented as an x86_64
  Wine loader is rejected125 before launch. Contract test again passed including
  this case; invocation2d93bc26-6c55-4956-9095-fbf85c11f8a4.
- Fresh output-base Linux action ran remotely, then ordinary output-base rebuild
  reported `1 remote cache hit`, elapsed1.004s. Generated artifact inspected in
  both cases; invocation68de4c00-33df-4e8f-ad9e-0bcfc2b7ffda confirms cache reuse.
- Buildifier checks and `git diff --check` pass. Support/fixture hashes reproducible
  across repeated maintenance builds; native header guard was then rebuilt and
  exercised by the real-runtime contract test.

Short PR description:

Windows tools need to execute independently of a build's final output platform.
Add same-CPU native/Wine runner toolchains, pinned/custom archive acquisition,
private Wine lifecycle supervision, and action/executable/test adapters. Linux
x86_64 behavior is verified on real remote workers; native Windows, ARM64 Linux,
and experimental macOS runtime limits are explicitly recorded.
