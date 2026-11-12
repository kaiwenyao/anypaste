# 行为规格(Windows → macOS 映射)

## 原始语义

原程序 = AutoHotkey v1.1.33.02 解释器 + 脚本:

```ahk
; <COMPILER: v1.1.33.02>
^+v::SendRaw %clipboard%
```

## 映射表

| Windows 原行为 | macOS 实现 | 说明 |
|---|---|---|
| `^+v` 全局热键 | Carbon `RegisterEventHotKey`,默认 `⌃⇧V` | Carbon 热键**不需要**辅助功能权限,只有注入按键需要 |
| `%clipboard%` | `NSPasteboard.general.string(forType: .string)` | 只读文本;图片/文件视为空 |
| `SendRaw` 逐字敲入 | `CGEvent` + `keyboardSetUnicodeString`,`.cghidEventTap` | 每字 down/up 一对事件 |
| 换行 = Enter | keyCode 36(Return) | 事件同时携带 `\r` |
| Tab = Tab | keyCode 48 | |
| 空格 | keyCode 49 | |
| 退格字符 | keyCode 51 | |
| Raw(不解释 `{}`/`^+!`/`%`) | 按 `Character`(字形簇)切分,永不解释转义 | 自检项 `mapping.raw` 覆盖 |
| 布局可产生的字符用真实键码 | `UCKeyTranslate` 反查当前输入源 → `(keyCode, shift)` | 兼容只读 `virtualKey` 的应用 |
| 布局不可产生的字符(中文/emoji) | 纯 Unicode 事件(keyCode 0) | 自检项 `mapping.unicode` 覆盖 |
| 一次性高速发送 | 默认每字 5 ms,可调 0–20 ms | 远端/Electron 丢字时调大 |
| AHK 托盘图标 | `NSStatusItem`;系统不呈现时自动降级为 Dock 图标 | 见 README「已知限制」 |
| 托盘菜单 Suspend | 菜单项「启用热键」开关 | 切换会立即注册/注销热键 |
| 无中断机制 | `Esc`(轮询键态)或菜单「停止输入」 | 输入前会等待残留的 Esc 抬起 |
| 无配置界面 | 设置窗口:通用 / 快捷键 / 权限与诊断 | 偏好写入 `UserDefaults`(`anypaste.*`) |
| 无权限模型 | 辅助功能权限引导 + 实时状态 + 一键跳转系统设置 | 安全输入(密码框)时明确提示 |
| 原程序无窗口菜单 | 原生 `NSApp.mainMenu`:`⌘W` 关闭当前窗口(不退出),`⌘Q` 退出 | 关闭最后一个窗口后进程继续驻留菜单栏 |
| 无自检 | `--self-test` / `--e2e-test` | 供 CI 与安装验收使用 |

## 偏好键

| 键 | 默认 | 含义 |
|---|---|---|
| `anypaste.enabled` | `true` | 热键是否启用 |
| `anypaste.hotKeyCode` / `anypaste.hotKeyModifiers` | `9` / `control+shift` | Carbon 键码与修饰位 |
| `anypaste.delayMs` | `5` | 每字延迟(毫秒,0–20) |
| `anypaste.showProgress` | `true` | 在菜单栏显示 `12/48` 进度 |
| `anypaste.completedOnboarding` | `false` | 是否已看过引导 |

## 验收矩阵

| 编号 | 检查 | 方式 |
|---|---|---|
| A | 工程可构建 | `Scripts/build.sh` |
| B | 通用二进制 | `lipo -info` |
| C | 签名有效,requirement 基于证书且与保存值一致 | `codesign -d -r-`;`Scripts/verify.sh` |
| D | Info.plist 契约 | `plutil -extract` |
| E | 热键注册/注销 | `--self-test` 的 `hotkey.*` |
| F | 键位映射(换行/Tab/ASCII/Raw/Unicode) | `--self-test` 的 `mapping.*` |
| G | 端到端输入(含中文/emoji/换行/Tab) | `--e2e-test` |
| H | 跨进程热键 → 目标应用收到文本 | 手测:目标应用 + 物理 `⌃⇧V` |
| I | 进程存活、无崩溃 | `ps` / `DiagnosticReports` |
| J | 菜单栏或 Dock 入口可见 | 截图 |
| K | 窗口快捷键:⌘W 关闭当前窗口且不退出,⌘Q 退出 | `--self-test` 的 `menu.*` / `window.closeKeepsAppRunning`;手测 |
| L | 升级后辅助功能授权保留 | 手测:安装 build A → 授予辅助功能 → 安装 build B → `--e2e-test` 不重新授权 |

## 边界情况

- 剪贴板为空或非文本:不输入,显示 HUD 提示(原程序静默;此处为必要 UX 补充)
- 超长文本:后台串行输入,进度可见,可中止,不设硬上限
- 输入中再次触发:忽略(不排队)
- 目标处于安全输入(密码框):拒绝并提示
- 辅助功能被撤销:每次输入前校验并引导
- 热键被其它应用占用:保留失败信息,提示更换,不静默失效
