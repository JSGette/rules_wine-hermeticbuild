// A source-built Windows tool using Bazel's normal runfiles library.
#include "rules_cc/cc/runfiles/runfiles.h"

#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>

using rules_cc::cc::runfiles::Runfiles;

std::string read(const std::string &name) {
  std::ifstream input(name);
  if (!input) {
    throw std::runtime_error("cannot read runfile: " + name);
  }
  return {std::istreambuf_iterator<char>(input),
          std::istreambuf_iterator<char>()};
}

int main(int argc, char **argv) {
  try {
    if (argc != 2) {
      throw std::runtime_error("expected output path");
    }
    std::string error;
    std::unique_ptr<Runfiles> files(
        Runfiles::Create(argv[0], BAZEL_CURRENT_REPOSITORY, &error));
    if (!files) {
      throw std::runtime_error(error);
    }
    auto license =
        files->Rlocation("platforms/LICENSE", BAZEL_CURRENT_REPOSITORY);
    if (read(license).find("Apache License") == std::string::npos ||
        read(files->Rlocation("root-alias.txt")) != "alias-only data\n") {
      throw std::runtime_error("repository mapping or alias runfiles contract");
    }
    std::ofstream output(argv[1]);
    output << "{\"args\":[\"mapped external\",\"alias-only data\"]}\n";
    if (!output) {
      throw std::runtime_error("cannot write runfiles record");
    }
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
