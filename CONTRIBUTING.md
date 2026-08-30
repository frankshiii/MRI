# Contributing to MRI

感谢你愿意改进 MRI。

## 开发流程

1. 从 `main` 创建短分支，例如 `feature/cache-status` 或 `fix/deepseek-timeout`。
2. 保持改动范围清楚，不要提交 API Key、书籍文件、KOReader 设置或运行日志。
3. 在本地运行 `./scripts/check.sh`。
4. 必要时用 `./同步 MRI 到 Kindle.command` 在真实设备测试。
5. 提交 Pull Request，写明问题、改动、测试设备、KOReader 版本和验证结果。

## 代码约定

- Lua 使用四个空格缩进。
- 用户可见文字需要同时加入 `mri.koplugin/i18n.lua`。
- 保持 EPUB 阅读边界和剧透规则。
- 新增网络请求时记录成功、失败和耗时，绝不记录 API Key 或完整书中文字。
- 修改缓存结构时提升对应缓存版本，并考虑旧数据迁移。

## 提交信息

建议使用简短动词开头，例如：

```text
Add cache migration for MRI rename
Fix timeout handling for DeepSeek
Document release workflow
```
