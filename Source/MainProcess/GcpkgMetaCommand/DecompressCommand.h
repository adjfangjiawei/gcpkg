#ifndef GCPKG_DECOMPRESSCOMMAND_H
#define GCPKG_DECOMPRESSCOMMAND_H

#include <string>

#include "MetaCommand.h"

namespace MainProcess::GcpkgMetaCommand {

    bool Decompress(MetaCommandContext &context, const std::string &file_arg);

}  // namespace MainProcess::GcpkgMetaCommand

#endif  // GCPKG_DECOMPRESSCOMMAND_H