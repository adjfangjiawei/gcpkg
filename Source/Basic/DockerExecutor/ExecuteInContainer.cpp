#include "Basic/DockerExecutor/ExecuteInContainer.h"

#include <sstream>

#include "Basic/SystemIntegrate/CommandExecutor/CommandExecutor.h"  // 假设 executeCommand 在此
namespace Basic {
    namespace DockerExecutor {

        bool ExecuteInContainer(std::string containerName, std::string workDir, std::string command) {
            std::stringstream cmd_stream;
            // 使用 -w 设置工作目录，并用 bash -c 来正确处理复杂的 shell 命令
            cmd_stream << "docker exec -w " << workDir << " " << containerName << " bash -c \"" << command << "\"";
            std::string cmd = cmd_stream.str();

            // 调用我们已有的命令执行器
            return Basic::SystemIntegrate::CommandExecutor::executeCommand(cmd);
        }

    }  // namespace DockerExecutor
}  // namespace Basic