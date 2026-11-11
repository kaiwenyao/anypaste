# AnyPaste.exe 逆向报告

## 结论(一句话)

`AnyPaste.exe` **不是原生 C/C++ 程序**,而是改名后的 **AutoHotkey v1.1.33.02 解释器**,内部只带一条 49 字节脚本:

```ahk
; <COMPILER: v1.1.33.02>
^+v::SendRaw %clipboard%
```

行为:按 `Ctrl+Shift+V`,把剪贴板文本**逐字模拟键盘敲入**当前窗口(而不是系统粘贴),用于普通粘贴失效的场景 —— 远程桌面/虚拟机、终端、禁止粘贴的输入框、没有粘贴快捷键的程序。

样本 SHA-256:`ee3ca22558143edad2d99d157ea45848a6fa29c021f1b915d58d73aaa8e0775b`(1,107,456 字节)

## 证据链

### 1. 容器与运行时

| 观察 | 值 |
|---|---|
| 格式 | PE32+ x86-64 GUI(`0x8664`),6 个节 |
| 节表 | `.text .rdata .data .pdata .gfids .rsrc`,`.rsrc` 结束于 `0x10E600` |
| 文件大小 | `0x10E600` —— **与最后一级节结束地址完全相等,没有附加载荷(overlay)** |
| CLI/.NET 数据目录 | 不存在 → 非托管程序(排除 C#/VB.NET 实现) |
| 编译特征 | `Rich` 头、`.pdata`/`.gfids` → MSVC x64 构建 |

`.gfids`(Control Flow Guard 函数表)是 MSVC 编译 AutoHotkey 解释器时的典型产物。

### 2. 导入表证明"通用脚本宿主"身份

14 个 DLL、457 个导入,覆盖了远超单个小工具所需的 Win32 面:

- 剪贴板:`OpenClipboard` / `GetClipboardData` / `SetClipboardData` / `EmptyClipboard` / `CountClipboardFormats`
- 全局输入:`RegisterHotKey` / `SetWindowsHookExW` / `keybd_event` / `SendInput` / `mouse_event` / `GetAsyncKeyState`
- 托盘与窗口:`Shell_NotifyIconW` / `CreateWindowExW` / `RegisterClassExW` / `SetLayeredWindowAttributes`
- 声音:`mixerGetLineInfoW` / `mixerSetControlDetails` / `waveOutGetVolume`(AHK 的 `SoundGet`/`SoundSet`)
- 网络:`InternetOpenW` / `InternetOpenUrlW`(AHK `URLDownloadToFile`)
- 注册表 / 服务控制 / COM / 多显示器 / 字体枚举 …

这是 AutoHotkey 解释器标准库的导入面,而不是任何单一业务程序的导入面。

### 3. 脚本本体

资源目录中:

- 类型 `RT_RCDATA`(`10`),名称 `>AUTOHOTKEY SCRIPT<`
- 语言 `1033`、代码页 `1252`,载荷 **49 字节**,文件偏移 `0x10DD68`

逐字节内容:

```
3b 20 3c 43 4f 4d 50 49 4c 45 52 3a 20 76 31 2e 31 2e 33 33 2e 30 32 3e 0a
5e 2b 76 3a 3a 53 65 6e 64 52 61 77 20 25 63 6c 69 70 62 6f 61 72 64 25
```

即:

```ahk
; <COMPILER: v1.1.33.02>
^+v::SendRaw %clipboard%
```

其中 `; <COMPILER: …>` 是 Ahk2Exe 打包时写入的版本标记,`^+v` 是 `Ctrl+Shift+V`,`SendRaw` 表示**不做转义解释**地发送按键。

### 4. 交叉印证

- 解释器在 `.text:0xE38DA` 处引用 UTF-16 字面量 `AUTOHOTKEY SCRIPT` → 该资源名正是被加载的脚本资源。
- 整个文件中仅出现 **1 次** 小写 `clipboard`(位于脚本资源内),其余为大写 `Clipboard`(AHK 运行时字符串),说明脚本之外没有第二份业务文本。
- 资源 `RT_VERSION` 的产品/文件版本均为 `1.1.33.02`(AutoHotkey 自身版本),没有 AnyPaste 品牌信息。
- 图标资源是 AutoHotkey 原生绿色 "H" 标志(32/48/16 三档)。
- 资源 `RT_MENU`(`&File / &Reload Script / &Edit Script / &Window Spy / &Pause Script / &Suspend Hotkeys / E&xit`,以及 `&View / &Lines most recently executed / &Variables / &Hotkeys / &Key history`)、`RT_DIALOG`(`MS Shell Dlg`,Prompt/OK/Cancel)、`RT_ACCELERATOR` 全部是 AutoHotkey 解释器自带的调试菜单与输入框。
- 脚本未写 `#NoTrayIcon` → 原程序在 Windows 通知区显示 AHK 托盘图标,菜单里可暂停/挂起/退出脚本。

## 行为规格(由脚本语义推导)

| 项 | 语义 |
|---|---|
| 触发 | 全局热键 `Ctrl+Shift+V` |
| 输入源 | 系统剪贴板的**文本**;非文本(图片/文件)时 `Clipboard` 为空 |
| 输出 | `SendRaw`:逐字发送按键,换行=Enter、Tab=Tab;`{}`、`^+!`、`%` 等**不做解释**;非 US 布局可产生的字符以 Unicode 方式注入 |
| 空剪贴板 | 发送空串 → 静默无操作 |
| 中断 | 原脚本没有中断机制 |
| 配置 | 无(热键写死,无配置文件、无界面) |
| 网络/外发 | 脚本无任何网络调用(`WININET` 只属于解释器) |

## 复现方法

```bash
shasum -a 256 AnyPaste.exe
# 提取 49 字节脚本
python3 - <<'PY'
data = open('AnyPaste.exe','rb').read()
print(data[0x10DD68:0x10DD68+49].decode())
PY
```

## 结论边界

- 上述结论覆盖 **业务逻辑**;解释器自身的实现细节(约 1 MB 的 AHK 运行时)不构成本次重写的对象。
- 证据只说明静态结构与脚本内容,**不声称**观察过 Windows 上的运行时行为;行为语义由 AutoHotkey v1.1.33.02 的既定语义推导得出。
- 本仓库不重新分发 `AnyPaste.exe`(其中含第三方 AutoHotkey 二进制)。
