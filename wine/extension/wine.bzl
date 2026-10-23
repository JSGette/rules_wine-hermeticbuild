"""Pinned Wine distributions and composable named runner registrations."""

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
    requirements = "Linux glibc ELF interpreter; glibc, libm, libgcc_s; optional subsystem libraries depend on payload. See README.md.",
)

_PLATFORMS = [("linux", "x86_64", "x86_64"), ("linux", "aarch64", "aarch64"), ("osx", "x86_64", "macos_x86_64"), ("osx", "aarch64", "macos_aarch64")]

def _relative(path, field):
    if not path or path.startswith("/") or ".." in path.split("/") or "\\" in path:
        fail("{} must be a nonempty relative archive path: {}".format(field, repr(path)))

def _distribution(tag):
    return struct(**{field: getattr(tag, field) for field in ["urls", "sha256", "integrity", "strip_prefix", "loader", "server", "files", "arch", "exec_os", "env", "identity", "requirements"]})

def _archive(name, tag):
    if bool(tag.sha256) == bool(tag.integrity):
        fail("{}: specify exactly one of sha256 or integrity".format(name))
    if not tag.identity or not tag.requirements:
        fail("{}: identity and requirements must be nonempty".format(name))
    for field in ["loader", "server"]:
        _relative(getattr(tag, field), field)
    if tag.strip_prefix:
        _relative(tag.strip_prefix, "strip_prefix")
    for pattern in tag.files:
        _relative(pattern, "files")
    http_archive(
        name = name,
        urls = tag.urls,
        sha256 = tag.sha256,
        integrity = tag.integrity,
        strip_prefix = tag.strip_prefix,
        build_file_content = "\n".join([
            'package(default_visibility = ["//visibility:public"])',
            'filegroup(name = "loader", srcs = [{}])'.format(repr(tag.loader)),
            'filegroup(name = "server", srcs = [{}])'.format(repr(tag.server)),
            'filegroup(name = "files", srcs = glob({}))'.format(repr(tag.files)),
            "",
        ]),
    )

def _impl(ctx):
    root = {}
    inherited = {}
    direct = {}

    # Resolve semantic configurations first. Root choices override dependencies;
    # equivalent dependency declarations share a repository, conflicts are errors.
    for mod in ctx.modules:
        distributions = {"default": (_DEFAULT, "wine_default")}
        scope = "_main" if mod.is_root else "{}_{}_{}_{}".format(len(mod.name), mod.name, len(str(mod.version)), mod.version)
        for tag in mod.tags.prebuilt:
            if tag.name in distributions:
                fail("duplicate Wine distribution {} in module {}".format(tag.name, mod.name))
            distributions[tag.name] = (_distribution(tag), "wine_dist_" + scope + "_" + tag.name)
        for tag in mod.tags.toolchains:
            if tag.name == "wine_default" or tag.name.startswith("wine_dist_"):
                fail("toolchains repository name uses reserved Wine distribution namespace: " + tag.name)
            selected = {}
            repos = {}
            for os, arch, attribute in _PLATFORMS:
                name = getattr(tag, attribute)
                if not name:
                    continue
                if name not in distributions:
                    fail("unknown Wine distribution {} in module {}".format(name, mod.name))
                distribution, repo = distributions[name]
                if distribution.arch != arch or distribution.exec_os != os:
                    fail("{} distribution has platform {}/{}, requested {}/{}".format(name, distribution.exec_os, distribution.arch, os, arch))
                key = os + "_" + arch
                selected[key] = distribution
                repos[key] = repo
            configs = root if mod.is_root else inherited
            if tag.name in configs and configs[tag.name].selected != selected:
                # A root configuration may already resolve dependency conflicts.
                if mod.is_root or tag.name not in root:
                    fail("conflicting Wine toolchains repository {}; select it in the root module or use different names".format(tag.name))
            if tag.name not in configs:
                configs[tag.name] = struct(selected = selected, repos = repos)
            if mod.is_root:
                direct[tag.name] = direct.get(tag.name, True) and ctx.is_dev_dependency(tag)
    inherited.update(root)
    created = {}
    for name, config in inherited.items():
        registrations = {}
        for key, distribution in config.selected.items():
            repo = config.repos[key]
            if repo not in created:
                _archive(repo, distribution)
                created[repo] = True
            registrations[key] = {"repository": repo, "identity": distribution.identity, "requirements": distribution.requirements, "env": distribution.env}
        registration_repository(name = name, distributions = json.encode(registrations))
    return ctx.extension_metadata(root_module_direct_deps = [name for name in direct if not direct[name]], root_module_direct_dev_deps = [name for name in direct if direct[name]], reproducible = True)

wine = module_extension(implementation = _impl, tag_classes = {
    "prebuilt": tag_class(attrs = {
        "name": attr.string(mandatory = True),
        "arch": attr.string(mandatory = True, values = ["x86_64", "aarch64"]),
        "exec_os": attr.string(default = "linux", values = ["linux", "osx"]),
        "urls": attr.string_list(mandatory = True, allow_empty = False),
        "sha256": attr.string(),
        "integrity": attr.string(),
        "strip_prefix": attr.string(),
        "loader": attr.string(default = "bin/wine"),
        "server": attr.string(default = "bin/wineserver"),
        "files": attr.string_list(default = ["**"], allow_empty = False),
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
