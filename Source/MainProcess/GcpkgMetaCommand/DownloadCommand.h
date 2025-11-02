#ifndef GCPKG_DOWNLOADCOMMAND_H
#define GCPKG_DOWNLOADCOMMAND_H

#include <string>

#include "MetaCommand.h"

namespace MainProcess::GcpkgMetaCommand {

    // 返回下载文件的路径
    std::string Download(MetaCommandContext& context, const std::string& url_arg);

}  // namespace MainProcess::GcpkgMetaCommand

#endif  // GCPKG_DOWNLOADCOMMAND_H