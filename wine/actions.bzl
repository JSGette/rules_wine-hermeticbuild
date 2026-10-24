"""Low-level Windows actions. Declare toolchain_type(arch) on the same exec group."""

load("//wine/private:paths.bzl", "path_marker")

def toolchain_type(arch):
    if arch not in ["x86_64", "aarch64"]:
        fail("unsupported Windows payload architecture: " + arch)
    return Label("//wine:runner_" + arch + "_toolchain_type")

def path(ctx, file, arch, format = "%s", exec_group = "default"):
    """Explicit path interpolation; only these values are converted for Wine.

    Args:
        ctx: The consuming rule context.
        file: File, or action-relative path string.
        arch: Declared Windows payload CPU.
        format: Surrounding option syntax, e.g. /out:%s.
        exec_group: Execution group declaring the runner toolchain.

    Returns:
        A path argument formatted for the selected executor.
    """
    toolchains = ctx.toolchains if exec_group == "default" else ctx.exec_groups[exec_group].toolchains
    runner = toolchains[toolchain_type(arch)].windows
    value = file.path if type(file) == "File" else file
    return format % (path_marker(value) if runner.backend == "wine" else value)

def _run(
        ctx,
        *,
        executable,
        arch,
        outputs,
        arguments = [],
        inputs = [],
        env = {},
        runtime_files = [],
        tools = [],
        exec_group = "default",
        mnemonic = "WindowsRun",
        progress_message = None,
        **kwargs):
    if not outputs:
        fail("Windows actions require at least one output to identify their configuration")
    toolchains = ctx.toolchains if exec_group == "default" else ctx.exec_groups[exec_group].toolchains
    runner = toolchains[toolchain_type(arch)].windows
    payload = executable.executable if type(executable) == "FilesToRunProvider" else executable
    input_set = inputs if type(inputs) == "depset" else depset(inputs)

    # The wrapped executable remains a tool when the supervisor replaces it.
    # Lists can carry FilesToRunProvider; depsets carry Files.
    if type(tools) == "depset" and type(executable) == "File":
        tools = depset([executable], transitive = [tools])
    else:
        tools = [executable] + (tools.to_list() if type(tools) == "depset" else tools)
    action_group = None if exec_group == "default" else exec_group
    if runner.backend == "native":
        # No process adapter for Windows actions. Explicit path markers are not
        # needed on Windows; use Args.add(File) for platform-neutral arguments.
        ctx.actions.run(
            executable = executable,
            arguments = arguments,
            inputs = depset(runtime_files, transitive = [input_set]),
            outputs = outputs,
            env = env,
            tools = tools,
            exec_group = action_group,
            toolchain = toolchain_type(arch),
            mnemonic = mnemonic,
            progress_message = progress_message,
            **kwargs
        )
        return

    # First output identifies the action. Reserve a target-owned namespace;
    # unlike hashes, distinct output paths cannot alias this configuration.
    config = ctx.actions.declare_file(ctx.label.name + ".wine/" + outputs[0].path + ".json")
    ctx.actions.write(config, json.encode({
        "arch": arch,
        "loader": runner.runtime.loader.path,
        "server": runner.runtime.server.path,
        "payload": payload.path,
        "env": env,
        "runtime_env": runner.runtime.env,
    }))
    ctx.actions.run(
        executable = runner.launcher,
        arguments = ["--config", config.path, "--"] + arguments,
        inputs = depset([config, payload] + runtime_files, transitive = [input_set, runner.runtime.files]),
        outputs = outputs,
        # These describe the Windows payload. A custom native launcher must
        # discover its own FilesToRunProvider runfiles before starting it.
        env = {
            key: value
            for key, value in env.items()
            if key not in ["RUNFILES_DIR", "RUNFILES_MANIFEST_FILE", "RUNFILES_MANIFEST_ONLY"]
        },
        tools = tools,
        exec_group = action_group,
        toolchain = toolchain_type(arch),
        mnemonic = mnemonic,
        progress_message = progress_message,
        **kwargs
    )

windows_actions = struct(run = _run, path = path, toolchain_type = toolchain_type)
