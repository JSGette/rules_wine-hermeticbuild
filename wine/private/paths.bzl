"""Logical runfile keys for executable adapters."""

def runfile_path(ctx, file):
    return file.short_path[3:] if file.short_path.startswith("../") else ctx.workspace_name + "/" + file.short_path
