# Cluo 视界

Cluo 视界是一个面向**电视大屏**和**手机移动端**的家庭影院应用。

> 🏗️ 项目处于早期设计阶段。

## 仓库结构

```
cluo-vision-dev/
├── cluo-vision/            # 👈 当前仓库 — 客户端 App
│   ├── docs/               # 产品、设计、架构文档
│   │   ├── project-goals.md        # 项目目标与原始诉求
│   │   └── architecture-design.md  # 整体架构设计
│   └── README.md
└── cluo-vision-server/     # 服务端 + Docker Compose
    ├── docker-compose.yml
    └── README.md
```

## 项目目标

详见 [`docs/project-goals.md`](docs/project-goals.md)

核心功能两大块：

| 功能 | 说明 |
|------|------|
| **找片** 🔍 | 搜索影片、浏览资源站、发起下载、查看下载进度 |
| **看片** 📺 | 浏览已下载的媒体库、海报墙、4K HDR 播放 |

## 技术栈

| 层级 | 选型 | 说明 |
|------|------|------|
| **框架** | Flutter 3.x | 一套代码覆盖 Android TV + Android 手机 + iOS |
| **状态管理** | Riverpod 2.x | 编译时安全，适合复杂异步场景 |
| **视频播放** | media_kit (libmpv) | 4K HDR/DV 硬解、ASS 字幕 |
| **网络层** | dio + retrofit | HTTP + API 类型生成 |
| **本地存储** | drift (SQLite) | 播放历史、缓存 |

## 平台支持

| 平台 | 优先级 | 状态 |
|------|--------|------|
| 雷鸟电视 (Android TV) | P0 | 待开发 |
| Android 手机 | P1 | 待开发 |
| iOS 手机 | P2 | 待开发 |

## 目标设备

- **电视**: FFALCON 鹤7 PRO 25款 85R795C（Android 14，灵控系统 3.0）
- **手机**: Android / iOS

## TV 端交互要点

- **D-pad 导航** — 所有可交互元素必须在 FocusNode 树中，焦点有视觉反馈
- **10-foot UI** — 字号 ≥ 24sp，卡片适配 3-5m 观看距离
- **遥控器映射** — 方向键=导航、确认=播放、返回=退出
- **文本输入** — 优先语音输入或手机扫码

## 开发约定

- 电视端交互优先考虑遥控器操作
- 手机端交互优先考虑单手操作和触控反馈
- 页面布局兼顾 10-foot UI 可读性与移动端信息密度
- 播放、导航、账号等核心流程需要可测试性
- 重要技术决策记录在 `docs/` 目录中

## 开发路线图

参见 [`docs/architecture-design.md`](docs/architecture-design.md) 第八章。

| 阶段 | 内容 | 预估 |
|------|------|------|
| P1 基础搭建 | Docker + Jellyfin + qBittorrent | 2-3 周 |
| P2 自动下载 | Sonarr + Radarr + Prowlarr + Jellyseerr | 1-2 周 |
| P3 自定义后端 | cluo-vision-server (Go API 聚合) | 2-3 周 |
| P4 App 开发 | Flutter TV + 手机端 | 4-6 周 |
| P5 打磨发布 | 测试、优化、发布 | 2-3 周 |

## 下一步

1. ✅ 确认技术栈 — Flutter + Jellyfin + Arr Stack
2. ⬜ 部署服务端基础环境（Jellyfin + qBittorrent）
3. ⬜ Flutter 项目初始化和基础脚手架
4. ⬜ 实现首页、跨端导航和基础播放能力
