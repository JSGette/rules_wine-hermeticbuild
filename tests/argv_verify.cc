// Assert observable records written by independent Windows fixture processes.
#include "wine/runtime/json.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;

wine::Json read(const fs::path &path) {
  std::ifstream in(path);
  if (!in) {
    throw std::runtime_error("cannot read " + path.string());
  }
  std::string data{std::istreambuf_iterator<char>(in),
                   std::istreambuf_iterator<char>()};
  return wine::JsonParser(data).parse();
}

int main(int argc, char **argv) {
  try {
    if (argc != 1) {
      throw std::runtime_error("unexpected verifier arguments");
    }
    auto config = read(std::string(argv[0]) + ".json");
    for (const auto &[file, expected] : config.fields) {
      auto record = read(fs::path(std::getenv("TEST_SRCDIR")) / file);
      std::vector<std::string> actual;
      const auto &args = record.at("args").elements;
      for (size_t i = 0; i < args.size(); ++i) {
        if (args[i].as_string() == "--output") {
          ++i;
        } else {
          actual.push_back(args[i].as_string());
        }
      }
      if (actual.size() != expected.elements.size()) {
        throw std::runtime_error(
            file + ": argv cardinality " + std::to_string(actual.size()) +
            " != " + std::to_string(expected.elements.size()));
      }
      for (size_t i = 0; i < actual.size(); ++i) {
        const auto &value = expected.elements[i];
        bool matches = false;
        if (value.kind == wine::Json::string) {
          matches = actual[i] == value.as_string();
        } else {
          auto suffix = value.at("suffix").as_string();
          matches = actual[i].size() >= suffix.size() &&
                    actual[i].compare(actual[i].size() - suffix.size(),
                                      suffix.size(), suffix) == 0;
        }
        if (!matches) {
          throw std::runtime_error(file + ": unexpected argv[" +
                                   std::to_string(i) + "] = " + actual[i]);
        }
      }
      if (record.at("child").kind != wine::Json::null_value &&
          record.at("child").as_string() != "child-ok") {
        throw std::runtime_error(file + ": child process failed");
      }
      std::cout << "PASS: " << file << '\n';
    }
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
