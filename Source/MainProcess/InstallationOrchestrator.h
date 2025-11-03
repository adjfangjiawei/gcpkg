#ifndef MAINPROCESS_INSTALLATIONORCHESTRATOR_H
#define MAINPROCESS_INSTALLATIONORCHESTRATOR_H

#include <string>

namespace MainProcess {

    /**
     * @brief 执行完整的软件包安装流程，包括所有依赖。
     *
     * 这是安装过程的顶层入口。它会负责：
     * 1. 启动一个用于整个安装会话的共享 Docker 容器。
     * 2. 创建并注册一个全局的 InstallationContext。
     * 3. 调用递归安装流程。
     * 4. 确保在流程结束后（无论成功与否）清理容器和上下文。
     *
     * @param packageSpec 要安装的软件包，格式为 "name@namespace@version"。
     * @return true 如果安装成功，否则返回 false。
     */
    bool PerformInstallation(const std::string& packageSpec);

}  // namespace MainProcess

#endif  // MAINPROCESS_INSTALLATIONORCHESTRATOR_H