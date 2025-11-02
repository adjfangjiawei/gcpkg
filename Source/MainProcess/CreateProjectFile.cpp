#include "MainProcess/CreateProjectFile.h"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <thread>

#include "toml++/toml.hpp"

namespace MainProcess {
    bool CreateProjectFile(std::string projectName) {
        std::string project_name = projectName;
        std::cout << "正在为项目 '" << project_name << "' 创建 gcpkg.toml..." << std::endl;

        // 计算CPU核心数
        unsigned int core_count = std::thread::hardware_concurrency();
        if (core_count == 0) {
            core_count = 1;  // 备用值
        }

        // 使用 toml++ 构建器创建 TOML 内容
        toml::table tbl;
        tbl.emplace("global",
                    toml::table{{"conf_repo", ""},
                                {"platform", ""},
                                {"project", project_name},
                                {"build_type", "debug"},
                                {"jobs", static_cast<int64_t>(core_count)}});

        tbl.emplace("docker",
                    toml::table{
                        {"build_mirror", "gcc"},
                        {"docker_proxy", ""},
                    });

        // 写入文件
        std::ofstream file("gcpkg.toml");
        if (!file.is_open()) {
            std::cerr << "错误: 无法打开文件 gcpkg.toml 进行写入。" << std::endl;
            return 1;
        }
        file << tbl;
        file.close();

        std::cout << "gcpkg.toml 文件已成功创建。" << std::endl;

        try {
            std::cout << "正在创建 'buildtrees' 和 'packages' 目录..." << std::endl;
            std::filesystem::create_directory("gcpkg/buildtrees");
            std::filesystem::create_directory("gcpkg/packages");
        } catch (const std::filesystem::filesystem_error& e) {
            std::cerr << "错误: 创建目录失败: " << e.what() << std::endl;
            // 即使目录创建失败，也可能不应该中止整个过程，所以我们只打印错误
        }
        return 0;
    }
}  // namespace MainProcess
