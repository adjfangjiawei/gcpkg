#pragma once

#include <string>
namespace Basic {
    namespace DockerExecutor {

        /**
         * @brief 在正在运行的 Docker 容器中执行一条命令。
         *
         * @param containerName 目标容器的名称。
         * @param workDir 命令在容器内执行时的工作目录。
         * @param command 要执行的命令字符串。
         * @return 如果命令成功执行，返回 true；否则返回 false。
         */
        bool ExecuteInContainer(std::string containerName, std::string workDir, std::string command);

    }  // namespace DockerExecutor
}  // namespace Basic