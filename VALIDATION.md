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
