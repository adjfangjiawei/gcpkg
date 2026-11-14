// gcpkg-intercept: a transparent CC/CXX wrapper.
//
// Build systems are used completely unmodified: we only put this binary in
// $CC / $CXX (via symlinks named `cc` and `c++`). Every compiler invocation is
// appended to a JSONL log (directory + full argv) and then passed through to
// the real compiler. gcpkg later turns those lines into a clangd-compatible
// compile_commands.json, including entries for dependency source files.
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cctype>
#include <cstring>
#include <string>
#include <vector>

namespace {

std::string jsonQuote(const std::string& s) {
    std::string out = "\"";
    char buf[8];
    for (unsigned char ch : s) {
        switch (ch) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (ch < 0x20) {
                    std::snprintf(buf, sizeof(buf), "\\u%04x", ch);
                    out += buf;
                } else {
                    out += static_cast<char>(ch);
                }
        }
    }
    out += "\"";
    return out;
}

std::vector<std::string> splitFlags(const std::string& text) {
    std::vector<std::string> out;
    std::string current;
    char quote = 0;
    for (char ch : text) {
        if (quote) {
            if (ch == quote) quote = 0;
            else current += ch;
        } else if (ch == '\'' || ch == '"') {
            quote = ch;
        } else if (std::isspace(static_cast<unsigned char>(ch))) {
            if (!current.empty()) {
                out.push_back(current);
                current.clear();
            }
        } else {
            current += ch;
        }
    }
    if (!current.empty()) out.push_back(current);
    return out;
}

bool isCxxName(const std::string& base) {
    for (const char* needle : {"c++", "cxx", "g++", "clang++", "clang-cl", "cpp"}) {
        if (base.find(needle) != std::string::npos) {
            return true;
        }
    }
    return false;
}

}  // namespace

int main(int argc, char** argv) {
    const char* modeEnv = std::getenv("GCPKG_INTERCEPT_MODE");
    std::string base = (argc > 0 && argv[0]) ? argv[0] : "cc";
    std::size_t slash = base.find_last_of('/');
    if (slash != std::string::npos) {
        base = base.substr(slash + 1);
    }
    bool cxx = modeEnv ? (std::strcmp(modeEnv, "cxx") == 0) : isCxxName(base);

    const char* real = std::getenv(cxx ? "GCPKG_CXX_REAL" : "GCPKG_CC_REAL");
    if (!real || !*real) {
        real = cxx ? "clang++" : "clang";
    }

    std::vector<std::string> args;
    args.emplace_back(real);
    for (int i = 1; i < argc; ++i) {
        args.emplace_back(argv[i] ? argv[i] : "");
    }
    // Cross flags travel in a dedicated variable so CMake/Meson/Makefile CFLAGS
    // cannot make us lose --target/--sysroot. Deduplicate against argv: many
    // build systems already got the same flags from toolchain.env().
    const char* extra = std::getenv("GCPKG_COMPILER_FLAGS");
    if (extra && *extra) {
        auto insertPos = args.begin() + 1;
        for (const auto& flag : splitFlags(extra)) {
            bool exists = false;
            for (std::size_t i = 1; i < args.size(); ++i) {
                if (args[i] == flag) { exists = true; break; }
            }
            if (!exists) insertPos = args.insert(insertPos, flag) + 1;
        }
    }

    const char* log = std::getenv("GCPKG_INTERCEPT_LOG");
    if (log && *log) {
        char cwd[4096];
        if (!::getcwd(cwd, sizeof(cwd))) {
            std::strcpy(cwd, ".");
        }
        const char* tag = std::getenv("GCPKG_INTERCEPT_TAG");
        std::string line = "{\"directory\":" + jsonQuote(cwd) + ",\"arguments\":[";
        for (std::size_t i = 0; i < args.size(); ++i) {
            if (i) {
                line += ",";
            }
            line += jsonQuote(args[i]);
        }
        line += "],\"tag\":" + jsonQuote(tag ? tag : "") + "}\n";

        int fd = ::open(log, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd >= 0) {
            ::flock(fd, LOCK_EX);
            std::size_t written = 0;
            while (written < line.size()) {
                ssize_t n = ::write(fd, line.data() + written, line.size() - written);
                if (n <= 0) {
                    break;
                }
                written += static_cast<std::size_t>(n);
            }
            ::flock(fd, LOCK_UN);
            ::close(fd);
        }
    }

    std::vector<char*> av;
    av.reserve(args.size() + 1);
    for (auto& a : args) {
        av.push_back(const_cast<char*>(a.c_str()));
    }
    av.push_back(nullptr);
    ::execvp(real, av.data());
    std::fprintf(stderr, "gcpkg-intercept: cannot exec '%s': %s\n", real, std::strerror(errno));
    return 127;
}
