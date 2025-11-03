#include "MainProcess/EnvironmentSetup.h"

#include <filesystem>
#include <sstream>
#include <vector>

namespace fs = std::filesystem;

namespace MainProcess {

    EnvironmentContext PrepareEnvironmentForPackage(const toml::table& gcpkg_toml,
                                                    const toml::table& port_toml,
                                                    const std::string& name,
                                                    const std::string& version) {
        EnvironmentContext context;
        std::map<std::string, std::string>& variables = context.variables;

        // 1. 准备基础路径和变量
        fs::path build_dir = fs::path("gcpkg/buildtrees") / name / version;
        fs::path package_dir = fs::path("gcpkg/packages") / name / version;
        fs::path gcpkg_root = fs::absolute(fs::current_path());

        // 安全地从 gcpkg.toml 获取 docker_proxy
        if (auto docker_table = gcpkg_toml["docker"].as_table()) {
            variables["${docker_proxy}"] = docker_table->get("docker_proxy")->value_or("");
        }

        // 安全地从 port_toml 获取 url
        if (auto packages_table = port_toml["packages"].as_table()) {
            if (auto packages_array = packages_table->get("packages")->as_array()) {
                if (!packages_array->empty()) {
                    if (auto first_package = packages_array->get(0)->as_table()) {
                        variables["${url}"] = first_package->get("url")->value_or("");
                    }
                }
            }
        }

        variables["${build_dir}"] = fs::absolute(build_dir).string();
        variables["${package_install_dir}"] = fs::absolute(package_dir).string();
        variables["${gcpkg_root}"] = gcpkg_root.string();

        // 确保目录存在
        fs::create_directories(build_dir);
        fs::create_directories(package_dir);

        // 2. 从依赖项收集路径
        std::vector<std::string> bin_paths, include_paths, lib_paths, pkgconfig_paths;

        if (auto deps_node = port_toml.get("dependencies")) {
            if (auto deps_array = deps_node->as_array()) {
                for (const auto& dep_node : *deps_array) {
                    if (auto dep_table = dep_node.as_table()) {
                        std::string dep_name = dep_table->get("name")->value_or("");
                        std::string dep_version = dep_table->get("version")->value_or("latest");

                        if (!dep_name.empty()) {
                            fs::path dep_package_dir =
                                fs::absolute(fs::path("gcpkg/packages") / dep_name / dep_version);

                            // 检查并添加存在的标准目录路径
                            if (fs::exists(dep_package_dir / "bin"))
                                bin_paths.push_back((dep_package_dir / "bin").string());
                            if (fs::exists(dep_package_dir / "include"))
                                include_paths.push_back((dep_package_dir / "include").string());
                            if (fs::exists(dep_package_dir / "lib"))
                                lib_paths.push_back((dep_package_dir / "lib").string());
                            if (fs::exists(dep_package_dir / "lib64"))
                                lib_paths.push_back((dep_package_dir / "lib64").string());
                            if (fs::exists(dep_package_dir / "lib" / "pkgconfig"))
                                pkgconfig_paths.push_back((dep_package_dir / "lib" / "pkgconfig").string());
                            if (fs::exists(dep_package_dir / "share" / "pkgconfig"))
                                pkgconfig_paths.push_back((dep_package_dir / "share" / "pkgconfig").string());
                        }
                    }
                }
            }
        }

        // 3. 构建 env 命令前缀
        auto join_paths = [](const std::vector<std::string>& paths, const std::string& env_var) -> std::string {
            if (paths.empty()) return "";
            std::stringstream ss;
            for (size_t i = 0; i < paths.size(); ++i) {
                ss << paths[i] << (i == paths.size() - 1 ? "" : ":");
            }
            if (!env_var.empty()) {
                ss << ":$" << env_var;
            }
            return ss.str();
        };

        std::stringstream env_builder;
        bool has_env_vars = false;

        auto add_env_var = [&](const std::string& var_name, const std::vector<std::string>& paths) {
            std::string value = join_paths(paths, var_name);
            if (!value.empty()) {
                env_builder << " " << var_name << "=\"" << value << "\"";
                has_env_vars = true;
            }
        };

        add_env_var("PATH", bin_paths);
        add_env_var("LD_LIBRARY_PATH", lib_paths);
        add_env_var("LIBRARY_PATH", lib_paths);
        add_env_var("C_INCLUDE_PATH", include_paths);
        add_env_var("CPLUS_INCLUDE_PATH", include_paths);
        add_env_var("PKG_CONFIG_PATH", pkgconfig_paths);

        if (has_env_vars) {
            context.env_prefix_command = "env" + env_builder.str() + " ";
        }

        return context;
    }

}  // namespace MainProcess