"""Typed argv expansion; location values never pass through a shell string."""

def path_marker(value, runfile = False):
    return "{windows_runfile:" + json.encode(value) + "}" if runfile else "{windows_path:" + json.encode(value) + "}"

def runfile_path(ctx, file):
    return file.short_path[3:] if file.short_path.startswith("../") else ctx.workspace_name + "/" + file.short_path

def _callable_path(file):
    return file.path if "/" in file.path else "./" + file.path

def _files(target):
    info = target[DefaultInfo]
    return [info.files_to_run.executable] if info.files_to_run.executable else sorted(info.files.to_list(), key = _callable_path)

def _location_fingerprint(files):
    # Mirror Bazel's LocationExpander/ShellEscaper serialization, not a shell
    # parser. AliasProvider's original dependency labels are not Starlark APIs.
    # https://github.com/bazelbuild/bazel/blob/8.5.0/src/main/java/com/google/devtools/build/lib/util/ShellEscaper.java
    # https://github.com/bazelbuild/bazel/blob/9.3.1/src/main/java/com/google/devtools/build/lib/analysis/starlark/StarlarkRuleContext.java
    safe = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%-_+:,./~"
    result = []
    for path in sorted([_callable_path(file) for file in files]):
        result.append(path if not path.startswith("~") and all([char in safe for char in path.elems()]) else "'" + path.replace("'", "'\\''") + "'")
    return " ".join(result)

def _location_files(ctx, spelling, targets, labels):
    # Bazel 9 provides caller-relative label resolution. On 8.5, Label.relative
    # handles local labels but uses the defining .bzl mapping for apparent repos.
    label = None
    if hasattr(ctx, "package_relative_label"):
        label = ctx.package_relative_label(spelling)
    elif not spelling.startswith("@"):
        label = ctx.label.relative(spelling)
    if label in labels:
        return labels[label]

    # Alias edges expose their actual Target.label. Let Bazel resolve the alias
    # or caller's apparent repository; compare whole opaque expansion values.
    # No shell quoting is decoded and no path/string boundaries are inferred.
    expanded = ctx.expand_location("$(locations " + spelling + ")", targets = targets)
    matches = None
    for target in targets:
        info = target[DefaultInfo]
        if expanded in [_location_fingerprint(info.files.to_list()), _location_fingerprint(_files(target))]:
            files = _files(target)
            if matches != None and matches != files:
                fail("ambiguous executable/output alias; use the declared target's canonical label: " + spelling)
            matches = files
    if matches == None:
        fail("location must be declared in binary, srcs or data and match Bazel's supported File-set encoding: " + spelling)
    return matches

def expand_arguments(ctx, targets, *, runfiles = False, windows = True, variables = {}, runfile_entries = {}):
    """Expand declared labels and explicit output/source variables once.

    Each argument remains one argv element. A standalone plural expression
    expands to separate elements; an embedded plural must identify one file.
    $$ escapes a dollar, including a following location expression.

    Args:
        ctx: Consuming rule context, including its arguments attribute.
        targets: Declared targets available to location expressions.
        runfiles: Resolve locations to logical runfiles keys.
        windows: Emit encoded Windows paths rather than ordinary exec paths.
        variables: Source/output variable names mapped to Files.
        runfile_entries: Declared logical runfiles keys mapped to Files.

    Returns:
        Expanded argv elements, with plural expressions preserving cardinality.
    """
    labels = {target.label: _files(target) for target in targets}
    result = []
    for argument in ctx.attr.arguments:
        parts = [""]
        consumed = 0
        for index in range(len(argument)):
            if index < consumed:
                continue
            char = argument[index]
            if char != "$":
                parts[-1] += char
                continue
            if argument.startswith("$$", index):
                parts[-1] += "$"
                consumed = index + 2
                continue
            if argument.startswith("$@", index):
                expression = "@"
                consumed = index + 2
            elif argument.startswith("$(", index):
                expression, close, _ = argument[index + 2:].partition(")")
                if not close:
                    fail("unterminated argument expression: " + argument)
                consumed = index + len(expression) + 3
            else:
                fail("use $$ for a literal dollar in arguments: " + argument)
            words = expression.split(" ", 1)
            if words[0] == "runfile" and len(words) == 2:
                key = words[1]
                if key not in runfile_entries:
                    fail("argument runfile must be declared in binary or data: " + key)
                values = [path_marker(key, runfile = True) if windows else runfile_entries[key].path]
            else:
                if words[0] in ["location", "locations"] and len(words) == 2:
                    files = _location_files(ctx, words[1].strip(), targets, labels)
                    if words[0] == "location" and len(files) != 1:
                        fail("$(location {}) requires one file; use $(locations ...)".format(words[1]))
                elif expression in variables:
                    files = variables[expression]
                else:
                    fail("unsupported argument expression: $(" + expression + ")")
                values = [runfile_path(ctx, file) if runfiles else file.path for file in files]
                if windows:
                    values = [path_marker(value, runfile = runfiles) for value in values]
            if index == 0 and consumed == len(argument):
                parts = values
            elif len(values) == 1:
                parts[-1] += values[0]
            else:
                fail("a plural file expression must be a complete argument: " + argument)
        result.extend(parts)
    return result
