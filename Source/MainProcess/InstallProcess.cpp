#include "MainProcess/InstallProcess.h"

#include <filesystem>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include "MainProcess/BuildPlanner.h"
#include "MainProcess/DependenciesAnalysis.h"
#include "MainProcess/EnvironmentSetup.h"
#include "MainProcess/InstallationContext.h"       // 【新】引入上下文
#include "MainProcess/InstallationOrchestrator.h"  // 【新】引入协调器
#include "toml++/toml.hpp"

namespace fs = std::filesystem;

namespace MainProcess {

    // 公共入口函数，接口不变，委托给协调器
    bool InstallPackage(const std::string& packageSpec) {
        return PerformInstallation(packageSpec);
    }

    // 内部递归安装函数，接口不变
    bool InstallPackage(const std::string& packageSpec, std::set<std::string>& processed_packages) {
        // 1. 检查此会话中是否已处理过
        if (processed_packages.count(packageSpec)) {
            std::cout << "--- Package '" << packageSpec << "' already processed in this session. Skipping. ---"
                      << std::endl;
            return true;
        }

        std::cout << "=================================================" << std::endl;
        std::cout << "--- Installing package: " << packageSpec << " ---" << std::endl;
        std::cout << "=================================================" << std::endl;

        // 2. 解析包描述符
        std::vector<std::string> parts;
        std::string part;
        std::istringstream spec_stream(packageSpec);
        while (std::getline(spec_stream, part, '@')) {
            parts.push_back(part);
        }
        if (parts.size() != 3) {
            std::cerr << "错误: 包格式无效。应为 'name@namespace@version'。" << std::endl;
            return false;
        }
        const std::string name = parts[0];
        const std::string ns = parts[1];
        const std::string version = parts[2];

        // 3. 【新增】持久化缓存检查
        fs::path package_dir = fs::path("gcpkg/packages") / name / version;
        if (fs::exists(package_dir)) {
            std::cout << "--- Package '" << packageSpec << "' found in cache. Skipping installation. ---" << std::endl;
            processed_packages.insert(packageSpec);
            return true;
        }

        // 4. 加载配置文件
        toml::table gcpkg_toml, port_toml;
        try {
            gcpkg_toml = toml::parse_file("gcpkg.toml");
            fs::path port_path = fs::path("gcpkg/port") / ns / name / version / "port.toml";
            port_toml = toml::parse_file(port_path.string());
        } catch (const toml::parse_error& err) {
            std::cerr << "错误: 解析 TOML 文件失败: " << err << std::endl;
            return false;
        }

        // 5. 递归安装依赖项 (调用接口不变)
        // InstallDependencies 内部调用的 InstallPackage 会自动获取正确的上下文
        if (!InstallDependencies(packageSpec, port_toml, processed_packages)) {
            return false;
        }

        // 6. 【核心修改】从全局上下文中获取容器名
        std::string containerName = GetCurrentContext()->containerName;

        // 7. 准备环境变量 (委托给 EnvironmentSetup 模块)
        EnvironmentContext env_context = PrepareEnvironmentForPackage(gcpkg_toml, port_toml, name, version);
        auto& variables = env_context.variables;

        // 8. 构建“构建计划” (委托给 BuildPlanner 模块)
        BuildPlan build_plan = CreateBuildPlan(port_toml, variables);

        // 9. 执行“构建计划” (委托给 BuildPlanner 模块)
        if (!ExecuteBuildPlan(containerName, build_plan, port_toml, variables, env_context.env_prefix_command)) {
            std::cerr << "错误: " << packageSpec << " 的构建过程失败。" << std::endl;
            return false;
        }

        processed_packages.insert(packageSpec);
        std::cout << "--- Build process for " << packageSpec << " completed successfully! ---" << std::endl;

        return true;
    }

}  // namespace MainProcess