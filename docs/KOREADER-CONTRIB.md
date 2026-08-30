# 将 MRI 提交到 KOReader contrib

[中文](#中文) | [English](#english)

## 中文

### 收录条件

KOReader `contrib` 收录维护范围以外的第三方插件。它当前要求：

- 插件在合并时可以正常工作，不接收尚未跑通或已经废弃的项目。
- 每个插件以 Git submodule 指向自己的上游仓库。
- 上游仓库提供功能说明和设备或 KOReader 版本兼容信息。

MRI 已有公开仓库、双语文档、许可证和 CI。提交前还要完成目标 KOReader 版本与 Kindle 实机验证，并发布一个稳定标签。

### 为什么需要专用分支

`contrib` 会把上游仓库直接检出为 `mri.koplugin`。KOReader 需要在该目录根层看到 `_meta.lua` 和 `main.lua`。MRI 的 `main` 分支把插件放在 `mri.koplugin/` 子目录，因此使用一个只包含该子目录历史的 `koreader-contrib` 分支。

这样可以保留当前的开发脚本、CI 和文档结构，同时让 submodule 得到正确的插件目录。

### 发布插件分支

完成实机测试并更新版本记录后，在 MRI 仓库运行：

```bash
git switch main
git pull --ff-only
git subtree push --prefix=mri.koplugin origin koreader-contrib
```

首次运行会创建远程 `koreader-contrib` 分支。以后每次稳定发布后重复最后一条命令即可更新它。

检出该分支后，目录根层应直接包含：

```text
_meta.lua
main.lua
api_client.lua
prompts.lua
...
```

### 向 contrib 提交 Pull Request

先 fork `koreader/contrib`，再在 fork 中添加 MRI：

```bash
gh repo fork koreader/contrib --clone
cd contrib
git switch -c add-mri
git submodule add -b koreader-contrib https://github.com/frankshiii/MRI-Mobile_Reading_Intelligence.git mri.koplugin
git add .gitmodules mri.koplugin
git commit -m "Add MRI plugin"
git push -u origin add-mri
gh pr create --repo koreader/contrib
```

Pull Request 说明应包含：

- MRI 解决的问题和主要功能。
- 已测试的 Kindle 型号与 KOReader 版本。
- EPUB 支持范围和已知限制。
- 网络请求、API Key、本地缓存及剧透边界说明。
- 上游仓库和稳定 Release 链接。

`contrib` 中的 submodule 会固定到提交时的版本。MRI 后续发布新版本时，需要在 `contrib` fork 中更新 submodule 指针并再次提交 Pull Request。

## English

### Inclusion requirements

KOReader `contrib` hosts third-party plugins outside KOReader's core maintenance scope. Its current requirements are:

- The plugin must work when merged; unfinished or deprecated projects are not accepted.
- Each plugin must be a Git submodule pointing to its upstream repository.
- The upstream repository must document the plugin and its device or KOReader compatibility.

MRI already has a public upstream repository, bilingual documentation, a licence, and CI. Before applying, it still needs physical Kindle testing against the target KOReader release and a stable tagged release.

### Dedicated plugin branch

`contrib` checks the upstream repository out directly as `mri.koplugin`. KOReader therefore needs `_meta.lua` and `main.lua` at that checkout's root. MRI keeps plugin files under `mri.koplugin/` on `main`, so a dedicated `koreader-contrib` branch exposes only that subtree.

After device testing and release preparation, publish the branch with:

```bash
git switch main
git pull --ff-only
git subtree push --prefix=mri.koplugin origin koreader-contrib
```

Then fork `koreader/contrib` and add MRI:

```bash
gh repo fork koreader/contrib --clone
cd contrib
git switch -c add-mri
git submodule add -b koreader-contrib https://github.com/frankshiii/MRI-Mobile_Reading_Intelligence.git mri.koplugin
git add .gitmodules mri.koplugin
git commit -m "Add MRI plugin"
git push -u origin add-mri
gh pr create --repo koreader/contrib
```

The Pull Request should include tested Kindle models and KOReader versions, EPUB scope and known limits, network and API-key behaviour, caching and spoiler boundaries, and links to the upstream repository and stable release.

The submodule remains pinned to the reviewed commit. Later MRI releases require a separate `contrib` Pull Request that updates the submodule pointer.
