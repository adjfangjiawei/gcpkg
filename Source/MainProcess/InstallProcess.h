#ifndef MAINPROCESS_INSTALLPROCESS_H
#define MAINPROCESS_INSTALLPROCESS_H

#include <set>
#include <string>

namespace MainProcess {

    /**
     * @brief 安装一个软件包 (公共入口)。
     *
     * 接口与原始代码完全相同。
     * 实现上，它现在委托给 InstallationOrchestrator 来管理整个安装会话。
     *
     * @param packageSpec 要安装的包，格式为 "name@namespace@version"。
     * @return true 如果安装成功，否则返回 false。
     */
    bool InstallPackage(const std::string& packageSpec);

    /**
     * @brief 递归地安装一个软件包及其依赖项 (内部实现)。
     *
     * 接口与原始代码完全相同。
     * 实现上，它现在从全局上下文中获取共享的 Docker 容器名，
     * 而不是通过参数接收。
     *
     * @param packageSpec 要安装的包，格式为 "name@namespace@version"。
     * @param processed_packages 一个集合，用于跟踪在此次安装会话中已处理的包。
     * @return true 如果安装成功，否则返回 false。
     */
    bool InstallPackage(const std::string& packageSpec, std::set<std::string>& processed_packages);

}  // namespace MainProcess

#endif  // MAINPROCESS_INSTALLPROCESS_H