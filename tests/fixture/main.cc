// Independent Windows program used to exercise the public rules and adapter.
#define NOMINMAX
#include <windows.h>

#include <cstdlib>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
std::string utf8(const std::wstring &value) {
  int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                 static_cast<int>(value.size()), nullptr, 0,
                                 nullptr, nullptr);
  std::string result(size, '\0');
  if (size)
    WideCharToMultiByte(CP_UTF8, 0, value.data(),
                        static_cast<int>(value.size()), result.data(), size,
                        nullptr, nullptr);
  return result;
}
std::wstring wide(const std::string &value) {
  int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                                 static_cast<int>(value.size()), nullptr, 0);
  if (!size && !value.empty())
    throw std::runtime_error("invalid UTF-8");
  std::wstring result(size, L'\0');
  if (size)
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                        static_cast<int>(value.size()), result.data(), size);
  return result;
}
std::string env(const wchar_t *key) {
  DWORD size = GetEnvironmentVariableW(key, nullptr, 0);
  if (!size)
    return {};
  std::wstring value(size, L'\0');
  GetEnvironmentVariableW(key, value.data(), size);
  value.resize(size - 1);
  return utf8(value);
}
void write_file(const std::wstring &name, const std::string &data) {
  HANDLE file = CreateFileW(name.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE)
    throw std::runtime_error("cannot write fixture output: " + utf8(name));
  DWORD written = 0;
  bool ok = WriteFile(file, data.data(), static_cast<DWORD>(data.size()),
                      &written, nullptr);
  CloseHandle(file);
  if (!ok || written != data.size())
    throw std::runtime_error("incomplete fixture output");
}
std::string read_file(const std::wstring &name) {
  HANDLE file =
      CreateFileW(name.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                  OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE)
    throw std::runtime_error("cannot read fixture input: " + utf8(name));
  std::string result;
  char buffer[4096];
  DWORD size = 0;
  while (ReadFile(file, buffer, sizeof(buffer), &size, nullptr) && size)
    result.append(buffer, size);
  CloseHandle(file);
  return result;
}
std::string json(const std::string &value) {
  std::string result = "\"";
  for (unsigned char c : value) {
    switch (c) {
    case '"':
      result += "\\\"";
      break;
    case '\\':
      result += "\\\\";
      break;
    case '\n':
      result += "\\n";
      break;
    case '\r':
      result += "\\r";
      break;
    case '\t':
      result += "\\t";
      break;
    default:
      if (c < 32) {
        char escape[7];
        std::snprintf(escape, sizeof(escape), "\\u%04x", c);
        result += escape;
      } else
        result += static_cast<char>(c);
    }
  }
  return result + "\"";
}
std::wstring executable() {
  std::wstring result(32768, L'\0');
  DWORD size = GetModuleFileNameW(nullptr, result.data(),
                                  static_cast<DWORD>(result.size()));
  if (!size || size == result.size())
    throw std::runtime_error("cannot find fixture executable");
  result.resize(size);
  return result;
}
void child(const std::wstring &name, bool wait) {
  std::wstring command =
      L"\"" + name + L"\" " + (wait ? L"--sleep" : L"--child");
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(name.c_str(), command.data(), nullptr, nullptr, FALSE, 0,
                      nullptr, nullptr, &startup, &process))
    throw std::runtime_error("child process failed to start");
  if (!wait)
    WaitForSingleObject(process.hProcess, INFINITE);
  DWORD code = 0;
  if (!wait)
    GetExitCodeProcess(process.hProcess, &code);
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  if (!wait && code != 0)
    throw std::runtime_error("child process failed");
}
} // namespace

int main() {
  try {
    int argc = 0;
    wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv)
      throw std::runtime_error("cannot parse command line");
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i)
      args.push_back(utf8(argv[i]));
    LocalFree(argv);
    if (!args.empty() && args[0] == "--child")
      return 0;
    if (!args.empty() && args[0] == "--sleep") {
      Sleep(300000);
      return 0;
    }
    if (args.size() >= 2 && args[0] == "--exit")
      return std::stoi(args[1]);
    for (const auto &arg : args) {
      if (arg == "--contract") {
        if (args.size() < 4 || args[1] != "with spaces" || args[2] != "" ||
            args[3] != "café" || env(L"TEST_TMPDIR").empty() ||
            env(L"XML_OUTPUT_FILE").empty())
          throw std::runtime_error("argument or test protocol contract");
      }
      if (arg == "--isolated") {
        if (GetFileAttributesW(L"C:\\rules-wine-fixture-state") !=
            INVALID_FILE_ATTRIBUTES)
          throw std::runtime_error("shared writable prefix");
        write_file(L"C:\\rules-wine-fixture-state", "private");
      }
    }
    for (auto &arg : args) {
      if (!arg.empty() && arg[0] == '@') {
        arg = read_file(wide(arg.substr(1)));
        while (!arg.empty() &&
               (arg.back() == '\r' || arg.back() == '\n' || arg.back() == ' '))
          arg.pop_back();
      }
    }
    if (!args.empty() && args[0] == "--dll") {
      std::wstring exe = executable();
      HMODULE dll = LoadLibraryW(
          (exe.substr(0, exe.find_last_of(L"\\/")) + L"\\companion.dll")
              .c_str());
      if (!dll)
        throw std::runtime_error("companion DLL unavailable");
      auto answer = reinterpret_cast<int (*)()>(GetProcAddress(dll, "answer"));
      if (!answer || answer() != 42)
        throw std::runtime_error("companion DLL contract");
      FreeLibrary(dll);
      args.erase(args.begin());
    }
    child(executable(), false);
    wchar_t cwd[32768];
    if (!GetCurrentDirectoryW(32768, cwd))
      throw std::runtime_error("cannot find cwd");
    const wchar_t *keys[] = {L"WINEPREFIX",        L"TEST_TMPDIR",
                             L"TEST_SRCDIR",       L"RUNFILES_DIR",
                             L"XML_OUTPUT_FILE",   L"TEST_SHARD_INDEX",
                             L"TEST_TOTAL_SHARDS", L"FIXTURE_VALUE"};
    std::string record = "{\"args\":[";
    for (size_t i = 0; i < args.size(); ++i)
      record += (i ? "," : "") + json(args[i]);
    record += "],\"cwd\":" + json(utf8(cwd)) + ",\"env\":{";
    for (size_t i = 0; i < std::size(keys); ++i)
      record += (i ? "," : "") + json(utf8(keys[i])) + ":" + json(env(keys[i]));
    record += "},\"child\":\"child-ok\"}\n";
    if (std::string shard = env(L"TEST_SHARD_STATUS_FILE"); !shard.empty())
      write_file(wide(shard), "sharding supported\n");
    if (std::string tmp = env(L"TEST_TMPDIR"); !tmp.empty())
      write_file(wide(tmp) + L"\\fixture.tmp", "temporary\n");
    if (std::string xml = env(L"XML_OUTPUT_FILE"); !xml.empty())
      write_file(wide(xml),
                 "<testsuites><testsuite name=\"wine\" tests=\"1\"><testcase "
                 "name=\"fixture\"/></testsuite></testsuites>");
    std::string output;
    for (size_t i = 0; i + 1 < args.size(); ++i)
      if (args[i] == "--output")
        output = args[i + 1];
    if (!output.empty())
      write_file(wide(output), record);
    else
      std::cout << record;
    for (const auto &arg : args)
      if (arg == "--hold") {
        child(executable(), true);
        Sleep(300000);
      }
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "fixture: " << error.what() << '\n';
    return 1;
  }
}
