#include "Basic/SystemIntegrate/CommandExecutor/CommandExecutor.h"

#include <stdlib.h>
namespace Basic {
    namespace SystemIntegrate {
        namespace CommandExecutor {
            bool executeCommand(const std::string& command) {
                std::cout << "执行命令: " << command << std::endl;
                int result = system(command.c_str());
                if (result != 0) {
                    std::cerr << "错误: 命令执行失败，返回值为: " << result << std::endl;
                }
                return true;
            }
        }  // namespace CommandExecutor
    }  // namespace SystemIntegrate
}  // namespace Basic