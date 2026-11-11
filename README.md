# AnyPaste for macOS

把剪贴板里的文字**逐字“敲”**进当前应用 —— 不是系统粘贴。

远程桌面 / 虚拟机、终端、禁止粘贴的输入框、没有粘贴快捷键的程序里,`⌘V` 通常无效;AnyPaste 用真实键盘事件把内容一个字一个字输进去。

> 这是对 Windows 程序 `AnyPaste.exe` 的逆向重写。原程序其实是 **AutoHotkey v1.1.33.02 解释器 + 一条 49 字节脚本**(`^+v::SendRaw %clipboard%`),完整取证见 [docs/REVERSE_ENGINEERING.md](docs/REVERSE_ENGINEERING.md)。本仓库用 SwiftUI / AppKit 原生重写,不依赖 AutoHotkey。

## 安装(一行命令,不需要 Apple 开发者账号)

```bash
curl -fL --proto '=https' --proto-redir '=https' \
  -o install-anypaste-macos.sh \
  https://github.com/kaiwenyao/anypaste/releases/latest/download/install-anypaste-macos.sh \
  && bash install-anypaste-macos.sh
```

安装器会:下载最新版 → 校验 SHA-256 → 在你的 Mac 上生成一个**持久本地签名身份**并签名 → 装到 `/Applications` → 启动。

- 支持 macOS 13+ / Apple Silicon / Intel(通用二进制)
- 不需要开发者账号、不做公证:默认 ad-hoc 签名,首次运行在「系统设置 → 隐私与安全性 → 辅助功能」勾选一次即可
- 想避免升级后重复授权:`bash install-anypaste-macos.sh --sign local`(会要求输入一次登录密码,把自签证书加入用户信任)
- 更新:重新执行同一条命令(默认 ad-hoc 签名,授权可能需要重新勾选;`--sign local` 可避免)

## 使用

1. `⌘C` 复制任意文字
2. 切到目标窗口,按 **`⌃⇧V`**
3. 文字被逐字输入(输入过程中按 `Esc` 可中止)

快捷键、每字延迟(0–20 ms)、开机启动都在设置里调整。点击 Dock 图标(或菜单栏图标)可以打开设置。

## 功能

- 全局热键 `⌃⇧V`,可在设置里录制修改,注册冲突会立即提示
- 忠实还原原脚本的 **Raw 语义**:`{}`、`^+!`、`%` 等不会被解释;换行 = Return,Tab = Tab
- 中英日韩与 emoji 走 Unicode 注入;当前键盘布局能产生的字符使用真实键码,兼容只认虚拟键码的应用
- 每字延迟可调,解决远程桌面 / Electron 应用丢字
- 输入进度、停止输入、菜单栏状态、Accessibility 权限引导
- 不联网、不上传任何数据;只在按下热键时读取剪贴板文本

## 截图

| 首次引导 | 设置 |
|---|---|
| ![引导](docs/images/onboarding.png) | ![设置](docs/images/settings.png) |

## 从源码构建

```bash
brew install --cask xcode        # 或用 App Store 安装 Xcode
bash Scripts/build.sh            # 生成 build/DerivedData/Build/Products/Release/AnyPaste.app
bash Scripts/install_local.sh    # 可选:装到 /Applications
```

`AnyPaste.xcodeproj` 由 `Scripts/gen_project.py` 生成(新增 Swift 文件后重新运行即可),用 Xcode 直接打开也能构建。

## 验收

```bash
Scripts/verify.sh
```

会检查:App 包与签名、Info.plist 契约、通用二进制、`--self-test`(热键注册 / 键位映射 / 偏好读写 / 剪贴板读取)、`--e2e-test`(真实 `CGEvent` 路径把含中文换行 Tab emoji 的样本敲进 `NSTextView` 并回读比对)、进程存活、崩溃报告。

## 卸载

```bash
curl -fL --proto '=https' --proto-redir '=https' \
  -o install-anypaste-macos.sh \
  https://github.com/kaiwenyao/anypaste/releases/latest/download/install-anypaste-macos.sh \
  && bash install-anypaste-macos.sh --uninstall
```

会移除应用、偏好、日志和本地签名身份。

## 已知限制

- **macOS 26/27 的菜单栏项呈现问题**:在部分系统构建上,系统不会呈现新建的状态栏项(实测连第三方菜单栏应用同样不显示)。AnyPaste 会自动检测并在 Dock 显示图标作为入口,热键功能不受影响;系统恢复正常后会自动回到"仅菜单栏"模式。
- 需要辅助功能权限(系统要求,无法绕过):这是 macOS 对"向其它应用模拟按键"的硬性限制。
- 密码框等安全输入状态下系统会忽略模拟按键,应用会明确提示而不是静默失败。

## 目录结构

```
AnyPaste/App/        程序入口与 AppDelegate(含 --self-test / --e2e-test)
AnyPaste/Core/       热键、键位映射、输入引擎、权限、偏好、诊断
AnyPaste/UI/         状态栏菜单、设置、引导、HUD
dist/                安装器(随 Release 分发)
docs/                逆向报告、行为规格、安装说明
analysis/            提取出的原脚本与样本哈希
Scripts/             构建 / 打包发布 / 验收 / 卸载 / 工程生成
```

## License

MIT。原 `AnyPaste.exe` 中的 AutoHotkey 解释器属于 AutoHotkey 项目(GPLv2),本仓库不再分发该二进制。
