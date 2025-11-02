#include "MainProcess/BuildSystemAnalysis.h"

#include <filesystem>
#include <iostream>
#include <thread>

#include "Basic/Utils/VariableProcessor.h"

namespace fs = std::filesystem;
namespace Utils = Basic::Utils;

namespace MainProcess {

    void ApplyExportedBuildSystem(BuildPlan& plan,
                                  toml::table& build_configs,
                                  const toml::table& port_toml,
                                  std::map<std::string, std::string>& variables) {
        std::string build_system_name = build_configs["build_system"].value_or("");
        if (build_system_name.empty()) {
            return;  // 没有指定 build_system，直接返回
        }
        std::cout << "--- Using build system: " << build_system_name << " ---" << std::endl;

        // 查找提供该构建系统的依赖
        auto deps_node = port_toml.get("dependencies");
        if (!deps_node || !deps_node->is_array()) return;

        toml::table exporter_toml;
        bool found_exporter = false;

        for (const auto& dep_node : *deps_node->as_array()) {
            std::string dep_spec = dep_node.value_or("");
            if (dep_spec.empty()) continue;

            std::vector<std::string> parts;
            std::string part;
            std::istringstream spec_stream(dep_spec);
            while (std::getline(spec_stream, part, '@')) parts.push_back(part);
            if (parts.size() != 3) continue;

            fs::path dep_port_path = fs::path("port") / parts[1] / parts[0] / parts[2] / "port.toml";

            try {
                toml::table dep_toml = toml::parse_file(dep_port_path.string());
                if (auto exports = dep_toml.get("build_configs")->as_array()) {
                    for (const auto& export_node : *exports) {
                        if (auto export_table = export_node.as_table()) {
                            if (auto systems = export_table->get("export_build_system")->as_array()) {
                                for (const auto& system_node : *systems) {
                                    if (auto system_table = system_node.as_table()) {
                                        if (system_table->get("name")->value_or("") == build_system_name) {
                                            exporter_toml = *system_table;
                                            found_exporter = true;
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                        if (found_exporter) break;
                    }
                }
            } catch (...) {
                continue;
            }
            if (found_exporter) break;
        }

        if (!found_exporter) {
            std::cerr << "警告: 未找到提供 build_system '" << build_system_name << "' 的依赖。" << std::endl;
            return;
        }

        // 定义映射关系
        const std::map<std::string, std::string> command_map = {
            {"configure", "configure_command"}, {"build", "build_command"}, {"install", "intstall_command"}
            // 注意 port.toml 示例中的拼写错误
        };

        // 如果当前包没有定义命令，则从导出系统继承
        for (const auto& pair : command_map) {
            if (plan[pair.first].empty()) {  // 如果没有指定具体命令
                if (auto cmd = exporter_toml.get(pair.second)) {
                    std::string command_template = cmd->value_or("");

                    // 处理选项
                    std::string option_key = pair.second;
                    option_key.replace(option_key.find("_command"), 8, "_option");
                    if (auto options = exporter_toml.get(option_key)->as_array()) {
                        for (const auto& opt : *options) {
                            command_template = command_template + " " + opt.value_or("");
                        }
                    }

                    // 替换变量
                    // 简单替换，实际可能需要更复杂的模板引擎
                    Utils::ReplaceAll(command_template, "${string}", variables["${package_install_dir}"]);
                    Utils::ReplaceAll(command_template, "${Int}", std::to_string(std::thread::hardware_concurrency()));

                    plan[pair.first].push_back(command_template);
                    std::cout << "--- Inherited '" << pair.first << "' command: " << command_template << " ---"
                              << std::endl;
                }
            }
        }
    }

}  // namespace MainProcess