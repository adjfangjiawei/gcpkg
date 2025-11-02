#include "MainProcess/GcpkgMetaCommand/DecompressCommand.h"

#include <archive.h>
#include <archive_entry.h>

#include <filesystem>
#include <iostream>

#include "Basic/Utils/VariableProcessor.h"

namespace fs = std::filesystem;

namespace MainProcess::GcpkgMetaCommand {

    static int copy_data(struct archive *ar, struct archive *aw) {
        int r;
        const void *buff;
        size_t size;
        la_int64_t offset;

        for (;;) {
            r = archive_read_data_block(ar, &buff, &size, &offset);
            if (r == ARCHIVE_EOF) return (ARCHIVE_OK);
            if (r < ARCHIVE_OK) return (r);
            r = archive_write_data_block(aw, buff, size, offset);
            if (r < ARCHIVE_OK) {
                fprintf(stderr, "%s\n", archive_error_string(aw));
                return (r);
            }
        }
    }

    bool Decompress(MetaCommandContext &context, const std::string &file_arg) {
        std::string archive_path_str = Basic::Utils::ExpandVariables(file_arg, context.variables);
        fs::path archive_path(archive_path_str);
        fs::path extract_dir = fs::path(Basic::Utils::ExpandVariables("${build_dir}", context.variables));

        std::cout << "--- MetaCommand: Decompressing " << archive_path << " to " << extract_dir << " ---" << std::endl;

        struct archive *a;
        struct archive *ext;
        struct archive_entry *entry;
        int flags;
        int r;

        flags = ARCHIVE_EXTRACT_TIME;
        flags |= ARCHIVE_EXTRACT_PERM;
        flags |= ARCHIVE_EXTRACT_ACL;
        flags |= ARCHIVE_EXTRACT_FFLAGS;

        a = archive_read_new();
        archive_read_support_format_all(a);
        archive_read_support_filter_all(a);
        ext = archive_write_disk_new();
        archive_write_disk_set_options(ext, flags);
        archive_write_disk_set_standard_lookup(ext);

        if ((r = archive_read_open_filename(a, archive_path_str.c_str(), 10240))) {
            std::cerr << "错误: 打开压缩文件失败。" << std::endl;
            return false;
        }

        // 切换工作目录以在此处解压
        fs::current_path(extract_dir);

        for (;;) {
            r = archive_read_next_header(a, &entry);
            if (r == ARCHIVE_EOF) break;
            if (r < ARCHIVE_OK) fprintf(stderr, "%s\n", archive_error_string(a));
            if (r < ARCHIVE_WARN) return false;

            r = archive_write_header(ext, entry);
            if (r < ARCHIVE_OK)
                fprintf(stderr, "%s\n", archive_error_string(ext));
            else if (archive_entry_size(entry) > 0) {
                r = copy_data(a, ext);
                if (r < ARCHIVE_OK) fprintf(stderr, "%s\n", archive_error_string(ext));
                if (r < ARCHIVE_WARN) return false;
            }
            r = archive_write_finish_entry(ext);
            if (r < ARCHIVE_OK) fprintf(stderr, "%s\n", archive_error_string(ext));
            if (r < ARCHIVE_WARN) return false;
        }

        archive_read_close(a);
        archive_read_free(a);
        archive_write_close(ext);
        archive_write_free(ext);

        // 恢复工作目录
        fs::current_path(Basic::Utils::ExpandVariables("${gcpkg_root}", context.variables));

        std::cout << "--- MetaCommand: Decompression successful ---" << std::endl;
        return true;
    }

}  // namespace MainProcess::GcpkgMetaCommand