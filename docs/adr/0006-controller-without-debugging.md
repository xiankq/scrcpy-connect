---
status: accepted
---

# 主控不要求开启调试

主控只使用普通应用身份及正常平台授权，不提供依赖本机 ADB 的增强入口；普通应用子进程仍可使用。被控 shell 权限不能转授主控，前台服务或更换语言也不能绕过 Android 后台剪贴板限制。被控调试仍按[免安装模型](0001-apk-free-controlled-device.md)授权。
