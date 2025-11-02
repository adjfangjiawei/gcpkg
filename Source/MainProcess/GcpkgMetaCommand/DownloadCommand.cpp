#include "MainProcess/GcpkgMetaCommand/DownloadCommand.h"

#include <curl/curl.h>

#include <filesystem>
#include <iostream>
#include <thread>

#include "Basic/Utils/VariableProcessor.h"

namespace fs = std::filesystem;

namespace MainProcess::GcpkgMetaCommand {

    // libcurl 写回调函数
    static size_t write_data(void *ptr, size_t size, size_t nmemb, FILE *stream) {
        size_t written = fwrite(ptr, size, nmemb, stream);
        return written;
    }

    std::string Download(MetaCommandContext &context, const std::string &url_arg) {
        std::string expanded_url = Basic::Utils::ExpandVariables(url_arg, context.variables);
        std::string proxy = Basic::Utils::ExpandVariables("${docker_proxy}", context.variables);
        unsigned int num_threads = std::thread::hardware_concurrency();
        if (num_threads == 0) num_threads = 8;  // 默认值

        CURL *curl_handle;
        curl_global_init(CURL_GLOBAL_ALL);
        curl_handle = curl_easy_init();
        if (!curl_handle) {
            std::cerr << "错误: cURL 初始化失败。" << std::endl;
            return "";
        }

        fs::path url_path(expanded_url);
        std::string filename = url_path.filename().string();
        fs::path download_dir =
            fs::path(Basic::Utils::ExpandVariables("${build_dir}", context.variables)) / "_downloads";
        fs::create_directories(download_dir);
        fs::path dest_path = download_dir / filename;

        FILE *fp = fopen(dest_path.string().c_str(), "wb");
        if (!fp) {
            std::cerr << "错误: 无法创建文件 " << dest_path << std::endl;
            curl_easy_cleanup(curl_handle);
            return "";
        }

        std::cout << "--- MetaCommand: Downloading " << expanded_url << " to " << dest_path << " ---" << std::endl;

        curl_easy_setopt(curl_handle, CURLOPT_URL, expanded_url.c_str());
        curl_easy_setopt(curl_handle, CURLOPT_WRITEFUNCTION, write_data);
        curl_easy_setopt(curl_handle, CURLOPT_WRITEDATA, fp);
        if (!proxy.empty()) {
            curl_easy_setopt(curl_handle, CURLOPT_PROXY, proxy.c_str());
        }
        // 注意: libcurl 本身是单线程的。多线程下载需要更复杂的范围请求和块管理。
        // 这里我们仅用一个线程作为示例，但遵循了多线程的配置意图。
        // curl_easy_setopt(curl_handle, CURLOPT_MAXCONNECTS, num_threads);

        CURLcode res = curl_easy_perform(curl_handle);

        fclose(fp);
        curl_easy_cleanup(curl_handle);

        if (res != CURLE_OK) {
            std::cerr << "错误: 下载失败: " << curl_easy_strerror(res) << std::endl;
            return "";
        }

        std::cout << "--- MetaCommand: Download successful ---" << std::endl;
        context.last_downloaded_file = dest_path.string();
        return dest_path.string();
    }

}  // namespace MainProcess::GcpkgMetaCommand