# 暂存版本：窗口关闭 / 退出快捷键

> 状态：已提交到 `feat/window-shortcuts` 分支，等待接手验证和合并；**尚未发版、尚未合并到 `main`**。
>
> 本文说明这个暂存版本包含什么、验证到什么程度，以及接手后还需要做什么。

## 功能变化

当任意 AnyPaste 窗口（设置、首次引导、关于面板等）处于聚焦状态时：

| 快捷键 | 行为 |
|---|---|
| `⌘W` | 关闭当前窗口；AnyPaste 继续运行，仍驻留菜单栏 |
| `⌘Q` | 正常退出 AnyPaste；退出前注销全局热键 |

补充行为：

- 没有窗口处于 key 状态时，`⌘W` 菜单项自动禁用，不会关闭状态栏菜单，也不会退出应用。
- 快捷键是应用内菜单快捷键，不是全局热键；切到其它应用后不会拦截它们的 `⌘W` / `⌘Q`。
- 关闭最后一个窗口不会退出应用（`applicationShouldTerminateAfterLastWindowClosed` 保持 `false`）。
- 设置 / 引导窗口关闭后仍可再次打开（窗口控制器保留窗口，`isReleasedWhenClosed = false`）。

## 实现位置

| 文件 | 变化 |
|---|---|
| `AnyPaste/App/AppMenu.swift` | 新增原生 `NSApp.mainMenu`：`AnyPaste` 应用菜单（关于 / 退出）与 `文件` 菜单（关闭窗口）。`⌘W` 使用 nil target + `performClose:`，由 responder chain 关闭当前 key window；`⌘Q` 使用 `terminate:`。 |
| `AnyPaste/App/AppDelegate.swift` | 启动时安装主菜单；`--self-test` 支持 `--skip-accessibility-check`。 |
| `AnyPaste/Core/Diagnostics.swift` | 自检新增 `menu.closeWindow`、`menu.quit`、`window.closeKeepsAppRunning` 三项菜单契约检查。 |
| `Scripts/gen_project.py` | 将 `AppMenu.swift` 纳入生成工程。 |
| `AnyPaste.xcodeproj/project.pbxproj` | 由 `gen_project.py` 重新生成。 |
| `Scripts/ci.sh` | 新增无头 CI 检查：工程文件同步、通用构建、bundle 契约、菜单/快捷键自检。 |
| `.github/workflows/ci.yml` | 新增 GitHub Actions：PR、`main` push、手动触发，运行 `Scripts/ci.sh`。 |
| `README.md` / `README.en.md` | 使用说明增加 `⌘W` / `⌘Q`，并补充无头 CI 说明。 |
| `docs/PORT_SPEC.md` | 增加窗口快捷键映射和验收项。 |

没有修改偏好键、剪贴板流程或输入引擎。

## 验证记录

### 已通过

在 macOS 27.2.1、Xcode 27.2、Apple Silicon 本机执行：

```bash
bash Scripts/ci.sh
```

结果：

- 生成的 Xcode 工程与 `gen_project.py` 输出一致；
- 通用二进制构建成功（`x86_64 arm64`）；
- `Info.plist`、bundle id、`LSUIElement`、ad-hoc 签名检查通过；
- `--self-test --skip-accessibility-check` 返回 `"ok" : true`，包含：
  - `menu.closeWindow`：`⌘W → performClose:(nil target)`
  - `menu.quit`：`⌘Q → terminate:(target=NSApp)`
  - `window.closeKeepsAppRunning`：关闭最后窗口后进程继续运行

GUI 冒烟（System Events 注入真实 `⌘W` / `⌘Q`）：

1. 打开设置窗口并让 AnyPaste 成为前台应用；
2. 按 `⌘W`：窗口关闭，进程仍在运行；
3. 从 Dock / `open` 重新打开设置；
4. 按 `⌘Q`：进程退出。

两项快捷键均按预期工作。

### 尚未完成

- GitHub Actions 尚未在 PR 上实际跑过（本分支尚未开 PR）。工作流文件已加入，接手后开 PR 即可触发。
- 没有做多显示器、全屏空间、VoiceOver 等额外 UI 场景测试。
- 没有更新截图；现有截图仍是旧版本。
- 没有 bump 版本号、打 tag 或发 Release。

## 接手清单

```bash
# 1. 获取分支
git fetch origin
git switch feat/window-shortcuts

# 2. 重新构建并跑完整无头检查
bash Scripts/ci.sh

# 3. 本机 GUI 冒烟
open build/DerivedData/Build/Products/Release/AnyPaste.app --args --open-settings
# 聚焦 AnyPaste 后按 ⌘W，确认窗口关闭且进程仍在；
# 重新打开设置，按 ⌘Q，确认进程退出。

# 4. 开 PR，等 CI 全绿
gh pr create --base main --head feat/window-shortcuts \
  --title "Add ⌘W close-window and ⌘Q quit shortcuts" \
  --body "Adds a native app menu so ⌘W closes the focused window without quitting and ⌘Q terminates. Includes menu diagnostics and headless CI."
gh pr checks --watch
```

合入前建议确认：

- [ ] PR CI 全绿；
- [ ] GitHub Actions 的 `macos-15` runner 能正常构建通用二进制；
- [ ] 至少一台 Intel Mac / macOS 13 上手动验证 `⌘W`、`⌘Q`；
- [ ] 如本次改动要随版本发布，再 bump `Info.plist` 与 `gen_project.py` 中的版本号，并更新截图 / Release notes；
- [ ] 合并后删除本暂存说明，或将其内容并入正式文档。

## 交接备注

- 当前工作树在提交前是干净的（除本分支改动外没有未跟踪文件）。
- `Scripts/ci.sh` 的工程同步检查比较的是“运行生成器前后”的文件哈希，因此本地未提交时也能用，不依赖 `git diff HEAD`。
- 若要在无头环境运行自检，必须带 `--skip-accessibility-check`；普通 `--self-test` 仍要求辅助功能权限。
