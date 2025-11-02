#include "MainProcess/InstallProcess.h"

#include <filesystem>
#include <iostream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#include "Basic/DockerExecutor/ExecuteInContainer.h"
#include "Basic/DockerExecutor/RunContainer.h"
#include "Basic/SystemIntegrate/CommandExecutor/CommandExecutor.h"
#include "Basic/Utils/VariableProcessor.h"
#include "MainProcess/BuildSystemAnalysis.h"
#include "MainProcess/DependenciesAnalysis.h"
#include "MainProcess/GcpkgMetaCommand/DecompressCommand.h"
#include "MainProcess/GcpkgMetaCommand/DownloadCommand.h"
#include "toml++/toml.hpp"

namespace fs = std::filesystem;
namespace CommandExecutor = Basic::SystemIntegrate::CommandExecutor;
namespace Utils = Basic::Utils;
namespace GcpkgMetaCommand = MainProcess::GcpkgMetaCommand;

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

    // 主入口函数
    bool InstallPackage(const std::string& packageSpec) {
        std::set<std::string> processed_packages;
        return InstallPackage(std::move(packageSpec), processed_packages);
    }

    // 内部递归安装函数
    bool InstallPackage(const std::string& packageSpec, std::set<std::string>& processed_packages) {
        if (processed_packages.count(packageSpec)) {
            std::cout << "--- Package '" << packageSpec << "' already processed. Skipping. ---" << std::endl;
            return true;
        }

        std::cout << "=================================================" << std::endl;
        std::cout << "--- Installing package: " << packageSpec << " ---" << std::endl;
        std::cout << "=================================================" << std::endl;

        // 1. 解析包描述符
        std::vector<std::string> parts;
        std::string part;
        std::istringstream spec_stream(packageSpec);
        while (std::getline(spec_stream, part, '@')) {
            parts.push_back(part);
        }
        if (parts.size() != 3) {
            std::cerr << "错误: 包格式无效。应为 'name@namespace@version'。" << std::endl;
            return false;
        }
        const std::string name = parts[0];
        const std::string ns = parts[1];
        const std::string version = parts[2];

        // 2. 加载配置文件
        toml::table gcpkg_toml, port_toml;
        try {
            gcpkg_toml = toml::parse_file("gcpkg.toml");
            fs::path port_path = fs::path("gcpkg/port") / ns / name / version / "port.toml";
            port_toml = toml::parse_file(port_path.string());
        } catch (const toml::parse_error& err) {
            std::cerr << "错误: 解析 TOML 文件失败: " << err << std::endl;
            return false;
        }

        // 3. [新] 递归安装依赖项
        if (!InstallDependencies(packageSpec, port_toml, processed_packages)) {
            return false;  // 依赖安装失败
        }

        // 4. 准备环境变量
        std::map<std::string, std::string> variables;
        fs::path build_dir = fs::path("gcpkg/buildtrees") / name / version;
        fs::path package_dir = fs::path("gcpkg/packages") / name / version;
        fs::path gcpkg_root = fs::absolute(fs::current_path());

        // 安全地从 gcpkg.toml 获取 docker_proxy
        if (auto docker_table = gcpkg_toml["docker"].as_table()) {
            variables["${docker_proxy}"] = docker_table->get("docker_proxy")->value_or("");
        }

        // 安全地从 port_toml 获取 url
        if (auto packages_table = port_toml["packages"].as_table()) {
            if (auto packages_array = packages_table->get("packages")->as_array()) {
                if (!packages_array->empty()) {
                    if (auto first_package = packages_array->get(0)->as_table()) {
                        variables["${url}"] = first_package->get("url")->value_or("");
                    }
                }
            }
        }

        variables["${build_dir}"] = fs::absolute(build_dir).string();
        variables["${package_install_dir}"] = fs::absolute(package_dir).string();
        variables["${gcpkg_root}"] = gcpkg_root.string();

        // 确保目录存在
        fs::create_directories(build_dir);
        fs::create_directories(package_dir);

        // 5. 启动 Docker 容器
        std::string image = "gcc:latest";  // 默认值
        if (auto docker_table = gcpkg_toml["docker"].as_table()) {
            image = docker_table->get("build_mirror")->value_or("gcc:latest");
        }
        std::string container_name = "gcpkg-build-" + name + "-" + version;

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

        std::cout << "--- Starting build container for " << packageSpec << " ---" << std::endl;
        CommandExecutor::executeCommand("docker rm -f " + container_name);  // 确保清理旧容器
        if (!Basic::DockerExecutor::RunContainer(docker_opts)) {
            std::cerr << "错误: 启动 Docker 容器失败。" << std::endl;
            return false;
        }
        DockerContainerGuard guard(container_name);

        // 6. [新] 构建“构建计划”
        BuildPlan build_plan;

        // --- 【核心安全修复】 ---
        // 我们需要一个 toml::table 来引用有效的构建配置。
        // 如果 port_toml 中没有，我们就创建一个空的临时 table，避免后续代码需要处理空指针。
        toml::table build_configs_table;

        // 1. 安全地获取 build_configs 节点
        auto build_configs_node = port_toml.get("build_configs");
        // 2. 检查节点是否存在、是否为数组、是否非空
        if (build_configs_node && build_configs_node->is_array()) {
            if (auto build_configs_array = build_configs_node->as_array()) {
                if (!build_configs_array->empty()) {
                    // 3. 检查数组的第一个元素是否存在且为表格
                    if (auto first_config_node = build_configs_array->get(0)) {
                        if (auto first_config_table = first_config_node->as_table()) {
                            // 4. 只有在所有检查通过后，才进行拷贝赋值
                            build_configs_table = *first_config_table;
                        }
                    }
                }
            }
        }

        // 如果没有找到有效的 build_configs，打印一个提示信息，但继续执行
        if (build_configs_table.empty()) {
            std::cout << "--- Note: No valid [build_configs] table found in " << packageSpec
                      << ". Proceeding without build steps. ---" << std::endl;
        }

        const std::vector<std::string> build_steps = {
            "pre_configure", "configure", "pre_build", "build", "post_build", "pre_install", "install", "post_install"};

        // 6a. 加载当前包的命令
        // 现在可以安全地使用 build_configs_table 了，即使它是空的。
        for (const auto& step : build_steps) {
            auto cmds_node = build_configs_table.get(step);
            if (cmds_node && cmds_node->is_array()) {
                if (auto cmds_array = cmds_node->as_array()) {
                    for (const auto& cmd : *cmds_array) {
                        build_plan[step].push_back(cmd.value_or(""));
                    }
                }
            }
        }

        // 6b. 应用 inject (ApplyInjects 内部也必须是安全的)
        ApplyInjects(build_plan, port_toml);

        // 6c. 应用 export_build_system (传入安全的 build_configs_table)
        ApplyExportedBuildSystem(build_plan, build_configs_table, port_toml, variables);

        // 7. [修改] 按顺序执行“构建计划”
        GcpkgMetaCommand::MetaCommandContext meta_context{"", variables};
        variables["${last_file}"] = "";  // 初始化

        for (const auto& step : build_steps) {
            if (build_plan.count(step) && !build_plan.at(step).empty()) {
                std::cout << "--- Executing step: " << step << " ---" << std::endl;

                std::string work_dir_key = step + "_work_dir";
                std::string work_dir = gcpkg_root.string();

                // 安全地获取 work_dir
                auto work_dir_node = build_configs_table.get(work_dir_key);
                if (work_dir_node && work_dir_node->is_array()) {
                    if (auto work_dir_arr = work_dir_node->as_array()) {
                        if (!work_dir_arr->empty()) {
                            work_dir = work_dir_arr->get(0)->value_or(work_dir);
                        }
                    }
                }

                for (const auto& cmd : build_plan.at(step)) {
                    if (cmd.empty()) continue;

                    // 7a. 元命令分发
                    if (cmd.rfind("inner_download ", 0) == 0) {
                        std::string url_arg = cmd.substr(15);
                        std::string downloaded_file = GcpkgMetaCommand::Download(meta_context, url_arg);
                        if (downloaded_file.empty()) {
                            std::cerr << "错误: 元命令 'inner_download' 执行失败。" << std::endl;
                            return false;
                        }
                        variables["${last_file}"] = downloaded_file;

                    } else if (cmd.rfind("inner_decompress ", 0) == 0) {
                        std::string file_to_decompress = cmd.substr(17);
                        if (!GcpkgMetaCommand::Decompress(meta_context, file_to_decompress)) {
                            std::cerr << "错误: 元命令 'inner_decompress' 执行失败。" << std::endl;
                            return false;
                        }

                    } else {
                        // 7b. 正常命令执行
                        std::string expanded_cmd = Utils::ExpandVariables(cmd, variables);
                        std::string expanded_work_dir = Utils::ExpandVariables(work_dir, variables);

                        if (!Basic::DockerExecutor::ExecuteInContainer(
                                container_name, expanded_work_dir, expanded_cmd)) {
                            std::cerr << "错误: 在步骤 '" << step << "' 中执行命令失败: " << expanded_cmd << std::endl;
                            return false;
                        }
                    }
                }
            }
        }

        processed_packages.insert(packageSpec);
        std::cout << "--- Build process for " << packageSpec << " completed successfully! ---" << std::endl;
        guard.enabled = false;
        CommandExecutor::executeCommand("docker stop " + container_name);  // 成功后停止容器
        return true;
    }

}  // namespace MainProcess