"""Low-level Windows actions. Declare toolchain_type(arch) on the same exec group."""

def toolchain_type(arch):
    if arch not in ["x86_64", "aarch64"]:
        fail("unsupported Windows payload architecture: " + arch)
    return Label("//wine:runner_" + arch + "_toolchain_type")

def path(ctx, file, arch, format = "%s", exec_group = "default"):
    """Explicit path interpolation; only these values are converted for Wine.

    Args:
        file: File, or action-relative path string.
        format: Surrounding option syntax, e.g. /out:%s.
    """
    runner = (ctx.toolchains if exec_group == "default" else ctx.exec_groups[exec_group].toolchains)[toolchain_type(arch)].windows
    value = file.path if type(file) == "File" else file
    return format % (("{windows_path:" + value + "}") if runner.backend == "wine" else value)

def _run(ctx, *, executable, arch, arguments = [], inputs = [], outputs = [], env = {}, runtime_files = [], tools = [], exec_group = "default", mnemonic = "WindowsRun", progress_message = None, **kwargs):
    runner = (ctx.toolchains if exec_group == "default" else ctx.exec_groups[exec_group].toolchains)[toolchain_type(arch)].windows
    payload = executable.executable if type(executable) == "FilesToRunProvider" else executable
    input_set = inputs if type(inputs) == "depset" else depset(inputs)
    tools = ([executable] if type(executable) == "FilesToRunProvider" else [payload]) + (tools.to_list() if type(tools) == "depset" else list(tools))
    action_group = None if exec_group == "default" else exec_group
    if runner.backend == "native":
        # No process adapter for Windows actions. Explicit path markers are not
        # needed on Windows; use Args.add(File) for platform-neutral arguments.
        ctx.actions.run(executable = executable, arguments = arguments, inputs = depset(runtime_files, transitive = [input_set]), outputs = outputs, env = env, tools = tools, exec_group = action_group, toolchain = toolchain_type(arch), mnemonic = mnemonic, progress_message = progress_message, **kwargs)
        return
    config = ctx.actions.declare_file(ctx.label.name + "." + str(hash(str(outputs))) + "." + mnemonic + ".wine.json")
    ctx.actions.write(config, json.encode({"backend": runner.backend, "arch": arch, "loader": runner.runtime.loader.path, "server": runner.runtime.server.path, "payload": payload.path, "env": env, "runtime_env": runner.runtime.env}))
    ctx.actions.run(
        executable = runner.launcher,
        arguments = ["--config", config.path, "--"] + arguments,
        inputs = depset([config, payload] + runtime_files, transitive = [input_set, runner.runtime.files]),
        outputs = outputs,
        env = env,
        tools = tools,
        exec_group = action_group,
        toolchain = toolchain_type(arch),
        mnemonic = mnemonic,
        progress_message = progress_message,
        **kwargs
    )

windows_actions = struct(run = _run, path = path, toolchain_type = toolchain_type)
