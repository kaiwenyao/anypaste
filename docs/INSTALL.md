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
3. 解包并校验应用包(`plutil`、bundle id、`codesign --verify`)
4. 创建或复用**登录钥匙串中的持久本地签名身份**,并把证书加入用户级 code signing 信任;然后用它重新签名应用
5. 校验新应用的 designated requirement 与已保存值一致
6. 退出旧实例 → 替换 `/Applications/AnyPaste.app`(失败自动回滚)→ 注册 LaunchServices → 启动

常用参数:

| 参数 | 作用 |
|---|---|
| `--no-launch` | 安装后不启动 |
| `--prefix DIR` | 安装到指定目录(默认 `/Applications`,不可写时退回 `~/Applications`) |
| `--sign local\|adhoc` | `local`(默认)使用持久身份;`adhoc` 仅用于排查,不保留授权 |
| `--reset-identity` | 删除旧签名身份并创建新身份(需要重新授权一次) |
| `--app PATH` | 用本地 `.app` 或 `.zip` 安装(离线 / 自建) |
| `--uninstall` | 卸载 |
| `--lang en\|zh-CN` | 提示语言(默认跟随系统) |

## 为什么不需要 Apple 开发者账号

macOS 允许运行**未经公证**的应用;只有"下载后首次运行"的 Gatekeeper 检查需要付费账号,而安装器会移除隔离属性(`com.apple.quarantine`)。

AnyPaste 使用**本机自签的本地证书**做代码签名,不依赖 Developer ID,也不需要 Apple 账号。证书由安装器在登录钥匙串中生成,私钥只授权 `/usr/bin/codesign` 使用,信任范围限定在用户域的 **code signing** 策略,不会变成系统级根证书。

## 升级后为什么不需要重新授权

macOS 的辅助功能授权(TCC)记录的是应用的 **designated requirement**,不是二进制本身:

- **ad-hoc 签名**的 requirement 是 `cdhash H"…"`,代码一变就失效 → 每次升级都要重新勾选。
- **证书签名**的 requirement 是 `identifier "com.anypaste.mac" and certificate leaf/root = H"<证书指纹>"`。只要新版本仍用同一张证书签名,它仍满足旧 requirement → 授权保留。

安装器的做法(与 [snow-shot](https://github.com/mg-chao/snow-shot) 相同):

1. 首次安装时生成 10 年期自签证书,导入**登录钥匙串**;
2. 用 `security add-trusted-cert -r trustRoot -p codeSign -k <login keychain>` 把它加入用户级 code signing 信任。没有这一步,自签证书甚至不能被 `codesign` 使用,更不会被 TCC 接受;
3. 每次更新都用同一张证书重新签名下载的 app(`--identifier com.anypaste.mac`,不使用 `--deep`);
4. 把证书指纹和 designated requirement 保存在 `~/Library/Application Support/AnyPaste/`;
5. 替换前用 `codesign --verify --strict -R "=<已保存 requirement>"` 校验新 app;身份丢失或 requirement 不匹配时**中止安装**,绝不静默生成新身份。

### 一次性成本

首次安装(以及从 1.0.x 的 ad-hoc 签名迁移到 1.1.0)需要:

1. **信任本地证书**:macOS 可能请求一次钥匙串访问或信任确认。允许即可;以后升级不再提示。
2. **授予辅助功能**:系统设置 → 隐私与安全性 → 辅助功能 → 勾选 AnyPaste。

从 1.0.x 升级时,旧授权是 cdhash 记录,无法复用,因此这是**最后一次**重新授权;从 1.1.0 起的后续升级会复用同一身份。

> 如果拒绝钥匙串/信任提示,安装器会中止,现有 app 不受影响。重跑并允许即可。

## 更新

重复执行同一条安装命令即可。也可以在应用内打开 设置 → 权限与诊断 → 检查更新:发现新版本时会显示 GitHub Release 入口,复制安装命令重跑即可。

安装器会:

- 复用已有的签名身份,不创建新证书;
- 用已保存的 requirement 校验新 app;
- 替换成功后打印“授权应保留”的提示;
- 替换失败时恢复旧 app,并保留原签名状态。

注意:

- **请用安装器更新**,不要把 Release 里 `AnyPaste-macos.zip` 的 app 直接拖进 `/Applications`。拖拽会保留发布包的 ad-hoc 签名,失去持久身份。
- **请用最初安装 AnyPaste 的 macOS 用户更新**。签名身份在用户钥匙串里;共享 Mac 上换用户更新会换成另一张证书,导致需要重新授权。
- 安装器会优先沿用已有安装路径(`/Applications` 或 `~/Applications`),避免路径变化影响授权。
- 如果安装了另一张证书签名的 AnyPaste(例如别的用户装的),安装器会打印警告;继续更新会改变签名并需要重新授权。

## 签名状态与验证

签名状态保存在 `~/Library/Application Support/AnyPaste/`:

| 文件 | 含义 |
|---|---|
| `signing-identity` | 证书 SHA-1 指纹 |
| `signing-certificate.pem` | 公钥证书,用于重新信任和诊断 |
| `signing-requirement` | 已保存的 designated requirement |
| `signing-creating` | 身份创建中断标记(正常情况下不存在) |

验证命令:

```bash
# 应用应显示 certificate leaf/root,而不是 cdhash
codesign -d -r- /Applications/AnyPaste.app

# 证书应在登录钥匙串中且可用于 code signing
login=$(security default-keychain -d user | sed 's/^[[:space:]]*"//; s/"$//')
security find-identity -v -p codesigning "$login"

# 证书应通过 code signing 信任校验
security verify-cert -L \
  -c "$HOME/Library/Application Support/AnyPaste/signing-certificate.pem" \
  -p codeSign

# 安装后的 requirement 应与保存值一致
cat "$HOME/Library/Application Support/AnyPaste/signing-requirement"
```

也可以运行 `Scripts/verify.sh` 做完整验收(默认把 ad-hoc 视为失败;如需接受 ad-hoc,设置 `ALLOW_ADHOC=1`)。

## 卸载

```bash
bash install-anypaste-macos.sh --uninstall
```

或从源码目录执行 `Scripts/uninstall.sh`。两者都会移除:

- `/Applications/AnyPaste.app`(以及 `~/Applications/AnyPaste.app`)
- `~/Library/Application Support/AnyPaste/`(含签名状态)
- 登录钥匙串中的 `AnyPaste Local Signing` 证书及信任设置
- 旧版 `~/Library/Keychains/anypaste-signing.keychain-db`(若存在)
- `~/Library/Logs/AnyPaste/`
- 偏好域 `com.anypaste.mac`

卸载会删除签名身份,重装需要重新授权一次。想保留授权时请直接覆盖升级,不要卸载。

## 安全说明

- 安装脚本随 Release 以明文分发([dist/install-anypaste-macos.sh](../dist/install-anypaste-macos.sh)),可逐行审阅
- 下载内容在解包前先做 SHA-256 校验
- 私钥保存在登录钥匙串;只有 `/usr/bin/codesign` 被授权使用;信任仅限用户域 code signing
- 应用不采集数据;只有在你点击「检查更新」时访问 GitHub 公开 API 查询版本号,平时不联网;仅在按下热键时读取剪贴板文本
- 日志只写本机 `~/Library/Logs/AnyPaste/anypaste.log`,不含剪贴板内容
- 未做 Apple 公证;自签证书不是 Developer ID 签名

## 排错

| 现象 | 处理 |
|---|---|
| 按 `⌃⇧V` 没反应 | 检查「辅助功能」是否勾选;设置 → 权限与诊断 里可看到实时状态 |
| 已在系统设置勾选,应用仍显示未授权 | 先退出并重新打开 AnyPaste;若仍无效,重启(或重新登录)一次。刚更新过版本时,在辅助功能列表里用减号移除 AnyPaste,再重新添加并勾选 |
| 安装时提示钥匙串访问 / 信任确认 | 首次创建签名身份所需;允许一次即可,以后升级复用身份、不再提示 |
| 安装提示“证书未受信任”或 `trust_failed` | 解锁登录钥匙串后重跑,并允许系统信任提示。不要用 `--sign adhoc` 绕过,除非接受每次升级后重新授权 |
| 安装提示身份缺失 / `identity_missing` | 优先恢复原证书和私钥(保留授权);无法恢复时用 `--reset-identity` 重建(需重新授权一次) |
| 安装提示 requirement 不匹配 / `continuity_failed` | 说明新应用不满足旧签名要求;恢复原签名身份,或明确用 `--reset-identity` 重置 |
| 安装提示多个 AnyPaste 身份 | 在“钥匙串访问”中删除多余证书;或 `--reset-identity` 重建 |
| 签名身份损坏 / 中断 | 运行 `bash install-anypaste-macos.sh --reset-identity`;会重建身份并需要重新授权一次 |
| 更新后仍不能输入文字 | 确认用安装器更新且 `codesign -d -r-` 显示证书 requirement;运行 `AnyPaste --self-test` 看 `axTrusted`;必要时移除后重新添加辅助功能 |
| 输入丢字 | 默认 5 ms;仍丢字时把每字延迟调到 10 ms 左右(远程桌面、Electron 应用常见) |
| 菜单栏看不到图标 | 系统限制;Dock 图标默认可见,可在 Dock 打开设置。若已关闭 Dock 图标,应用会自动启用备用入口(系统恢复后自动切回),详见 README「已知限制」 |
| 想看诊断 | `Settings → 权限与诊断 → 运行自检`,或终端执行 `AnyPaste --self-test` |
