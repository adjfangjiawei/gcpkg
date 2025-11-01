#include "Basic/DockerExecutor/RunContainer.h"

#include <cstdlib>   // for system()
#include <iostream>  // for std::cout, std::cerr
#include <sstream>   // for std::stringstream
namespace Basic {
    namespace DockerExecutor {
        bool RunContainer(const std::vector<std::string>& options) {
            // 1. 使用 stringstream 来安全、高效地构建命令
            std::stringstream command_stream;
            command_stream << "docker run";

            for (const auto& opt : options) {
                // 在每个选项前加上空格
                // 注意：这里假设选项本身不包含需要额外引号处理的空格
                command_stream << " " << opt;
            }

            std::string command = command_stream.str();

            // 2. 打印将要执行的命令，便于调试
            std::cout << "Executing command: " << command << std::endl;

            // 3. 使用 system() 执行命令
            int result = system(command.c_str());

            // 4. 检查执行结果并返回
            if (result != 0) {
                std::cerr << "Error: Command execution failed with return code: " << result << std::endl;
                return false;
            }

            std::cout << "Command executed successfully." << std::endl;
            return true;
        }

    }  // namespace DockerExecutor
}  // namespace Basic