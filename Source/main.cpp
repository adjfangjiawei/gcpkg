#include <cstdlib>
#include <filesystem>  // 用于创建目录 (需要 C++17)
#include <fstream>     // 用于文件写入 (std::ofstream)
#include <iostream>
#include <sstream>  // 用于解析 port 字符串
#include <string>
#include <thread>  // 用于获取 CPU 核心数
#include <vector>

#include "Basic/DockerExecutor/ExecuteInContainer.h"
#include "Basic/SystemIntegrate/CommandExecutor/CommandExecutor.h"
#include "MainProcess/CreatePortFile.h"
#include "MainProcess/CreateProjectFile.h"
#include "MainProcess/InstallProcess.h"
#include "llvm-22/llvm/Support/CommandLine.h"

namespace cl = llvm::cl;

static cl::OptionCategory GcpkgCategory("gcpkg Options");

cl::SubCommand InitCommand("init", "初始化 gcpkg 环境并克隆配置仓库");

// --- 3. 为 'init' 子命令定义专属选项 ---
static cl::opt<std::string> ConfUrl("conf",
                                    cl::desc("指定配置仓库的 Git URL"),
                                    cl::value_desc("url"),
                                    cl::init("https://github.com/adjfangjiawei/gcpkgconf.git"),  // 设置默认值
                                    cl::sub(InitCommand),
                                    cl::cat(GcpkgCategory));

// 'create' 子命令
cl::SubCommand CreateCommand("create", "创建一个新的 gcpkg 项目或 port 文件");
static cl::opt<std::string> ProjectName("project",
                                        cl::desc("创建一个新的 gcpkg 项目配置文件 (gcpkg.toml)"),
                                        cl::value_desc("projectname"),
                                        cl::sub(CreateCommand),
                                        cl::cat(GcpkgCategory));

static cl::opt<std::string> PortSpec("port",
                                     cl::desc("创建一个新的 port 文件 (格式: name@namespace@version)"),
                                     cl::value_desc("spec"),
                                     cl::sub(CreateCommand),
                                     cl::cat(GcpkgCategory));

// 'install' 子命令
cl::SubCommand InstallCommand("install", "安装一个包");
static cl::opt<std::string> PortToInstall(cl::Positional,  // This marks the option as positional
                                          cl::desc("<package-spec>"),
                                          cl::value_desc("name@namespace@version"),
                                          cl::Required,
                                          cl::sub(InstallCommand)  // Associate with the 'install' command
);

// 3. 构建并填充分发映射
using SubCommandCallback = std::function<int(int, char**)>;
llvm::DenseMap<cl::SubCommand*, SubCommandCallback> SubCommandDispatchMap;

int HandleInitSubCommand(int argc, char** argv) {
    std::cout << "'init' 子命令被调用。" << std::endl;
    std::cout << "配置仓库 URL (--conf): " << ConfUrl.getValue() << std::endl;
    std::string git_command = "git clone " + ConfUrl.getValue() + " gcpkg";
    Basic::SystemIntegrate::CommandExecutor::executeCommand(git_command);
    std::cout << "\n克隆完成。仓库内容已下载到 'gcpkg' 目录中。" << std::endl;
    return 0;
}

// 'create' 的处理函数 (新增)
int HandleCreateSubCommand(int argc, char** argv) {
    bool hasProject = ProjectName.getNumOccurrences() > 0;
    bool hasPort = PortSpec.getNumOccurrences() > 0;

    // 检查选项的互斥性
    if (hasProject && hasPort) {
        std::cerr << "错误: --project 和 --port 选项不能同时使用。" << std::endl;
        return 1;
    }
    if (!hasProject && !hasPort) {
        std::cerr << "错误: 'create' 命令需要 --project 或 --port 选项之一。" << std::endl;
        return 1;
    }

    // --- --project 功能实现 ---
    if (hasProject) {
        MainProcess::CreateProjectFile(ProjectName);
    }
    // --- --port 功能实现 ---
    if (hasPort) {
        MainProcess::CreatePortFile(PortSpec);
    }

    return 0;
}

int HandleInstallSubCommand(int argc, char** argv) {
    if (PortToInstall.empty()) {
        std::cerr << "错误: 'install' 命令需要一个包描述符。" << std::endl;
        return 1;
    }

    if (MainProcess::InstallPackage(PortToInstall.getValue())) {
        return 0;  // 成功
    } else {
        return 1;  // 失败
    }
}

// 4. 注册子命令及其回调的函数
void RegisterSubCommands() {
    SubCommandDispatchMap[&InitCommand] = HandleInitSubCommand;
    SubCommandDispatchMap[&CreateCommand] = HandleCreateSubCommand;
    SubCommandDispatchMap[&InstallCommand] = HandleInstallSubCommand;
}

// 主函数
int main(int argc, char** argv) {
    RegisterSubCommands();

    // 隐藏所有不属于 GcpkgCategory 的 LLVM 内部选项，使帮助信息更整洁
    cl::HideUnrelatedOptions(GcpkgCategory);

    // 使用标准的 ParseCommandLineOptions。它会更新所有已定义的 cl::opt 和 cl::SubCommand 的状态。
    cl::ParseCommandLineOptions(argc, argv, "gcpkg - 一个包管理工具\n");

    // 5. 在 main 函数中进行分发
    for (auto const& [subCmd, callback] : SubCommandDispatchMap) {
        if (*subCmd) {
            return callback(argc, argv);
        }
    }
    return 0;
}