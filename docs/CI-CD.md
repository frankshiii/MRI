# MRI 的 CI/CD 学习指南

## 这套流程在做什么

CI 是持续集成。每次推送代码或创建 Pull Request，GitHub 会在一台干净的 Linux 机器上重新检查项目：

1. 检查所有 Lua 文件能否解析。
2. 检查示例配置是否为有效 JSON。
3. 检查核心插件文件是否齐全。
4. 检查 `config.json` 没有被 Git 跟踪，并扫描常见 API Key 格式。
5. 生成一次安装 ZIP，确认发布过程可以工作。

CD 是持续交付。推送 `v0.1.0` 这类版本标签时，GitHub 会再次执行检查，然后生成 `MRI-0.1.0.zip` 并创建 Release。

## 日常开发

```bash
git switch -c feature/my-change
# 修改和测试
./scripts/check.sh
git add .
git commit -m "Describe the change"
git push -u origin feature/my-change
```

随后在 GitHub 创建 Pull Request。CI 通过后再合并到 `main`。

## 发布版本

先更新 `CHANGELOG.md`，确认 Kindle 实机测试通过，然后运行：

```bash
git switch main
git pull --ff-only
git tag -a v0.1.0 -m "MRI 0.1.0"
git push origin v0.1.0
```

标签推送会触发 `.github/workflows/release.yml`。Release 使用仓库自带的 `GITHUB_TOKEN`，只授予创建 Release 所需的 `contents: write` 权限；普通 CI 只有 `contents: read`。

## 建议的 GitHub 设置

在仓库的 Settings → Branches 中保护 `main`：

- 合并前必须通过 Pull Request。
- 要求 `validate` 检查成功。
- 禁止 force push。
- 由你独立开发时可以暂时不要求审批人数。

在 Settings → Security 中启用 Secret scanning 和 Dependabot alerts。任何 Key 一旦误推到 GitHub，都应立即在服务商后台撤销并重新创建；从 Git 历史删除字符串不能恢复已经泄露的 Key。

## 版本号

- `0.1.1`：兼容修复或小错误。
- `0.2.0`：新增向后兼容功能。
- `1.0.0`：准备好稳定公开使用的版本。

早期开发可以从 `0.1.0` 开始。
