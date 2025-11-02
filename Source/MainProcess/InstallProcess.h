#ifndef GCPKG_INSTALLPROCESS_H
#define GCPKG_INSTALLPROCESS_H

#include <set>
#include <string>

namespace MainProcess {

    // 主入口
    bool InstallPackage(const std::string& packageSpec);

    // 内部递归函数
    bool InstallPackage(const std::string& packageSpec, std::set<std::string>& processed_packages);

}  // namespace MainProcess

#endif  // GCPKG_INSTALLPROCESS_H