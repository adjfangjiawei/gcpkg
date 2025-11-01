#include "MainProcess/CreatePortFile.h"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>  // 确保包含

#include "toml++/toml.hpp"

namespace MainProcess {

    // 返回 bool 更符合 C++ 的习惯 (true 表示成功, false 表示失败)
    bool CreatePortFile(std::string portName) {
        std::cout << "正在为 port '" << portName << "' 创建 port.toml..." << std::endl;

        // --- 1. 解析 name@namespace@version (这部分保持不变) ---
        std::vector<std::string> parts;
        std::string part;
        std::istringstream spec_stream(portName);
        while (std::getline(spec_stream, part, '@')) {
            parts.push_back(part);
        }

        if (parts.size() != 3) {
            std::cerr << "错误: port 格式无效。应为 'name@namespace@version'。" << std::endl;
            return false;  // 返回 false 表示失败
        }
        const std::string& name = parts[0];
        const std::string& ns = parts[1];
        const std::string& version = parts[2];

        // --- 2. 构建并创建目录 (这部分保持不变) ---
        std::filesystem::path dir_path = "port";
        dir_path /= ns;
        dir_path /= name;
        dir_path /= version;

        try {
            std::filesystem::create_directories(dir_path);
        } catch (const std::filesystem::filesystem_error& e) {
            std::cerr << "错误: 创建目录失败: " << e.what() << std::endl;
            return false;
        }

        // --- 3. 使用 toml++ 构建器创建 TOML 内容 (修改部分) ---

        // 创建根表
        toml::table root_tbl;

        // 创建 [packages] 表
        // packages = [{ dummy = { url = "", ref = "" } }]
        root_tbl.emplace(
            "packages",
            toml::table{{"packages", toml::array{toml::table{{"dummy", toml::table{{"url", ""}, {"ref", ""}}}}}}});

        // 1. 先创建一个空的 toml::array 作为容器
        toml::array build_configs_array;

        // 2. 创建一个 toml::table，它将成为数组的第一个元素
        toml::table build_config_element = toml::table{{"pre_configure", toml::array{}},
                                                       {"configure", toml::array{}},
                                                       {"pre_build", toml::array{}},
                                                       {"build", toml::array{}},
                                                       {"post_build", toml::array{}},
                                                       {"pre_install", toml::array{}},
                                                       {"install", toml::array{}},
                                                       {"post_install", toml::array{}}};

        // 3. 将这个 table 元素添加到数组中
        build_configs_array.push_back(std::move(build_config_element));

        // 4. 最后，将完整的数组 emplaced 到根表中
        root_tbl.emplace("build_configs", std::move(build_configs_array));

        // --- 4. 写入文件 (修改部分) ---
        std::filesystem::path file_path = dir_path / "port.toml";
        std::ofstream file(file_path);
        if (!file.is_open()) {
            std::cerr << "错误: 无法打开文件 " << file_path << " 进行写入。" << std::endl;
            return false;
        }

        // 将构建好的 toml::table 对象流式传输到文件
        file << root_tbl;
        file.close();

        std::cout << "port.toml 文件已在 '" << dir_path.string() << "' 中成功创建。" << std::endl;
        return true;  // 返回 true 表示成功
    }

}  // namespace MainProcess