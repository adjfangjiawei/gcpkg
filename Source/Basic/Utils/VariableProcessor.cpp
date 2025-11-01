#include "Basic/Utils/VariableProcessor.h"

namespace Basic::Utils {

    std::string ExpandVariables(const std::string& input, const std::map<std::string, std::string>& variables) {
        std::string result = input;
        for (const auto& pair : variables) {
            const std::string& key = pair.first;
            const std::string& value = pair.second;
            size_t start_pos = 0;
            while ((start_pos = result.find(key, start_pos)) != std::string::npos) {
                result.replace(start_pos, key.length(), value);
                start_pos += value.length();  // 移动到替换后的文本末尾，防止无限循环
            }
        }
        return result;
    }

}  // namespace Basic::Utils