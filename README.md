# cc-connect-wechat

> 通过 [cc-connect](https://github.com/chenhg5/cc-connect) 将 Claude Code 连接到个人微信，随时随地用微信跟 AI 编程助手对话。

## 这是什么？

这是一个 [WorkBuddy](https://www.codebuddy.cn) Skill，提供完整的 cc-connect 安装和配置指南，让你的个人微信变成 AI 编程助手的入口。

## 功能

- **微信对话 AI** — 用个人微信直接跟 Claude Code 对话，支持代码编写、文件操作、命令执行
- **后台服务化** — 注册为 Windows 服务，开机自启、RDP 断连不停、崩溃自动重启
- **完整安装指南** — 从下载到配置到服务化，手把手全覆盖
- **故障排查手册** — RDP 渲染、PATH 缺失、锁冲突等常见问题解决方案

## 前置条件

- Windows 10/11 或 Windows Server
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 已安装（`npm install -g @anthropic-ai/claude-code`）
- Node.js 18+
- 个人微信（手机端，用于扫码授权）

## 快速开始

### 方式一：WorkBuddy Skill 安装（推荐）

如果你使用 WorkBuddy，可以直接安装这个 Skill：

1. 下载本仓库的 ZIP 或克隆
2. 在 WorkBuddy 中：技能 -> 从文件夹安装 -> 选择解压后的目录
3. 在对话中说"帮我安装 cc-connect 连接微信"

### 方式二：手动安装

按照 `SKILL.md` 中的步骤操作，或参考下面的核心流程：

```powershell
# 1. 下载 cc-connect（运行 scripts/download_cc_connect.py）
python scripts/download_cc_connect.py

# 2. 解压到 C:\Program Files\cc-connect

# 3. 初始化配置
cc-connect  # 首次运行创建默认配置

# 4. 微信扫码授权
cc-connect weixin setup

# 5. 修改 config.toml（设置 work_dir 和 allow_from）

# 6. 服务化（推荐，RDP 环境必备）
# 以管理员运行 scripts/setup_ccconnect_service.ps1
```

## 文件结构

```
cc-connect-wechat/
├── SKILL.md                          # 完整安装指南（8个步骤）
├── scripts/
│   ├── download_cc_connect.py        # 下载脚本（自动获取最新版本）
│   └── setup_ccconnect_service.ps1   # NSSM 服务化脚本
├── references/
│   ├── troubleshooting.md            # 常见问题排查手册
│   └── config_template.toml          # 配置文件模板
├── README.md
└── LICENSE
```

## 常见问题

### RDP 远程桌面下 CC Switch 界面打不开

设置环境变量 `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--disable-gpu`：

```powershell
[Environment]::SetEnvironmentVariable("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS", "--disable-gpu", "User")
```

### cc-connect 服务启动后立即暂停（Paused）

原因是 LocalSystem 账户找不到 `claude` 命令，需要注入 PATH 环境变量。详见 `references/troubleshooting.md`。

### 进程反复重启

检查 `~/.cc-connect/service-stderr.log`，通常是配置文件路径或 `claude` 路径问题。

更多问题见 [排查手册](references/troubleshooting.md)。

## 致谢

- [cc-connect](https://github.com/chenhg5/cc-connect) — AI 编程工具消息平台连接器
- [CC Switch](https://github.com/farion1231/cc-switch) — AI 编程工具统一管理平台
- [NSSM](https://github.com/fightroad/nssm) — Non-Sucking Service Manager

## License

MIT
