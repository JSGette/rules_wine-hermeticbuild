"""Low-level Windows actions using one resolved execution-group context."""

load("//wine/private:paths.bzl", "path_marker")

_TOOLCHAIN_TYPE = Label("//wine:runner_toolchain_type")

def _resolve(ctx, *, exec_group = "default"):
    """Bind a runner to the execution group declaring its toolchain type.

    Args:
        ctx: The consuming rule context.
        exec_group: Group declaring windows_actions.toolchain_type.

    Returns:
        Context for run/path, containing WindowsRunnerInfo as windows and the
        action's exec_group. The payload must match windows.arch; constrain the
        execution group for fixed-CPU prebuilts.
    """
    toolchains = ctx.toolchains if exec_group == "default" else ctx.exec_groups[exec_group].toolchains
    return struct(
        windows = toolchains[_TOOLCHAIN_TYPE].windows,
        exec_group = None if exec_group == "default" else exec_group,
    )

def path(runner, file, format = "%s"):
    """Explicit path interpolation; only these values are converted for Wine.

    Args:
        runner: Context returned by windows_actions.resolve.
        file: File, or action-relative path string.
        format: Surrounding option syntax, e.g. /out:%s.

    Returns:
        A path argument formatted for the selected executor.
    """
    value = file.path if type(file) == "File" else file
    return format % (path_marker(value) if runner.windows.backend == "wine" else value)

def _run(
        ctx,
        *,
        runner,
        executable,
        outputs,
        arguments = [],
        inputs = [],
        env = {},
        runtime_files = [],
        tools = [],
        mnemonic = "WindowsRun",
        progress_message = None,
        **kwargs):
    if not outputs:
        fail("Windows actions require at least one output to identify their configuration")
    action_group = runner.exec_group
    runner = runner.windows
    payload = executable.executable if type(executable) == "FilesToRunProvider" else executable
    input_set = inputs if type(inputs) == "depset" else depset(inputs)

    # The wrapped executable remains a tool when the supervisor replaces it.
    # Lists can carry FilesToRunProvider; depsets carry Files.
    if type(tools) == "depset" and type(executable) == "File":
        tools = depset([executable], transitive = [tools])
    else:
        tools = [executable] + (tools.to_list() if type(tools) == "depset" else tools)
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
            toolchain = _TOOLCHAIN_TYPE,
            mnemonic = mnemonic,
            progress_message = progress_message,
            **kwargs
        )
        return

    # First output identifies the action. Reserve a target-owned namespace;
    # unlike hashes, distinct output paths cannot alias this configuration.
    config = ctx.actions.declare_file(ctx.label.name + ".wine/" + outputs[0].path + ".json")
    ctx.actions.write(config, json.encode({
        "arch": runner.arch,
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
        toolchain = _TOOLCHAIN_TYPE,
        mnemonic = mnemonic,
        progress_message = progress_message,
        **kwargs
    )

windows_actions = struct(run = _run, path = path, resolve = _resolve, toolchain_type = _TOOLCHAIN_TYPE)
