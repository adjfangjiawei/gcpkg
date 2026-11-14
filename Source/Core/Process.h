#pragma once

#include <map>
#include <string>
#include <vector>

namespace gcpkg {

struct ExecOptions {
    std::vector<std::string> argv;
    std::string cwd;
    std::map<std::string, std::string> env;  // merged over the inherited environment
    std::string log;                         // stdout+stderr appended to this file
    bool quiet = false;                      // discard output when no log is given
    bool capture = false;                    // capture stdout into ExecResult::out
};

struct ExecResult {
    int code = -1;
    std::string out;
};

// argv-based process execution: never goes through a shell, so port scripts
// cannot accidentally inject commands through file names or versions.
ExecResult execute(const ExecOptions& options);

}  // namespace gcpkg
