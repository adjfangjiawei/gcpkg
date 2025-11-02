#ifndef GCPKG_DEPENDENCIESANALYSIS_H
#define GCPKG_DEPENDENCIESANALYSIS_H

#include <map>
#include <set>
#include <string>
#include <vector>

#include "toml++/toml.hpp"

namespace MainProcess {

    // 定义一个结构来持有构建计划
    using BuildPlan = std::map<std::string, std::vector<std::string>>;

    // 递归安装所有依赖项
    bool InstallDependencies(const std::string& current_package_spec,
                             const toml::table& port_toml,
                             std::set<std::string>& processed_packages);

    // 应用依赖项中的 inject 规则到当前构建计划
    void ApplyInjects(BuildPlan& plan, const toml::table& port_toml);

}  // namespace MainProcess

#endif  // GCPKG_DEPENDENCIESANALYSIS_H