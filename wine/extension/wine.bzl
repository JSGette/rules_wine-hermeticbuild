"""Pinned Wine distributions and explicit, named runner registrations."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//wine/private:repositories.bzl", "registration_repository")

_DEFAULT = struct(
    urls = ["https://github.com/Kron4ek/Wine-Builds/releases/download/11.0/wine-11.0-amd64-wow64.tar.xz"],
    sha256 = "39574efa1132c3ca0d5c77dd2eddbe4a49cca0d6cc2c290ff4924493a1c40314",
    integrity = "",
    strip_prefix = "wine-11.0-amd64-wow64",
    loader = "bin/wine",
    server = "bin/wineserver",
    files = ["**"],
    arch = "x86_64",
    exec_os = "linux",
    env = {},
    identity = "Kron4ek Wine 11.0 amd64 WoW64",
    requirements = "Linux glibc ELF interpreter; glibc, libm, libgcc_s; optional subsystem libraries depend on payload. See VALIDATION.md.",
)

def _safe(path, field):
    if not path or path.startswith("/") or ".." in path.split("/") or "\\" in path or ":" in path or '"' in path or "\n" in path:
        fail("{} must be a nonempty relative archive path: {}".format(field, repr(path)))

def _archive(name, tag):
    if bool(tag.sha256) == bool(tag.integrity):
        fail("{}: specify exactly one of sha256 or integrity".format(name))
    if not tag.urls:
        fail("{}: urls must not be empty".format(name))
    if not tag.files or not tag.identity or not tag.requirements:
        fail("{}: files, identity and requirements must be nonempty".format(name))
    _safe(tag.loader, "loader")
    _safe(tag.server, "server")
    if tag.strip_prefix:
        _safe(tag.strip_prefix, "strip_prefix")
    for pattern in tag.files:
        _safe(pattern, "files")
    http_archive(
        name = name,
        urls = tag.urls,
        sha256 = tag.sha256,
        integrity = tag.integrity,
        strip_prefix = tag.strip_prefix,
        build_file_content = 'package(default_visibility = ["//visibility:public"])\nfilegroup(name = "loader", srcs = [{}])\nfilegroup(name = "server", srcs = [{}])\nfilegroup(name = "files", srcs = glob({}))\n'.format(repr(tag.loader), repr(tag.server), repr(tag.files)),
    )

def _impl(ctx):
    direct = []
    direct_dev = []
    registration_names = {}

    # A module's tags refer only to its own named distributions.
    for index, mod in enumerate(ctx.modules):
        distributions = {"default": (_DEFAULT, "wine_default")}
        for tag in mod.tags.prebuilt:
            if tag.name in distributions:
                fail("duplicate Wine distribution {} in module {}".format(tag.name, mod.name))
            distributions[tag.name] = (tag, "wine_{}_{}".format(index, tag.name))
        created = {}
        for tag in mod.tags.toolchains:
            if tag.name in registration_names:
                fail("toolchains repository {} already declared by module {}; choose a globally unique registration name".format(tag.name, registration_names[tag.name]))
            registration_names[tag.name] = mod.name
            repos = {}
            identities = {}
            requirements = {}
            environments = {}
            for os, arch, selected in [("linux", "x86_64", tag.x86_64), ("linux", "aarch64", tag.aarch64), ("osx", "x86_64", tag.macos_x86_64), ("osx", "aarch64", tag.macos_aarch64)]:
                if not selected:
                    continue
                if selected not in distributions:
                    fail("unknown Wine distribution {} in module {}".format(selected, mod.name))
                dist, repo = distributions[selected]
                if dist.arch != arch or dist.exec_os != os:
                    fail("{} distribution has platform {}/{}, requested {}/{}".format(selected, dist.exec_os, dist.arch, os, arch))
                if repo not in created:
                    # Default is shared across modules; create once globally below.
                    if selected != "default":
                        _archive(repo, dist)
                    created[repo] = True
                key = os + "_" + arch
                repos[key] = repo
                identities[key] = dist.identity
                requirements[key] = dist.requirements
                environments[key] = json.encode(dist.env)
            registration_repository(name = tag.name, distributions = repos, identities = identities, requirements = requirements, environments = environments)
            if mod.is_root:
                (direct_dev if ctx.is_dev_dependency(tag) else direct).append(tag.name)

    # Repository declaration alone does not fetch its archive.
    _archive("wine_default", _DEFAULT)
    return ctx.extension_metadata(root_module_direct_deps = direct, root_module_direct_dev_deps = direct_dev)

wine = module_extension(implementation = _impl, tag_classes = {
    "prebuilt": tag_class(attrs = {
        "name": attr.string(mandatory = True),
        "arch": attr.string(mandatory = True, values = ["x86_64", "aarch64"]),
        "exec_os": attr.string(default = "linux", values = ["linux", "osx"]),
        "urls": attr.string_list(mandatory = True),
        "sha256": attr.string(),
        "integrity": attr.string(),
        "strip_prefix": attr.string(),
        "loader": attr.string(default = "bin/wine"),
        "server": attr.string(default = "bin/wineserver"),
        "files": attr.string_list(default = ["**"]),
        "identity": attr.string(mandatory = True),
        "requirements": attr.string(mandatory = True),
        "env": attr.string_dict(doc = "Loader environment; supports {loader_dir} and {server_dir}."),
    }),
    "toolchains": tag_class(attrs = {
        "name": attr.string(mandatory = True),
        "x86_64": attr.string(doc = "Distribution name, default for pinned Wine, empty for no Linux x86_64 runner."),
        "macos_x86_64": attr.string(doc = "Native Intel macOS Wine distribution name."),
        "macos_aarch64": attr.string(doc = "Native ARM64 macOS Wine distribution; no known default."),
        "aarch64": attr.string(doc = "User-supplied native ARM64 distribution name; no default archive."),
    }),
})
