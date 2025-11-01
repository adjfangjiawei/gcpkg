#pragma once
#include <string>

namespace MainProcess {

    /**
     * @brief 执行 gcpkg install 命令的核心逻辑。
     *
     * @param packageSpec 要安装的包的描述符 (例如, "make@gnu@latest")。
     * @return 如果安装成功，返回 true；否则返回 false。
     */
    bool InstallPackage(std::string packageSpec);

}  // namespace MainProcess