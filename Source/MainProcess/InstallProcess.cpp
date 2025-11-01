#include "MainProcess/InstallProcess.h"

#include <filesystem>
#include <iostream>
#include <map>
#include <sstream>  // for std::istringstream
#include <string>
#include <utility>  // for std::move
#include <vector>

#include "Basic/DockerExecutor/ExecuteInContainer.h"
#include "Basic/DockerExecutor/RunContainer.h"
#include "Basic/SystemIntegrate/CommandExecutor/CommandExecutor.h"
#include "Basic/Utils/VariableProcessor.h"
#include "toml++/toml.hpp"

namespace fs = std::filesystem;

// 命名空间别名，使代码更简洁
namespace CommandExecutor = Basic::SystemIntegrate::CommandExecutor;
namespace Utils = Basic::Utils;

namespace MainProcess {

    // RAII 守卫，确保容器在函数结束时（无论是否成功）被停止和移除
    struct DockerContainerGuard {
        std::string containerName;
        bool enabled = true;

        // 构造函数已经在使用值传递，并通过 std::move 高效地转移所有权，无需修改
        DockerContainerGuard(std::string name) : containerName(std::move(name)), enabled(true) {
        }

        ~DockerContainerGuard() {
            if (!enabled) return;
            std::cout << "--- Cleaning up container '" << containerName << "' ---" << std::endl;
            CommandExecutor::executeCommand("docker stop " + containerName);
            CommandExecutor::executeCommand("docker rm " + containerName);
        }
    };

    // 参数 packageSpec 由 const std::string& 修改为 std::string
    bool InstallPackage(std::string packageSpec) {
        // 1. 解析包描述符
        std::vector<std::string> parts;
        std::string part;
        // istringstream 会处理 packageSpec 的副本
        std::istringstream spec_stream(packageSpec);
        while (std::getline(spec_stream, part, '@')) {
            parts.push_back(part);
        }
        if (parts.size() != 3) {
            std::cerr << "错误: 包格式无效。应为 'name@namespace@version'。" << std::endl;
            return false;
        }
        // 将 const std::string& name = parts[0]; 修改为值传递（创建副本）
        const std::string name = parts[0];
        const std::string ns = parts[1];
        const std::string version = parts[2];

        // 2. 加载配置文件
        toml::table gcpkg_toml, port_toml;
        try {
            gcpkg_toml = toml::parse_file("gcpkg.toml");
            fs::path port_path = fs::path("port") / ns / name / version / "port.toml";
            port_toml = toml::parse_file(port_path.string());
        } catch (const toml::parse_error err) {  // 将 const toml::parse_error& 修改为值传递
            std::cerr << "错误: 解析 TOML 文件失败: " << err << std::endl;
            return false;
        }

        // 3. 准备环境变量
        std::map<std::string, std::string> variables;
        fs::path build_dir = fs::path("buildtrees") / name / version;
        fs::path package_dir = fs::path("packages") / name / version;

        variables["${docker_proxy}"] = gcpkg_toml["docker"]["docker_proxy"].value_or("");
        variables["${url}"] = port_toml["packages"]["packages"][0]["dummy"]["url"].value_or("");
        variables["${build_dir}"] = fs::absolute(build_dir).string();
        variables["${package_install_dir}"] = fs::absolute(package_dir).string();

        // 确保目录存在
        fs::create_directories(build_dir);
        fs::create_directories(package_dir);

        // 4. 启动 Docker 容器
        std::string image = gcpkg_toml["docker"]["build_mirror"].value_or("gcc:latest");
        std::string container_name = "gcpkg-build-" + name + "-" + version;
        fs::path current_path = fs::absolute(fs::current_path());

        std::vector<std::string> docker_opts = {"-itd",
                                                "--name",
                                                container_name,
                                                "--gpus",
                                                "all",
                                                "--network",
                                                "host",
                                                "-v",
                                                current_path.string() + ":" + current_path.string(),
                                                "-w",
                                                current_path.string(),
                                                image,
                                                "sleep",
                                                "infinity"};

        std::cout << "--- Starting build container ---" << std::endl;
        if (!Basic::DockerExecutor::RunContainer(docker_opts)) {
            std::cerr << "错误: 启动 Docker 容器失败。" << std::endl;
            return false;
        }

        // 使用 RAII 守卫确保清理
        DockerContainerGuard guard(container_name);

        // 5. 按顺序执行构建步骤
        const std::vector<std::string> build_steps = {
            "pre_configure", "configure", "pre_build", "build", "post_build", "pre_install", "install", "post_install"};

        // 将 auto& build_configs 修改为 auto，创建 toml::table 的一个完整副本
        auto build_configs = *port_toml["build_configs"].as_array()->get(0)->as_table();

        for (auto step : build_steps) {
            if (auto cmds_node = build_configs.get(step)) {
                if (auto cmds_array = cmds_node->as_array()) {
                    if (cmds_array->empty()) continue;

                    std::cout << "--- Executing step: " << step << " ---" << std::endl;

                    std::string work_dir_key = step + "_work_dir";
                    std::string work_dir = current_path.string();
                    if (auto work_dir_node = build_configs.get(work_dir_key)) {
                        if (auto work_dir_arr = work_dir_node->as_array()) {
                            if (!work_dir_arr->empty()) {
                                work_dir = work_dir_arr->get(0)->value_or(work_dir);
                            }
                        }
                    }

                    for (const auto& cmd_node : *cmds_array) {
                        std::string original_cmd = cmd_node.value_or("");
                        if (original_cmd.empty()) continue;

                        std::string expanded_cmd = Utils::ExpandVariables(original_cmd, variables);
                        std::string expanded_work_dir = Utils::ExpandVariables(work_dir, variables);

                        if (!DockerExecutor::ExecuteInContainer(container_name, expanded_work_dir, expanded_cmd)) {
                            std::cerr << "错误: 在步骤 '" << step << "' 中执行命令失败: " << expanded_cmd << std::endl;
                            return false;
                        }
                    }
                }
            }
        }

        std::cout << "--- Build process completed successfully! ---" << std::endl;
        guard.enabled = false;
        return true;
    }

}  // namespace MainProcess