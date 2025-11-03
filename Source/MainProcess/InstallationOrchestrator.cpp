#include "MainProcess/InstallationOrchestrator.h"

#include <ctime>
#include <filesystem>
#include <iostream>
#include <set>
#include <vector>

#include "Basic/DockerExecutor/RunContainer.h"
#include "Basic/SystemIntegrate/CommandExecutor/CommandExecutor.h"
#include "MainProcess/InstallProcess.h"  // 引用 InstallPackage(spec, processed_set)
#include "MainProcess/InstallationContext.h"
#include "toml++/toml.hpp"

namespace fs = std::filesystem;
namespace CommandExecutor = Basic::SystemIntegrate::CommandExecutor;

namespace MainProcess {

    // RAII 守卫，用于管理 Docker 容器的生命周期
    struct DockerContainerGuard {
        std::string containerName;
        DockerContainerGuard(std::string name) : containerName(std::move(name)) {
        }
        ~DockerContainerGuard() {
            std::cout << "--- Cleaning up session container '" << containerName << "' ---" << std::endl;
            CommandExecutor::executeCommand("docker stop " + containerName);
            CommandExecutor::executeCommand("docker rm " + containerName);
        }
    };

    // RAII 守卫，用于管理全局上下文的生命周期
    struct ContextGuard {
        ContextGuard(InstallationContext* context) {
            SetCurrentContext(context);
        }
        ~ContextGuard() {
            SetCurrentContext(nullptr);
        }
    };

    bool PerformInstallation(const std::string& packageSpec) {
        // 1. 加载 gcpkg.toml 以获取 Docker 镜像信息
        toml::table gcpkg_toml;
        try {
            gcpkg_toml = toml::parse_file("gcpkg.toml");
        } catch (const toml::parse_error& err) {
            std::cerr << "错误: 解析 gcpkg.toml 文件失败: " << err << std::endl;
            return false;
        }

        // 2. 准备并启动唯一的 Docker 容器
        std::string image = "gcc:latest";
        if (auto docker_table = gcpkg_toml["docker"].as_table()) {
            image = docker_table->get("build_mirror")->value_or("gcc:latest");
        }

        std::string container_name = "gcpkg-session-" + std::to_string(std::time(nullptr));
        fs::path gcpkg_root = fs::absolute(fs::current_path());

        std::vector<std::string> docker_opts = {"-itd",
                                                "--name",
                                                container_name,
                                                "--gpus",
                                                "all",
                                                "--network",
                                                "host",
                                                "-v",
                                                gcpkg_root.string() + ":" + gcpkg_root.string(),
                                                "-w",
                                                gcpkg_root.string(),
                                                image,
                                                "sleep",
                                                "infinity"};

        std::cout << "--- Starting installation session container '" << container_name << "' ---" << std::endl;
        CommandExecutor::executeCommand("docker rm -f " + container_name);
        if (!Basic::DockerExecutor::RunContainer(docker_opts)) {
            std::cerr << "错误: 启动 Docker 容器失败。" << std::endl;
            return false;
        }

        // 使用 RAII 守卫确保容器最终被清理
        DockerContainerGuard containerGuard(container_name);

        // 3. 创建并设置上下文
        InstallationContext context;
        context.containerName = container_name;
        ContextGuard contextGuard(&context);  // RAII 守卫确保上下文被清理

        // 4. 开始递归安装
        std::set<std::string> processed_packages;
        // 调用原始的、未改变接口的内部安装函数
        bool success = InstallPackage(packageSpec, processed_packages);

        if (success) {
            std::cout << "--- Installation session completed successfully! ---" << std::endl;
        } else {
            std::cerr << "--- Installation session failed. Cleaning up. ---" << std::endl;
        }

        return success;
    }

}  // namespace MainProcess