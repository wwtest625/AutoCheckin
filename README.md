# AutoCheckin for macOS ⚡️

[![Platform](https://img.shields.io/badge/Platform-macOS%2014.0%2B-blue?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org/)
[![Build & Package](https://github.com/wwtest625/AutoCheckin/actions/workflows/build.yml/badge.svg)](https://github.com/wwtest625/AutoCheckin/actions/workflows/build.yml)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Zero-Dependencies](https://img.shields.io/badge/Dependencies-Zero-brightgreen.svg)]()

一款基于 **Swift 6 + SwiftUI** 构建的高颜值 macOS 原生菜单栏自动签到与积分管理工具。专为 **Trae CN** 与 **WorkBuddy** 打造，提供无需繁琐登录、零第三方依赖、安全透明的每日自动签到体验。

---

## ✨ 特性亮点

- **🖥 原生常驻菜单栏（Menu Bar Accessory）**
  - 不占用 Dock 栏空间，优雅融入 macOS 状态栏。
  - 左键一键快速呼出 / 隐藏控制台，右键弹出快捷操作菜单。
  - 原生自适应系统浅色 / 深色模式（SF Symbols 矢量适配）。

- **🔒 本地只读 & 极致安全**
  - **零外部第三方依赖**：Trae (AES-128-CBC + HMAC-SHA512) 与 WorkBuddy (AES-256-GCM 信封解密) 全部基于 Apple 原生 `CryptoKit` 和 `CommonCrypto` 实现。
  - **只读扫描**：直接读取本地客户端现有登录凭证，绝不修改、覆盖或写入客户端私有数据。
  - **本地内存处理**：所有解密与网络交互均直接在本地与官方 API 发起，绝无中间服务器或云端中转。

- **⚡️ 现代化 Swift 6 并发架构**
  - 全面适配 Swift 6 并发模型（`@MainActor`、`async/await`、`Task.detached`）。
  - 后台异步文件 I/O 与状态同步，界面流畅零卡顿。

- **🎯 全自动打卡 & 状态看板**
  - **自动发现**：自动感知本地登录的全部 Trae 与 WorkBuddy 账号。
  - **多账号管理**：支持多账号独立积分查询、今日签到状态展示及右键移除。
  - **定时签到**：内置后台静默定时调度器，设定时间自动打卡。
  - **实时日志**：内置交互式日志控制台，接口调用流程清晰可追溯。

---

## 🛠 架构一览

```text
AutoCheckin
├── Sources/AutoCheckin/
│   ├── App.swift                   # 应用入口、菜单栏 NSStatusItem 管理与生命周期
│   ├── Core/
│   │   ├── CryptoUtils.swift       # Apple CryptoKit / CommonCrypto 原生解密实现
│   │   ├── TraeService.swift       # Trae 登录态扫描、凭证提取、积分与签到接口
│   │   ├── WorkBuddyService.swift  # WorkBuddy 本地凭证扫描、Token 提取与打卡接口
│   │   ├── CheckinManager.swift    # 状态中心、定时调度、并发执行管理
│   │   └── AccountStorage.swift    # 本地轻量化账号信息持久化
│   ├── Models/
│   │   ├── AccountModel.swift      # 账号与平台数据结构定义
│   │   └── LogEntry.swift          # 实时控制台日志模型
│   └── Views/
│       ├── ContentView.swift       # 核心主容器（账号概览、日志面板、设置界面）
│       ├── AccountCardView.swift   # 账号状态卡片（积分、签到按钮、右键菜单）
│       ├── LogConsoleView.swift    # 实时流式控制台日志视图
│       └── SettingsView.swift      # 定时任务、触发时间与安全设置
├── Resources/
│   └── AppIcon.icns                # 原生 App 图标资源
├── Scripts/
│   ├── bundle.sh                   # 一键 Release 编译并打包为标准 .app 应用程序
│   └── run.sh                      # 命令行调试模式直接运行
└── Package.swift                   # Swift Package Manager 工程定义
```

---

## 📦 构建与安装

### 系统要求

- **macOS**: 14.0 (Sonoma) 或更高版本
- **Xcode Command Line Tools**: 支持 Swift 6.0+

### 一键打包运行

1. 克隆代码仓库：
   ```bash
   git clone https://github.com/wwtest625/AutoCheckin.git
   cd AutoCheckin
   ```

2. 运行打包脚本：
   ```bash
   bash Scripts/bundle.sh
   ```
   脚本将使用 Swift 6 Release 模式编译二进制文件，生成标准的 `AutoCheckin.app`，并配置好菜单栏图标与代码签名。

3. 启动应用：
   ```bash
   open AutoCheckin.app
   ```
   或者直接将 `AutoCheckin.app` 拖入系统的 `/Applications`（应用程序）文件夹。

---

## 💡 使用指南

1. **首次启动**：
   - 应用会自动常驻在 macOS 屏幕右上角菜单栏中。
   - 启动时会自动检测本地已登录的 Trae 与 WorkBuddy 账号，并拉取最新积分。

2. **操作说明**：
   - **单击状态栏图标**：快速唤出或收起主窗口。
   - **右键状态栏图标**：呼出菜单（打开主界面 / 退出应用）。
   - **右键账号卡片**：支持删除本地存储的不再需要的旧账号。
   - **定时设置**：在主界面切换至「定时设置」标签，开启定时自动签到并设置期望时间。

---

## ⚠️ 免责声明 (Disclaimer)

- 本工具仅供个人学习、技术研究与自动化体验之用。
- 本项目不包含任何商业代码或破解行为，所有网络请求均为客户端原有标准交互。
- 请合理使用各平台服务，遵守对应平台的用户协议。作者对使用本工具所导致的任何账号限制或风控问题不承担责任。

---

## 📄 开源许可

本项目基于 [MIT License](LICENSE) 许可协议开放。
