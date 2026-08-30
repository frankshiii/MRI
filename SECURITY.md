# Security Policy

## 报告安全问题

请不要在公开 Issue 中提交 API Key、完整请求内容、私人书籍文件或可识别个人身份的日志。

发现安全问题时，请通过 GitHub 仓库所有者公开资料中的联系方式私下报告，并说明受影响版本、复现方式和可能影响。

## 本地秘密

- `mri.koplugin/config.json` 只用于本地配置，已被 `.gitignore` 排除。
- 发布包只包含 `config.example.json`。
- 建议为 MRI 创建单独且有限额的 API Key。
- 提交前运行 `./scripts/check.sh`，确认没有常见 Key 格式进入源码。
