"""Declared logical runfiles keys for executable argument expansion."""

load(":paths.bzl", "runfile_path")

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
