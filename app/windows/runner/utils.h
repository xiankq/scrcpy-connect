#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// 为进程创建控制台，并将宿主与 Flutter 库的标准输出和错误输出重定向至控制台。
void CreateAndAttachConsole();

// 将空字符结尾的 UTF-16 wchar_t* 转为 UTF-8 std::string；失败返回空字符串。
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// 读取命令行参数并返回 UTF-8 std::vector<std::string>；失败返回空向量。
std::vector<std::string> GetCommandLineArguments();

#endif  // RUNNER_UTILS_H_
