#ifndef RULES_WINE_RUNTIME_JSON_H_
#define RULES_WINE_RUNTIME_JSON_H_

#include <cctype>
#include <cstdint>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>

namespace wine {
struct Json {
  enum Kind { null_value, boolean, string, array, object } kind = null_value;
  bool flag = false;
  std::string text;
  std::vector<Json> elements;
  std::map<std::string, Json> fields;

  const Json &at(const std::string &key) const {
    static const Json empty;
    auto it = fields.find(key);
    return it == fields.end() ? empty : it->second;
  }
  std::string as_string() const {
    if (kind == null_value) {
      return {};
    }
    if (kind != string) {
      throw std::runtime_error("expected JSON string");
    }
    return text;
  }
  bool as_bool() const {
    if (kind == null_value) {
      return false;
    }
    if (kind != boolean) {
      throw std::runtime_error("expected JSON boolean");
    }
    return flag;
  }
};

class JsonParser {
public:
  explicit JsonParser(const std::string &input) : input_(input) {}
  Json parse() {
    Json result = value();
    space();
    if (position_ != input_.size()) {
      fail();
    }
    return result;
  }

private:
  const std::string &input_;
  size_t position_ = 0;
  [[noreturn]] void fail() const {
    throw std::runtime_error("invalid JSON configuration");
  }
  void space() {
    while (position_ < input_.size() &&
           std::isspace(static_cast<unsigned char>(input_[position_]))) {
      ++position_;
    }
  }
  char take() {
    if (position_ == input_.size()) {
      fail();
    }
    return input_[position_++];
  }
  void expect(char c) {
    if (take() != c) {
      fail();
    }
  }
  bool consume(char c) {
    space();
    if (position_ < input_.size() && input_[position_] == c) {
      ++position_;
      return true;
    }
    return false;
  }
  unsigned hex4() {
    unsigned value = 0;
    for (int i = 0; i < 4; ++i) {
      char c = take();
      value <<= 4;
      if (c >= '0' && c <= '9') {
        value |= c - '0';
      } else if (c >= 'a' && c <= 'f') {
        value |= c - 'a' + 10;
      } else if (c >= 'A' && c <= 'F') {
        value |= c - 'A' + 10;
      } else {
        fail();
      }
    }
    return value;
  }
  static void utf8(std::string &out, unsigned c) {
    if (c < 0x80) {
      out += static_cast<char>(c);
    } else if (c < 0x800) {
      out += static_cast<char>(0xc0 | (c >> 6));
      out += static_cast<char>(0x80 | (c & 63));
    } else if (c < 0x10000) {
      out += static_cast<char>(0xe0 | (c >> 12));
      out += static_cast<char>(0x80 | ((c >> 6) & 63));
      out += static_cast<char>(0x80 | (c & 63));
    } else {
      out += static_cast<char>(0xf0 | (c >> 18));
      out += static_cast<char>(0x80 | ((c >> 12) & 63));
      out += static_cast<char>(0x80 | ((c >> 6) & 63));
      out += static_cast<char>(0x80 | (c & 63));
    }
  }
  std::string quoted() {
    expect('"');
    std::string out;
    while (true) {
      char c = take();
      if (c == '"') {
        return out;
      }
      if (static_cast<unsigned char>(c) < 32) {
        fail();
      }
      if (c != '\\') {
        out += c;
        continue;
      }
      c = take();
      switch (c) {
      case '"':
        out += '"';
        break;
      case '\\':
        out += '\\';
        break;
      case '/':
        out += '/';
        break;
      case 'b':
        out += '\b';
        break;
      case 'f':
        out += '\f';
        break;
      case 'n':
        out += '\n';
        break;
      case 'r':
        out += '\r';
        break;
      case 't':
        out += '\t';
        break;
      case 'u': {
        unsigned code = hex4();
        if (code >= 0xd800 && code <= 0xdbff) {
          expect('\\');
          expect('u');
          unsigned low = hex4();
          if (low < 0xdc00 || low > 0xdfff) {
            fail();
          }
          code = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00);
        } else if (code >= 0xdc00 && code <= 0xdfff) {
          fail();
        }
        utf8(out, code);
        break;
      }
      default:
        fail();
      }
    }
  }
  Json value() {
    space();
    Json result;
    char c = take();
    if (c == '"') {
      --position_;
      result.kind = Json::string;
      result.text = quoted();
    } else if (c == '[') {
      result.kind = Json::array;
      if (!consume(']')) {
        do {
          result.elements.push_back(value());
        } while (consume(','));
        space();
        expect(']');
      }
    } else if (c == '{') {
      result.kind = Json::object;
      if (!consume('}')) {
        do {
          space();
          std::string key = quoted();
          space();
          expect(':');
          result.fields[key] = value();
        } while (consume(','));
        space();
        expect('}');
      }
    } else {
      const char *literal = c == 't'   ? "rue"
                            : c == 'f' ? "alse"
                            : c == 'n' ? "ull"
                                       : nullptr;
      if (!literal) {
        fail();
      }
      while (*literal) {
        if (take() != *literal++) {
          fail();
        }
      }
      result.kind = c == 'n' ? Json::null_value : Json::boolean;
      result.flag = c == 't';
    }
    return result;
  }
};
} // namespace wine
#endif
