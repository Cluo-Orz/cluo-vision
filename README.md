# Cluo 视界

Cluo 视界是一个面向**电视大屏**和**手机移动端**的家庭影院应用。

> 🏗️ 项目处于早期设计阶段。

当前仓库已开始落地 Flutter 客户端骨架：

- `pubspec.yaml` — Flutter 应用定义；运行时使用 `shared_preferences` 保存服务器地址和登录态
- `lib/main.dart` — TV-first MVP UI，直接调用 `cluo-server` API
- `android/` — Android 平台目录，已接入本地 HTTP、Android TV launcher 和播放启动 MethodChannel
- 已覆盖登录/注册、本地登录态恢复、首页、统一发现搜索、最近搜索、库内命中、番剧搜索与订阅、订阅/规则状态、下载列表、下载自动刷新、等待/错误状态展示、下载暂停/恢复、local-dev 下载完成、完成下载自动尝试入库、服务端后台入库手动触发、批量入库手动重试、入库后跳转详情、媒体库、Jellyfin 同步/扫描同步、详情、海报展示、播放会话、播放启动桥接、外部播放器安装/intent 检测、外部播放器返回后按离开时长回写进度、播放停止/标记看完、续播位置展示、播放状态写回媒体库、external-player intent 目标展示、历史、底层服务配置、Jellyfin 登录配置和系统诊断
- 已接入基础 TV 遥控器交互：方向键焦点移动、确认键触发、数字键 1-6 切换主导航、按钮/侧栏焦点高亮
- Flutter 测试已包含 `CluoApi` 主链路契约测试，用内存 HTTP server 校验客户端发出的 BFF 路径、query、请求体和 Bearer token

当前开发机已在 `.codex-tools/flutter` 拉取 Flutter SDK，并在 `.codex-tools/android-sdk` 安装 Android SDK。客户端已通过 `flutter analyze`、`flutter test` 和 `flutter build apk --debug`，debug APK 产物位于 `build/app/outputs/flutter-apk/app-debug.apk`；Android TV 实机播放 Provider 仍需在目标电视上验证。

Android TV 首次安装前建议把家庭服务器地址编进 APK，避免默认 `127.0.0.1` 在电视上指向电视自身：

```bash
flutter build apk --debug --dart-define=CLUO_DEFAULT_SERVER_URL=http://<server-lan-ip>:3000
```

App 内仍可在设置页切换服务器地址；用户手动保存后的地址会覆盖构建默认值。

## 仓库结构

```
cluo-vision-dev/
├── cluo-vision/            # 👈 当前仓库 — 客户端 App
│   ├── docs/               # 产品、设计、架构文档
│   │   ├── project-goals.md        # 项目目标与原始诉求
│   │   ├── architecture-design.md     # v1 历史草案
│   │   ├── architecture-design-v2.md  # 落地架构设计
│   │   └── android-playback-channel.md # Android 播放启动桥接
│   ├── android/            # Android 平台目录和播放启动桥接
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
| **框架** | Flutter 3.x | 一套代码覆盖 Android TV + Android 手机 + iOS；当前源码已通过 analyzer/test |
| **状态管理** | StatefulWidget MVP | 先保证主链路可跑；复杂度上来后再引入 Riverpod 等方案 |
| **视频播放** | Playback Provider + MethodChannel | 已接 Jellyfin stream-url 和 Android external-player intent；Android 原生桥接已写入 `MainActivity`，设置页可检测 Yamby/外部播放器包和 intent 解析，外部播放器返回后会按离开 App 的时长回写进度；实机播放和真实播放器进度同步仍需电视验证 |
| **网络层** | dart:io HttpClient | 当前无第三方依赖；后续按需要再换 dio/retrofit |
| **本地存储** | shared_preferences + cluo-server / Jellyfin | 客户端只保存服务器地址和登录 token；播放历史和进度由 BFF/Jellyfin 承担 |

## 平台支持

| 平台 | 优先级 | 状态 |
|------|--------|------|
| 雷鸟电视 (Android TV) | P0 | Android 平台目录、TV launcher、播放启动桥接和外部播放器检测已接入；待安装到电视并验证 external-player |
| Android 手机 | P1 | 复用同一 Flutter 源码，待布局细化 |
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

参见 [`docs/architecture-design-v2.md`](docs/architecture-design-v2.md) 第九章。

| 阶段 | 内容 | 预估 |
|------|------|------|
| P1 基础搭建 | Docker + Jellyfin + qBittorrent | 2-3 周 |
| P2 自动下载 | Sonarr + Radarr + Prowlarr + Seerr | 1-2 周 |
| P3 自定义后端 | cluo-server (本地 BFF / API 聚合) | 2-3 周 |
| P4 App 开发 | Flutter TV + 手机端 | 4-6 周 |
| P5 打磨发布 | 测试、优化、发布 | 2-3 周 |

## 下一步

1. ✅ 确认技术栈 — Flutter + Jellyfin + Arr Stack
2. ✅ cluo-server 本地 BFF 主链路开发
3. ✅ Flutter 项目源码骨架、基础 UI、服务配置、Jellyfin 登录配置、下载控制和完成下载入库入口
4. ✅ Flutter local-dev 下载完成入口，支持无 Docker 本地验证订阅到播放闭环
5. ✅ Flutter 基础 TV D-pad 焦点/确认/主导航快捷键
6. ✅ Flutter 侧播放启动 MethodChannel 抽象、Android 原生桥接和外部播放器检测
7. ✅ 外部播放器返回 Cluo 后自动按观看耗时回写播放历史
8. ✅ 下载列表刷新到 completed 任务后自动触发批量入库，pending-scan 会节流重试
9. ✅ 下载页可手动触发 cluo-server 后台自动入库
10. ✅ 媒体库页可触发 Jellyfin 同步和扫描同步
11. ✅ Flutter analyze / test
12. ✅ Android SDK 打包和 debug APK 构建
13. ⬜ 安装到 Android TV、external-player 实机验证
