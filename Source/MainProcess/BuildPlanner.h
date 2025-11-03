#ifndef MAINPROCESS_BUILDPLANNER_H
#define MAINPROCESS_BUILDPLANNER_H

#include <map>
#include <string>
#include <vector>

#include "toml++/toml.hpp"

namespace MainProcess {

    using BuildPlan = std::map<std::string, std::vector<std::string>>;

    /**
     * @brief 创建构建计划。
     *
     * 此函数从 port.toml 文件中解析构建步骤，应用 injects 和 export_build_system 规则，
     * 最终生成一个完整的、有序的构建命令计划。
     *
     * @param port_toml 当前软件包的配置文件。
     * @param variables 包含已解析变量的映射表，用于可能的替换。
     * @return 一个表示构建计划的 map。
     */
    BuildPlan CreateBuildPlan(const toml::table& port_toml, std::map<std::string, std::string>& variables);

    /**
     * @brief 执行构建计划。
     *
     * 按预定顺序（pre_configure, configure, ...）执行构建计划中的所有命令。
     * 命令在指定的 Docker 容器内执行。
     *
     * @param container_name 用于执行命令的 Docker 容器的名称。
     * @param plan 要执行的构建计划。
     * @param port_toml 当前软件包的配置文件，用于获取工作目录等信息。
     * @param variables 包含所有环境变量的映射表。
     * @param env_prefix_command 为命令添加的环境变量前缀（例如 "env PATH=... "）。
     * @return true 如果所有步骤都成功执行，否则返回 false。
     */
    bool ExecuteBuildPlan(const std::string& container_name,
                          const BuildPlan& plan,
                          const toml::table& port_toml,
                          std::map<std::string, std::string>& variables,
                          const std::string& env_prefix_command);

}  // namespace MainProcess

#endif  // MAINPROCESS_BUILDPLANNER_H