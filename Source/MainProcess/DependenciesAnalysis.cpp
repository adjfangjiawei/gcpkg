#include "MainProcess/DependenciesAnalysis.h"

#include <filesystem>
#include <iostream>

#include "MainProcess/InstallProcess.h"

namespace fs = std::filesystem;

namespace MainProcess {

    bool InstallDependencies(const std::string& current_package_spec,
                             const toml::table& port_toml,
                             std::set<std::string>& processed_packages) {
        // 1. 先获取 build_configs 节点
        auto build_configs_node = port_toml.get("build_configs");

        // 2. 检查节点是否存在且为数组
        if (build_configs_node && build_configs_node->is_array()) {
            if (auto build_configs_array = build_configs_node->as_array()) {
                for (const auto& config_node : *build_configs_array) {
                    if (auto config_table = config_node.as_table()) {
                        // 在表格内部安全地获取 dependencies
                        auto deps_node = config_table->get("dependencies");
                        if (deps_node && deps_node->is_array()) {
                            if (auto deps_array = deps_node->as_array()) {
                                std::cout << "--- [" << current_package_spec << "] Resolving dependencies ---"
                                          << std::endl;
                                for (const auto& dep_node : *deps_array) {
                                    std::string dep_spec = dep_node.value_or("");
                                    if (!dep_spec.empty()) {
                                        std::cout << "--- [" << current_package_spec
                                                  << "] Found dependency: " << dep_spec << " ---" << std::endl;
                                        if (!InstallPackage(dep_spec, processed_packages)) {
                                            std::cerr << "错误: 依赖项 '" << dep_spec << "' 安装失败。" << std::endl;
                                            return false;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return true;
    }

    /**
     * @brief [辅助函数] 从单个依赖项的 port 文件中提取 inject 命令并应用到构建计划中。
     *
     * @param dep_spec 依赖项的描述符 (e.g., "gcpkg@preconfigure-inject@latest")
     * @param plan     要被修改的构建计划
     */
    static void ApplyInjectsFromDependency(const std::string& dep_spec, BuildPlan& plan) {
        // --- 使用卫语句 (Guard Clauses) 来避免嵌套 ---

        // 1. 解析依赖项 spec，如果格式不正确则提前退出
        std::vector<std::string> parts;
        std::string part;
        std::istringstream spec_stream(dep_spec);
        while (std::getline(spec_stream, part, '@')) {
            parts.push_back(part);
        }
        if (parts.size() != 3) {
            return;  // 卫语句：格式错误，直接返回
        }

        // 2. 解析依赖项的 port.toml 文件
        fs::path dep_port_path = fs::path("gcpkg/port") / parts[1] / parts[0] / parts[2] / "port.toml";
        toml::table dep_toml;
        try {
            dep_toml = toml::parse_file(dep_port_path.string());
        } catch (const std::exception& e) {
            // std::cerr << "警告: 无法解析依赖项 " << dep_spec << " 的 port 文件: " << e.what() << std::endl;
            return;  // 卫语句：文件解析失败，直接返回
        }

        // 3. 安全地获取 build_configs 数组
        auto build_configs_node = dep_toml.get("build_configs");
        if (!build_configs_node || !build_configs_node->is_array()) {
            return;  // 卫语句：没有 build_configs 或类型错误，直接返回
        }
        auto build_configs_array = build_configs_node->as_array();
        if (!build_configs_array) {
            return;
        }

        // --- 主干逻辑：遍历并提取 inject 命令 ---
        for (const auto& config_node : *build_configs_array) {
            auto config_table = config_node.as_table();
            if (!config_table) {
                continue;  // 跳过非表格的元素
            }

            auto injects_node = config_table->get("inject");
            if (!injects_node || !injects_node->is_array()) {
                continue;  // 这个 config table 中没有 inject 数组，跳过
            }
            auto injects_array = injects_node->as_array();
            if (!injects_array) {
                continue;
            }

            for (const auto& inject_node : *injects_array) {
                auto inject_table = inject_node.as_table();
                if (!inject_table) {
                    continue;  // 跳过非表格的 inject 项
                }

                std::string type = inject_table->get("type")->value_or("");
                auto commands_node = inject_table->get("command");

                if (type.empty() || !commands_node || !commands_node->is_array()) {
                    continue;  // 必要的字段缺失或类型错误，跳过
                }

                if (auto commands = commands_node->as_array()) {
                    std::vector<std::string> cmds_to_inject;
                    for (const auto& cmd : *commands) {
                        cmds_to_inject.push_back(cmd.value_or(""));
                    }
                    // 注入：将命令插入到现有命令的前面
                    plan[type].insert(plan[type].begin(), cmds_to_inject.begin(), cmds_to_inject.end());
                }
            }
        }
    }

    /**
     * @brief [主函数] 从 port_toml 中找到所有依赖，并应用它们的 inject 命令。
     *        (重构后，此函数职责单一，非常清晰)
     */
    void ApplyInjects(BuildPlan& plan, const toml::table& port_toml) {
        // 安全地获取 build_configs 数组
        auto build_configs_node = port_toml.get("build_configs");
        if (!build_configs_node || !build_configs_node->is_array()) {
            return;
        }
        auto build_configs_array = build_configs_node->as_array();
        if (!build_configs_array) {
            return;
        }

        // 遍历所有 build_config
        for (const auto& config_node : *build_configs_array) {
            auto config_table = config_node.as_table();
            if (!config_table) {
                continue;
            }

            // 安全地获取 dependencies 数组
            auto deps_node = config_table->get("dependencies");
            if (!deps_node || !deps_node->is_array()) {
                continue;
            }
            auto deps_array = deps_node->as_array();
            if (!deps_array) {
                continue;
            }

            // 为每个依赖项调用辅助函数
            for (const auto& dep_node : *deps_array) {
                if (auto dep_spec = dep_node.value<std::string>()) {
                    ApplyInjectsFromDependency(*dep_spec, plan);
                }
            }
        }
    }
}  // namespace MainProcess