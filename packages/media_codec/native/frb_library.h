#pragma once
#include <string>
#if defined(_WIN32)
#include <windows.h>
#else
#include <dlfcn.h>
#endif

inline std::string mc_native_library_path(void* anchor) {
  if (!anchor) return {};
#if defined(_WIN32)
  HMODULE module = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                         GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                         reinterpret_cast<LPCWSTR>(anchor), &module)) return {};
  wchar_t path[32768];
  const DWORD length = GetModuleFileNameW(module, path, 32768);
  if (!length || length >= 32768) return {};
  const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, path,
                                     static_cast<int>(length), nullptr, 0, nullptr, nullptr);
  if (size <= 0) return {};
  std::string result(static_cast<size_t>(size), '\0');
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, path,
                          static_cast<int>(length), result.data(), size,
                          nullptr, nullptr) != size) return {};
  return result;
#else
  Dl_info info{};
  if (!dladdr(anchor, &info) || !info.dli_fname || !*info.dli_fname) return {};
  return info.dli_fname;
#endif
}
