"""Wine archive and toolchain registration repositories."""

load("@bazel_tools//tools/build_defs/repo:cache.bzl", "DEFAULT_CANONICAL_ID_ENV", "get_default_canonical_id")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "get_auth")

def _impl(ctx):
    ctx.file("BUILD.bazel", "\n".join([
        'load("@rules_wine//wine/private:registrations.bzl", "register_runners")',
        'package(default_visibility = ["//visibility:public"])',
        "register_runners(distributions = " + repr(json.decode(ctx.attr.distributions)) + ")",
        "",
    ]))

registration_repository = repository_rule(
    implementation = _impl,
    attrs = {
        "distributions": attr.string(mandatory = True),
    },
)

def _archive_impl(ctx):
    ctx.download_and_extract(
        url = ctx.attr.urls,
        sha256 = ctx.attr.sha256,
        integrity = ctx.attr.integrity,
        stripPrefix = ctx.attr.strip_prefix,
        canonical_id = get_default_canonical_id(ctx, ctx.attr.urls),
        auth = get_auth(ctx, ctx.attr.urls),
    )

    # Wine finds its modules through realpath(), outside the action's declared
    # inputs, so leaving them out of the files glob does not hide them.
    for path in ctx.attr.remove:
        if not ctx.delete(path):
            fail("{}: remove path is not in the archive: {}".format(ctx.name, path))
    ctx.file("BUILD.bazel", ctx.attr.build_file_content)

wine_archive = repository_rule(
    implementation = _archive_impl,
    attrs = {
        "urls": attr.string_list(mandatory = True),
        "sha256": attr.string(),
        "integrity": attr.string(),
        "strip_prefix": attr.string(),
        "remove": attr.string_list(),
        "build_file_content": attr.string(mandatory = True),
    },
    environ = [DEFAULT_CANONICAL_ID_ENV],
)
