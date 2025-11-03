#ifndef MAINPROCESS_ENVIRONMENTSETUP_H
#define MAINPROCESS_ENVIRONMENTSETUP_H

#include <map>
#include <string>

#include "toml++/toml.hpp"

namespace MainProcess {

    struct EnvironmentContext {
        std::map<std::string, std::string> variables;
        std::string env_prefix_command;
    };

    /**
     * @brief 为指定的软件包准备构建环境。
     *
     * 该函数负责填充所有必要的环境变量，包括：
     * - 从 gcpkg.toml 和 port.toml 中提取的变量（如 docker_proxy, url）。
     * - 基础路径变量（如 build_dir, package_install_dir, gcpkg_root）。
     * - 从所有依赖项中收集并合并的环境变量（PATH, LD_LIBRARY_PATH 等）。
     *
     * @param gcpkg_toml 全局配置文件。
     * @param port_toml 当前软件包的配置文件。
     * @param name 软件包名称。
     * @param version 软件包版本。
     * @return 包含环境变量映射表和 env 命令前缀的结构体。
     */
    EnvironmentContext PrepareEnvironmentForPackage(const toml::table& gcpkg_toml,
                                                    const toml::table& port_toml,
                                                    const std::string& name,
                                                    const std::string& version);

}  // namespace MainProcess

#endif  // MAINPROCESS_ENVIRONMENTSETUP_H