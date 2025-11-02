#pragma once

#include <map>
#include <string>

namespace Basic::Utils {

    /**
     * @brief 替换字符串中的 ${variable} 占位符。
     *
     * @param input 包含占位符的输入字符串。
     * @param variables 一个从变量名 (如 "${docker_proxy}")到其值的映射。
     * @return 替换后的字符串。
     */
    std::string ExpandVariables(const std::string& input, const std::map<std::string, std::string>& variables);

    // Replaces all occurrences of a substring within a string.
    void ReplaceAll(std::string& str, const std::string& from, const std::string& to);

}  // namespace Basic::Utils