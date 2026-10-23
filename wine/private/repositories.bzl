"""Generate only the call to the declarative registration macro."""

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
