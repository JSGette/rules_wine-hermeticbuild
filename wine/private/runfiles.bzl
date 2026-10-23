"""Transport complete runfiles through an action's standard manifest."""

load(":paths.bzl", "runfile_path")

def _escape(value):
    return value.replace("\\", "\\b").replace(" ", "\\s").replace("\n", "\\n")

def runfile_entries(ctx, runfiles):
    """Return the logical file map, including workspace and root aliases.

    Args:
        ctx: Consuming rule context.
        runfiles: Complete merged runfiles object.

    Returns:
        Logical keys mapped to Files, or None for generated empty entries.
    """
    entries = {runfile_path(ctx, file): file for file in runfiles.files.to_list()}
    for entry in runfiles.symlinks.to_list():
        entries[ctx.workspace_name + "/" + entry.path] = entry.target_file
    for entry in runfiles.root_symlinks.to_list():
        entries[entry.path] = entry.target_file
    for key in runfiles.empty_filenames.to_list():
        entries[key] = None
    return entries

def action_runfiles(ctx, runfiles, name):
    """Return a manifest and all its inputs, including alias-only/empty files.

    Args:
        ctx: Consuming rule context.
        runfiles: Complete merged runfiles object.
        name: Target-owned output prefix for the manifest and empty files.

    Returns:
        Struct with manifest File, complete input depset and logical file map.
    """
    entries = runfile_entries(ctx, runfiles)
    for index, key in enumerate(runfiles.empty_filenames.to_list()):
        file = ctx.actions.declare_file(name + ".empty/" + str(index))
        ctx.actions.write(file, "")
        entries[key] = file
    manifest = ctx.actions.declare_file(name + ".runfiles_manifest")
    ctx.actions.write(manifest, "".join([
        " " + _escape(key) + " " + _escape(entries[key].path) + "\n"
        for key in sorted(entries)
    ]))
    return struct(manifest = manifest, files = depset([manifest] + entries.values()), entries = entries)
