# 安装 / 更新 / 卸载

## 一键安装(推荐)

```bash
curl -fL --proto '=https' --proto-redir '=https' \
  -o install-anypaste-macos.sh \
  https://github.com/kaiwenyao/anypaste/releases/latest/download/install-anypaste-macos.sh \
  && bash install-anypaste-macos.sh
```

安装器执行流程:

1. 从 GitHub Release 下载 `AnyPaste-macos.zip` 与 `.sha256`
2. 校验 SHA-256(**不一致直接中止,不改动现有安装**)
3. 解包并校验应用包(`plutil`、`codesign --verify`)
4. 在 `~/Library/Keychains/anypaste-signing.keychain-db` 中准备一个**持久自签名身份**,并用它签名应用
5. 退出旧实例 → 原子替换 `/Applications/AnyPaste.app`(失败自动回滚)→ 注册 LaunchServices → 启动

常用参数:

| 参数 | 作用 |
|---|---|
| `--no-launch` | 安装后不启动 |
| `--prefix DIR` | 安装到指定目录(默认 `/Applications`,不可写时退回 `~/Applications`) |
| `--sign auto\|local\|adhoc` | 签名策略;`adhoc` 用于排查签名问题 |
| `--app PATH` | 用本地 `.app` 或 `.zip` 安装(离线 / 自建) |
| `--uninstall` | 卸载 |
| `--lang en\|zh-CN` | 提示语言(默认跟随系统) |

## 为什么不需要 Apple 开发者账号

macOS 允许运行**本机自签名**的应用;只有"下载后首次运行"的公证(Gatekeeper)检查需要付费账号,而安装器会移除隔离属性(`com.apple.quarantine`)。

安装器生成的证书是 10 年期自签证书,私钥保存在独立钥匙串中,密码保存在 `~/Library/Application Support/AnyPaste/`(权限 0600)。这样签名的应用具有**基于证书的 designated requirement**:

```
identifier "com.anypaste.mac" and certificate root = H"…"
```

而不是随每次构建变化的 `cdhash`。因此 macOS 的辅助功能授权在**升级后依然有效**,不需要每次重新勾选。

首次安装后 macOS 仍会要求一次辅助功能授权(这是系统对"模拟按键"的硬性要求,无法绕过):

> 系统设置 → 隐私与安全性 → 辅助功能 → 勾选 AnyPaste

## 更新

重复执行同一条安装命令即可。安装器复用同一签名身份,并在替换前校验旧 requirement 是否一致。

## 卸载

```bash
bash install-anypaste-macos.sh --uninstall
```

或从源码目录执行 `Scripts/uninstall.sh`。两者都会移除:

- `/Applications/AnyPaste.app`
- `~/Library/Application Support/AnyPaste/`(含签名身份状态)
- `~/Library/Logs/AnyPaste/`
- 偏好域 `com.anypaste.mac`
- `~/Library/Keychains/anypaste-signing.keychain-db`

## 安全说明

- 安装脚本随 Release 以明文分发([dist/install-anypaste-macos.sh](../dist/install-anypaste-macos.sh)),可逐行审阅
- 下载内容在解包前先做 SHA-256 校验
- 应用本身不联网、不采集数据;仅在按下热键时读取剪贴板文本
- 日志只写本机 `~/Library/Logs/AnyPaste/anypaste.log`,不含剪贴板内容

## 排错

| 现象 | 处理 |
|---|---|
| 按 `⌃⇧V` 没反应 | 检查「辅助功能」是否勾选;设置 → 权限与诊断 里可看到实时状态 |
| 输入丢字 | 把每字延迟调到 5–10 ms(远程桌面、Electron 应用常见) |
| 菜单栏看不到图标 | 系统限制;应用会自动在 Dock 显示入口,详见 README「已知限制」 |
| 签名身份损坏 | `bash install-anypaste-macos.sh --uninstall` 后重装,会重新生成身份(需重新授权) |
| 想看诊断 | `Settings → 权限与诊断 → 运行自检`,或终端执行 `AnyPaste --self-test` |
