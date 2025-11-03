#ifndef MAINPROCESS_INSTALLATIONCONTEXT_H
#define MAINPROCESS_INSTALLATIONCONTEXT_H

#include <string>

namespace MainProcess {

    // 保存单次安装会话期间共享状态的结构体
    struct InstallationContext {
        std::string containerName;
    };

    /**
     * @brief 获取当前正在进行的安装会话的上下文。
     *
     * @warning 如果没有活动的安装会话，调用此函数将导致未定义行为。
     *          它应该只在由 InstallationOrchestrator 管理的生命周期内被调用。
     * @return 指向当前上下文的指针。
     */
    InstallationContext* GetCurrentContext();

    /**
     * @brief 设置当前安装会话的上下文。
     *
     * 这个函数由 InstallationOrchestrator 在会话开始时调用。
     *
     * @param context 指向当前会话上下文的指针。
     */
    void SetCurrentContext(InstallationContext* context);

}  // namespace MainProcess

#endif  // MAINPROCESS_INSTALLATIONCONTEXT_H