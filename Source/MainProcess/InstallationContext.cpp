#include "MainProcess/InstallationContext.h"

namespace MainProcess {

    // 使用 thread_local 确保在多线程环境下（如果未来支持）每个线程有自己的上下文，
    // 避免数据竞争。对于单线程应用，其行为与静态变量相同。
    thread_local InstallationContext* g_current_context = nullptr;

    InstallationContext* GetCurrentContext() {
        return g_current_context;
    }

    void SetCurrentContext(InstallationContext* context) {
        g_current_context = context;
    }

}  // namespace MainProcess