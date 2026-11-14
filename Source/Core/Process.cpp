#include "Process.h"

#include <fcntl.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace gcpkg {

namespace {

void closeFd(int fd) {
    if (fd >= 0) {
        ::close(fd);
    }
}

void childSetup(const ExecOptions& o, int captureWriteFd) {
    if (!o.cwd.empty() && ::chdir(o.cwd.c_str()) != 0) {
        std::fprintf(stderr, "gcpkg: chdir(%s): %s\n", o.cwd.c_str(), std::strerror(errno));
        _exit(126);
    }

    for (const auto& [key, value] : o.env) {
        ::setenv(key.c_str(), value.c_str(), 1);
    }

    if (o.capture) {
        ::dup2(captureWriteFd, STDOUT_FILENO);
        int devnull = ::open("/dev/null", O_WRONLY);
        if (devnull >= 0) {
            ::dup2(devnull, STDERR_FILENO);
            ::close(devnull);
        }
    } else if (!o.log.empty()) {
        int fd = ::open(o.log.c_str(), O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd >= 0) {
            ::dup2(fd, STDOUT_FILENO);
            ::dup2(fd, STDERR_FILENO);
            if (fd > STDERR_FILENO) {
                ::close(fd);
            }
        }
    } else if (o.quiet) {
        int devnull = ::open("/dev/null", O_WRONLY);
        if (devnull >= 0) {
            ::dup2(devnull, STDOUT_FILENO);
            ::dup2(devnull, STDERR_FILENO);
            ::close(devnull);
        }
    }
}

}  // namespace

ExecResult execute(const ExecOptions& o) {
    ExecResult result;
    if (o.argv.empty()) {
        result.code = 127;
        return result;
    }

    std::vector<char*> av;
    av.reserve(o.argv.size() + 1);
    for (auto& arg : o.argv) {
        av.push_back(const_cast<char*>(arg.c_str()));
    }
    av.push_back(nullptr);

    int pipefd[2] = {-1, -1};
    if (o.capture && ::pipe(pipefd) != 0) {
        result.code = 125;
        return result;
    }

    pid_t pid = ::fork();
    if (pid < 0) {
        closeFd(pipefd[0]);
        closeFd(pipefd[1]);
        result.code = 125;
        return result;
    }

    if (pid == 0) {
        closeFd(pipefd[0]);
        childSetup(o, pipefd[1]);
        ::execvp(av[0], av.data());
        std::fprintf(stderr, "gcpkg: cannot execute '%s': %s\n", av[0], std::strerror(errno));
        _exit(127);
    }

    closeFd(pipefd[1]);
    if (o.capture) {
        char buffer[4096];
        ssize_t n;
        while ((n = ::read(pipefd[0], buffer, sizeof(buffer))) > 0) {
            result.out.append(buffer, static_cast<std::size_t>(n));
        }
        closeFd(pipefd[0]);
    }

    int status = 0;
    while (::waitpid(pid, &status, 0) < 0 && errno == EINTR) {
    }
    if (WIFEXITED(status)) {
        result.code = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        result.code = 128 + WTERMSIG(status);
    } else {
        result.code = 124;
    }
    return result;
}

}  // namespace gcpkg
