#include "MainProcess/DependenciesAnalysis.h"

#include <filesystem>
#include <iostream>

#include "MainProcess/InstallProcess.h"

namespace fs = std::filesystem;

namespace MainProcess {

    bool InstallDependencies(const std::string& current_package_spec,
                             const toml::table& port_toml,
                             std::set<std::string>& processed_packages) {
        if (auto deps_node = port_toml.get("dependencies")) {
            if (auto deps_array = deps_node->as_array()) {
                std::cout << "--- [" << current_package_spec << "] Resolving dependencies ---" << std::endl;
                for (const auto& dep_node : *deps_array) {
                    std::string dep_spec = dep_node.value_or("");
                    if (!dep_spec.empty()) {
                        std::cout << "--- [" << current_package_spec << "] Found dependency: " << dep_spec << " ---"
                                  << std::endl;
                        if (!InstallPackage(dep_spec, processed_packages)) {
                            std::cerr << "错误: 依赖项 '" << dep_spec << "' 安装失败。" << std::endl;
                            return false;
                        }
                    }
                }
            }
        }
        return true;
    }

    void ApplyInjects(BuildPlan& plan, const toml::table& port_toml) {
        if (auto deps_node = port_toml.get("dependencies")) {
            if (auto deps_array = deps_node->as_array()) {
                for (const auto& dep_node : *deps_array) {
                    std::string dep_spec = dep_node.value_or("");
                    if (dep_spec.empty()) continue;

                    // 解析依赖项的 spec
                    std::vector<std::string> parts;
                    std::string part;
                    std::istringstream spec_stream(dep_spec);
                    while (std::getline(spec_stream, part, '@')) parts.push_back(part);
                    if (parts.size() != 3) continue;

                    fs::path dep_port_path = fs::path("port") / parts[1] / parts[0] / parts[2] / "port.toml";

                    try {
                        toml::table dep_toml = toml::parse_file(dep_port_path.string());
                        if (auto injects = dep_toml.get("inject")->as_array()) {
                            for (const auto& inject_node : *injects) {
                                auto inject_table = inject_node.as_table();
                                std::string type = (*inject_table)["type"].value_or("");
                                auto commands = (*inject_table)["command"].as_array();

                                if (!type.empty() && commands) {
                                    std::vector<std::string> cmds_to_inject;
                                    for (const auto& cmd : *commands) cmds_to_inject.push_back(cmd.value_or(""));

                                    // 注入：将命令插入到现有命令的前面
                                    plan[type].insert(plan[type].begin(), cmds_to_inject.begin(), cmds_to_inject.end());
                                }
                            }
                        }
                    } catch (const std::exception& e) {
                        // 忽略解析失败的依赖项
                    }
                }
            }
        }
    }

}  // namespace MainProcess