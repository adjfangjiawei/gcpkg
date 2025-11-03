#include "MainProcess/BuildPlanner.h"

#include <filesystem>
#include <iostream>

#include "Basic/DockerExecutor/ExecuteInContainer.h"
#include "Basic/Utils/VariableProcessor.h"
#include "MainProcess/BuildSystemAnalysis.h"
#include "MainProcess/GcpkgMetaCommand/DecompressCommand.h"
#include "MainProcess/GcpkgMetaCommand/DownloadCommand.h"

namespace fs = std::filesystem;
namespace Utils = Basic::Utils;
namespace GcpkgMetaCommand = MainProcess::GcpkgMetaCommand;

namespace MainProcess {

    BuildPlan CreateBuildPlan(const toml::table& port_toml, std::map<std::string, std::string>& variables) {
        BuildPlan build_plan;

        // 1. 获取 build_configs 表
        toml::table build_configs_table;
        auto build_configs_node = port_toml.get("build_configs");
        if (build_configs_node && build_configs_node->is_array()) {
            if (auto build_configs_array = build_configs_node->as_array()) {
                if (!build_configs_array->empty()) {
                    if (auto first_config_node = build_configs_array->get(0)) {
                        if (auto first_config_table = first_config_node->as_table()) {
                            build_configs_table = *first_config_table;
                        }
                    }
                }
            }
        }

        if (build_configs_table.empty()) {
            std::cout << "--- Note: No valid [build_configs] table found. Proceeding without build steps. ---"
                      << std::endl;
        }

        // 2. 加载当前包的命令
        const std::vector<std::string> build_steps = {
            "pre_configure", "configure", "pre_build", "build", "post_build", "pre_install", "install", "post_install"};

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

        // 3. 应用 inject 和 export_build_system
        ApplyInjects(build_plan, port_toml);
        ApplyExportedBuildSystem(build_plan, build_configs_table, port_toml, variables);

        return build_plan;
    }

    bool ExecuteBuildPlan(const std::string& container_name,
                          const BuildPlan& plan,
                          const toml::table& port_toml,
                          std::map<std::string, std::string>& variables,
                          const std::string& env_prefix_command) {
        GcpkgMetaCommand::MetaCommandContext meta_context{"", variables};
        variables["${last_file}"] = "";  // 初始化

        const std::vector<std::string> build_steps = {
            "pre_configure", "configure", "pre_build", "build", "post_build", "pre_install", "install", "post_install"};

        fs::path gcpkg_root = fs::absolute(fs::current_path());

        // 1. 获取 build_configs 表以查找工作目录
        toml::table build_configs_table;
        auto build_configs_node = port_toml.get("build_configs");
        if (build_configs_node && build_configs_node->is_array()) {
            if (auto build_configs_array = build_configs_node->as_array()) {
                if (!build_configs_array->empty()) {
                    if (auto first_config_node = build_configs_array->get(0)) {
                        if (auto first_config_table = first_config_node->as_table()) {
                            build_configs_table = *first_config_table;
                        }
                    }
                }
            }
        }

        for (const auto& step : build_steps) {
            if (plan.count(step) && !plan.at(step).empty()) {
                std::cout << "--- Executing step: " << step << " ---" << std::endl;

                std::string work_dir_key = step + "_work_dir";
                std::string work_dir = gcpkg_root.string();

                auto work_dir_node = build_configs_table.get(work_dir_key);
                if (work_dir_node && work_dir_node->is_array()) {
                    if (auto work_dir_arr = work_dir_node->as_array()) {
                        if (!work_dir_arr->empty()) {
                            work_dir = work_dir_arr->get(0)->value_or(work_dir);
                        }
                    }
                }

                for (const auto& cmd : plan.at(step)) {
                    if (cmd.empty()) continue;

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
                        std::string expanded_cmd = Utils::ExpandVariables(cmd, variables);
                        std::string expanded_work_dir = Utils::ExpandVariables(work_dir, variables);
                        std::string final_command = env_prefix_command + expanded_cmd;

                        if (!Basic::DockerExecutor::ExecuteInContainer(
                                container_name, expanded_work_dir, final_command)) {
                            std::cerr << "错误: 在步骤 '" << step << "' 中执行命令失败: " << final_command << std::endl;
                            return false;
                        }
                    }
                }
            }
        }
        return true;
    }

}  // namespace MainProcess