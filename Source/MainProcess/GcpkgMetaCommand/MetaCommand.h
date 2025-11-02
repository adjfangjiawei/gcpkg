#ifndef GCPKG_METACOMMAND_H
#define GCPKG_METACOMMAND_H

#include <map>
#include <string>

namespace MainProcess::GcpkgMetaCommand {

    // 用于在元命令执行期间传递状态
    struct MetaCommandContext {
        std::string last_downloaded_file;               // 用于 ${last_file}
        std::map<std::string, std::string>& variables;  // 引用变量映射以进行扩展
    };

}  // namespace MainProcess::GcpkgMetaCommand

#endif  // GCPKG_METACOMMAND_H