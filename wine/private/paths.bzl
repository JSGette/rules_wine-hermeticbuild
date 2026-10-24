"""Logical runfile keys and explicit action path markers."""

def path_marker(value):
    return "{windows_path:" + json.encode(value) + "}"

def runfile_path(ctx, file):
    return file.short_path[3:] if file.short_path.startswith("../") else ctx.workspace_name + "/" + file.short_path
