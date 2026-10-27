"""Default Wine toolchains with per-platform prebuilt overrides."""

load("//wine/private:repositories.bzl", "registration_repository", "wine_archive")

_DEFAULT = struct(
    urls = ["https://github.com/Kron4ek/Wine-Builds/releases/download/11.0/wine-11.0-amd64-wow64.tar.xz"],
    sha256 = "39574efa1132c3ca0d5c77dd2eddbe4a49cca0d6cc2c290ff4924493a1c40314",
    integrity = "",
    strip_prefix = "wine-11.0-amd64-wow64",
    loader = "bin/wine",
    server = "bin/wineserver",
    files = ["**"],
    # Unix modules linking host libraries beyond glibc. Their Windows DLLs stay
    # and behave as on a host without those libraries.
    remove = ["lib/wine/x86_64-unix/{}.so".format(module) for module in [
        "capi2032",
        "gphoto2",
        "opencl",
        "sane",
        "winealsa",
        "winebus",
        "winedmo",
        "winegstreamer",
        "winepulse",
        "wineusb",
        "winewayland",
        "winex11",
        "winscard",
        "wpcap",
    ]],
    arch = "x86_64",
    exec_os = "linux",
    env = {},
    identity = "Kron4ek Wine 11.0 amd64 WoW64",
    requirements = "Linux glibc ELF interpreter; glibc, libm, libgcc_s; optional subsystem libraries depend on payload. See README.md.",
)

def _relative(path, field):
    if not path or path.startswith("/") or ".." in path.split("/") or "\\" in path:
        fail("{} must be a nonempty relative archive path: {}".format(field, repr(path)))

def _distribution(tag):
    return struct(**{
        field: getattr(tag, field)
        for field in [
            "urls",
            "sha256",
            "integrity",
            "strip_prefix",
            "loader",
            "server",
            "files",
            "remove",
            "arch",
            "exec_os",
            "env",
            "identity",
            "requirements",
        ]
    })

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
    for path in tag.remove:
        _relative(path, "remove")
    wine_archive(
        name = name,
        urls = tag.urls,
        sha256 = tag.sha256,
        integrity = tag.integrity,
        strip_prefix = tag.strip_prefix,
        remove = tag.remove,
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

    # modules is breadth-first, with the root first. Root choices resolve any
    # conflicting dependency overrides for the same executor platform.
    for mod in ctx.modules:
        seen = {}
        for tag in mod.tags.prebuilt:
            key = tag.exec_os + "_" + tag.arch
            if key in seen:
                fail("duplicate Wine prebuilt for {} in module {}".format(key, mod.name))
            seen[key] = True
            distribution = _distribution(tag)
            overrides = root if mod.is_root else inherited
            if key not in root and key in inherited and inherited[key] != distribution:
                fail("conflicting Wine prebuilts for {}; override this platform in the root module".format(key))
            overrides[key] = distribution

    distributions = {"linux_x86_64": _DEFAULT}
    distributions.update(inherited)
    distributions.update(root)
    registrations = {}
    for key, distribution in sorted(distributions.items()):
        repo = "wine_prebuilt_" + key
        _archive(repo, distribution)
        registrations[key] = {
            "repository": repo,
            "identity": distribution.identity,
            "requirements": distribution.requirements,
            "env": distribution.env,
        }
    registration_repository(name = "wine_toolchains", distributions = json.encode(registrations))
    return ctx.extension_metadata(
        root_module_direct_deps = ["wine_toolchains"] if ctx.root_module_has_non_dev_dependency else [],
        root_module_direct_dev_deps = [] if ctx.root_module_has_non_dev_dependency else ["wine_toolchains"],
        reproducible = True,
    )

wine = module_extension(
    implementation = _impl,
    tag_classes = {
        "prebuilt": tag_class(
            doc = "Override the Wine archive for one executor OS/CPU pair.",
            attrs = {
                "arch": attr.string(mandatory = True, values = ["x86_64", "aarch64"]),
                "exec_os": attr.string(default = "linux", values = ["linux", "osx"]),
                "urls": attr.string_list(mandatory = True, allow_empty = False),
                "sha256": attr.string(),
                "integrity": attr.string(),
                "strip_prefix": attr.string(),
                "loader": attr.string(default = "bin/wine"),
                "server": attr.string(default = "bin/wineserver"),
                "files": attr.string_list(default = ["**"], allow_empty = False),
                "remove": attr.string_list(doc = "Archive paths deleted after extraction; each must exist."),
                "identity": attr.string(mandatory = True),
                "requirements": attr.string(mandatory = True),
                "env": attr.string_dict(doc = "Loader environment; supports {loader_dir} and {server_dir}."),
            },
        ),
    },
)
