# MRI for KOReader

[![CI](https://github.com/frankshiii/MRI/actions/workflows/ci.yml/badge.svg)](https://github.com/frankshiii/MRI/actions/workflows/ci.yml)
[![License: AGPL-3.0-or-later](https://img.shields.io/badge/License-AGPL--3.0--or--later-blue.svg)](LICENSE)

MRI 是一个面向 Kindle 小屏和 KOReader 的 EPUB AI 阅读助手，重点解决长篇阅读中的人物回忆、章节回顾、地点与概念整理，以及基于当前阅读进度的问答。

项目目前处于早期测试阶段，兼容基线为 KOReader `v2025.08`，正式目标基线为 `v2026.07`。目前只支持 EPUB。

## 功能

- 选中文字后直接使用 MRI，自动识别人名、地点、概念或段落。
- 回顾当前章、前两章或从开头到当前位置，并默认限制剧透。
- 生成人物表、地点表和概念表；名著可使用自动混合知识，小众作品自动扩大书内样本。
- 对相同问题和条目使用每本书独立的本地缓存。
- 支持 OpenAI、Anthropic、Gemini、Qwen、DeepSeek、Kimi 和自定义兼容接口。
- API Key、模型和接口地址可以在电脑上配置。

## 安装

从 [Releases](https://github.com/frankshiii/MRI/releases) 下载 ZIP，解压后确认目录名称为 `mri.koplugin`，复制到：

```text
koreader/plugins/mri.koplugin
```

完整退出并重新启动 KOReader。

如需在电脑填写 API Key，将 `mri.koplugin/config.example.json` 复制为 `mri.koplugin/config.json`，再填写自己的配置。`config.json` 已被 Git 忽略，也不会进入发布包。

macOS 开发者可以双击 `同步 MRI 到 Kindle.command`，将当前源码同步到已连接的 Kindle。脚本会把旧的 `aireader.koplugin` 目录迁移为 `mri.koplugin`，插件也会迁移旧版设置和每本书缓存。

详细功能与隐私说明见 [中文文档](mri.koplugin/README.md)；English documentation is available [here](mri.koplugin/README.en.md).

## 开发与发布

```bash
./scripts/check.sh
./scripts/package.sh dev
```

每次推送和 Pull Request 都会运行 CI。推送 `v0.1.0` 形式的标签后，CD 会自动检查源码、生成安装 ZIP，并创建 GitHub Release。完整流程见 [CI/CD 学习指南](docs/CI-CD.md)。

## 贡献

欢迎提交问题和 Pull Request。开始前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [SECURITY.md](SECURITY.md)。

## 许可

Copyright (C) 2026 Frank

以 GNU Affero General Public License v3.0 或更新版本发布，详见 [LICENSE](LICENSE)。
