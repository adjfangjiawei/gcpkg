#pragma once

#include <string>
#include <vector>
namespace Basic {
    namespace DockerExecutor {

        /**
         * @brief 启动一个 Docker 容器，并忠实地传递所有指定的选项。
         *
         * 该函数会构建一个完整的 "docker run [options...]" 命令并执行它。
         * 它不会解析或验证传入的选项，只是将它们拼接起来。
         *
         * @param options 一个字符串向量，包含了所有 'docker run' 命令后的选项和参数。
         *                例如: {"-it", "--rm", "ubuntu:latest", "bash"}
         * @return 如果 system() 调用返回 0 (通常表示成功)，则返回 true；否则返回 false。
         */
        bool RunContainer(const std::vector<std::string>& options);

    }  // namespace DockerExecutor
}  // namespace Basic