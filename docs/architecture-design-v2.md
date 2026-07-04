# Cluo Vision 落地架构设计

> 版本: v2.0  
> 日期: 2026-07-05  
> 状态: 调研后设计草案  
> 需求源: `docs/project-goals.md`

---

## 1. 设计边界

`project-goals.md` 是需求源。里面出现的具体技术名词只作为候选方案，不作为不可变约束。

### 必须满足

| 目标 | 落地要求 |
|------|----------|
| 电视优先 | 雷鸟 Android TV 上遥控器可完成浏览、搜索、请求下载、查看进度、播放 |
| 找片 + 看片 | 一个 Cluo App 作为入口，底层可调用多个本地服务 |
| 合法自有媒体 | 不抓取视频源，不绕过 DRM，不提供在线盗版播放 |
| 自动化整理 | 下载后自动命名、归档、入 Jellyfin 媒体库 |
| 观看体验 | 4K HDR 稳定播放，动漫 ASS 字幕尽量正确，多音轨/字幕选择交给成熟播放器 |
| 进度同步 | 播放历史、继续观看、已看状态以 Jellyfin 为准 |
| 局域网可用 | 已入库媒体在无公网时仍可浏览和播放 |
| 可维护 | Cluo 只做统一体验层，重型能力交给成熟项目 |

### 不固定

| 项 | 说明 |
|----|------|
| 播放器名称 | Yamby、官方 Jellyfin Android TV、Kodi、Just Player 都只是候选 |
| App 框架 | Flutter 是推荐项，不是需求本身 |
| 后端语言 | Node.js/TypeScript、Go 都可行；先固定 API 边界 |
| 索引源列表 | 用户自行配置自己有权使用的索引源/RSS；设计文档不绑定具体站点 |
| HTTPS/域名 | 局域网 MVP 可用 HTTP + IP；Caddy/local domain 是增强项 |

---

## 2. 总体结论

Cluo Vision 应定位为本地媒体系统的 **BFF + TV/手机统一 UI**，而不是播放器、下载器或资源站爬虫。

推荐架构:

```text
Android TV / Mobile App
        |
        v
cluo-server (本地 BFF, 统一认证、聚合 API、隐藏服务密钥)
        |
        +-- Jellyfin: 已入库媒体、元数据、播放历史、收藏
        +-- Seerr: 影片/剧集发现与请求
        +-- Sonarr/Radarr: 剧集/电影自动下载与归档
        +-- Prowlarr: 用户配置的索引源管理
        +-- qBittorrent: 下载队列与进度
        +-- AutoBangumi: 动漫 RSS 追番与重命名
        +-- Bazarr: 字幕管理
        |
        v
Playback Provider (可插拔播放策略)
```

核心原则:

1. App 不直接保存 Sonarr/Radarr/qBittorrent/Prowlarr 的密钥。
2. App 不实现站点爬虫，不内置具体资源站规则。
3. 播放能力先通过 POC 决策，不能把未验证的 Intent 深链写成既定事实。
4. 下载自动化优先走 Seerr + Sonarr/Radarr + Prowlarr；动漫走 AutoBangumi；手动种子/磁力只做高级补充。
5. 本地已入库媒体的浏览和播放不依赖公网；新内容发现、索引搜索、RSS 更新自然需要公网。

---

## 3. 组件选型

| 层级 | 推荐组件 | 用途 | 信心 | 备注 |
|------|----------|------|------|------|
| TV/手机 App | Flutter + Riverpod | 统一 UI、遥控器导航、移动端复用 | 中高 | Flutter TV 需要实机焦点测试 |
| TV 焦点 | `dpad` | D-pad focus/region/memory | 中 | 包存在且面向 Flutter TV，但较新 |
| TV 输入 | 原生输入桥 / `flutter_android_tv_text_field` / 手机辅助输入 | 搜索输入 | 中 | 不把长文本输入作为 TV 核心流程 |
| BFF | cluo-server | API 聚合、认证、凭据隔离 | 高 | 语言后置，先定 API |
| 媒体库 | Jellyfin | 媒体管理、进度、收藏、海报 | 高 | 核心系统 |
| 请求/发现 | Seerr | 发现、请求、连接 Sonarr/Radarr | 高 | Jellyseerr 已迁移/重定向到 Seerr |
| 剧集/电影 | Sonarr / Radarr | 搜索、下载调度、重命名、归档 | 高 | 成熟组件 |
| 索引器 | Prowlarr | 用户配置索引器，同步给 Arr | 高 | Cluo 不直接处理站点规则 |
| 下载器 | qBittorrent | BT/PT 下载队列 | 高 | Web API 稳定 |
| 动漫 | AutoBangumi | RSS 解析、追番、番剧整理 | 高 | 有 REST API，适合动漫专项 |
| 字幕 | Bazarr | Sonarr/Radarr 字幕自动化 | 中高 | 作为主字幕方案 |
| 中文字幕补充 | ChineseSubFinder | 可选补充 | 中低 | 项目停更/维护弱，不作为 P0 |
| 反代 | Caddy | local domain / HTTPS | 中 | MVP 可先不用 |
| 反 Cloudflare 辅助 | FlareSolverr | 个别索引器可选依赖 | 低 | 不默认启用，避免扩大维护面 |

---

## 4. 播放策略

播放是本项目最大风险点。不能直接假设“某个 App 支持 itemId 深链并完美返回 Cluo”。

### 4.1 播放需求分层

| 层级 | 要求 | 是否 P0 |
|------|------|---------|
| 基础播放 | 已入库视频可从 Cluo 点击播放 | 是 |
| 进度同步 | 播放进度、已看状态写回 Jellyfin | 是 |
| 4K HDR | 本地高码率 4K HDR 稳定播放 | 是 |
| ASS 字幕 | 动漫 ASS 字幕尽量完整渲染 | 是 |
| Dolby Vision | 可直接播放则直接播放；不可用时回退 HDR10 | P1 |
| 音频直通 | TrueHD/DTS-HD 等直通功放 | P1 |

### 4.2 候选播放 Provider

Cluo App 内部应定义 `PlaybackProvider` 抽象，不把任何播放器写死:

```text
resolve(itemId, mediaSourceId) -> PlaybackTarget
play(target) -> PlaybackLaunchResult
```

候选 Provider:

| Provider | 优点 | 风险 | 结论 |
|----------|------|------|------|
| 官方 Jellyfin Android TV | 官方客户端，天然同步 Jellyfin 进度 | 公开资料只能确认 App 存在；未确认稳定 item 深链 | 必须 POC，不作为默认假设 |
| Kodi + Jellyfin for Kodi / JellyCon | Kodi 播放能力强；Jellyfin for Kodi 支持双向 watched/resume；Kodi 有 JSON-RPC | 初始配置复杂；Cluo 到具体 item 的打开方式需验证 | 高价值 POC，可能成为 TV 默认方案 |
| Just Player | Android TV 支持好；基于 Media3；兼容 HDR/DV 硬件能力；可接收 streaming link | SSA/ASS 是 limited styling；Jellyfin 进度同步不天然成立 | 适合高兼容播放兜底，不适合唯一默认 |
| Cluo 内置播放器 | 体验最统一，可自己写进度 | 4K HDR、DV、ASS、音频直通维护成本高 | 不作为 P0 默认 |

### 4.3 播放 POC 关卡

在 App 正式开发前必须完成 TV 实机 POC。通过标准:

1. 从 Cluo 或 ADB 启动候选播放器，能打开指定 Jellyfin item 或对应播放流。
2. 播放结束/返回后可回到 Cluo。
3. Jellyfin 中继续观看进度正确变化。
4. 用至少 4 类样片测试:
   - 4K HDR10 HEVC MKV
   - Dolby Vision profile 7/8 样片
   - 带 ASS 特效字幕的动漫 MKV
   - 多音轨、多字幕样片
5. 遥控器暂停、快进、字幕切换、音轨切换可用。

POC 优先级:

1. 官方 Jellyfin Android TV explicit Intent / deep link。
2. Kodi + Jellyfin for Kodi / JellyCon + JSON-RPC。
3. Just Player + Jellyfin stream URL。
4. 内置播放器最小实现。

只有第 1 或第 2 条通过，才能宣称“播放进度与 Jellyfin 天然同步”。如果只能使用 Just Player，需要增加 Cluo 自己的播放会话上报方案，或降低 V1 对进度同步的承诺。

---

## 5. 找片与下载策略

### 5.1 搜索分三类

| 类型 | 数据源 | 用途 |
|------|--------|------|
| 库内搜索 | Jellyfin | 已下载内容、继续观看、详情页 |
| 媒体发现 | Seerr / TMDB 元数据 | 查找电影/剧集并发起请求 |
| 索引搜索 | Sonarr/Radarr/Prowlarr/AutoBangumi | 已配置索引源中的可下载结果 |

Cluo 不做站点 WebView 聚合，不维护具体站点 DOM，不保存站点 Cookie。站点能力由 Prowlarr/AutoBangumi 这类专门组件处理。

### 5.2 电影/电视剧流程

```text
用户在 Cluo 搜索标题
  -> cluo-server 查询 Jellyfin + Seerr
  -> 已入库: 进入详情并播放
  -> 未入库: 用户选择请求
  -> Seerr 创建 request
  -> Radarr/Sonarr 按质量配置和索引器搜索
  -> qBittorrent 下载
  -> Sonarr/Radarr import、重命名、归档
  -> Jellyfin 扫描入库
  -> Cluo 首页出现“最近添加/可观看”
```

### 5.3 动漫流程

动漫不强行塞进 Sonarr/Radarr 的欧美剧模型。V1 推荐:

```text
用户在 Cluo 添加/查看番剧订阅
  -> cluo-server 调 AutoBangumi API
  -> AutoBangumi 解析 RSS、管理规则
  -> qBittorrent 下载
  -> AutoBangumi 重命名并整理到 anime 库
  -> Jellyfin 扫描入库
```

Cluo 对 AutoBangumi 暴露的能力:

| Cluo 功能 | AutoBangumi API |
|-----------|-----------------|
| 查看番剧规则 | `/api/v1/bangumi/get/all` |
| 添加 RSS | `/api/v1/rss/add` / `/rss/subscribe` |
| 搜索番剧 | `/api/v1/search/bangumi` |
| 查看运行状态 | `/api/v1/status` |
| 查看动漫下载 | `/api/v1/downloader/torrents` |

### 5.4 手动下载

手动下载不是 P0 主流程，但需要保留高级入口:

1. 用户提供 `.torrent` 文件或 magnet 链接。
2. Cluo 上传到 cluo-server。
3. cluo-server 添加到 qBittorrent 指定 category。
4. 用户手动或通过 Arr 导入到正确媒体库。

TV 端不适合复杂手动管理；高级操作优先放手机端或 Web 管理页。

---

## 6. cluo-server 边界

cluo-server 是本地 BFF，不替代 Jellyfin/Arr/AutoBangumi。

### 6.1 职责

1. 保存各服务地址和 API Key。
2. 提供单一认证入口，V1 可用本地单用户 PIN/密码。
3. 统一数据模型，避免 App 直接适配多个第三方 API。
4. 聚合服务健康状态。
5. 屏蔽下载器、索引器等敏感接口。
6. 为 TV 端返回轻量分页数据，减少 UI 端复杂度。

### 6.2 不做

1. 不实现 BT/PT 索引规则。
2. 不绕过 DRM。
3. 不做公网账号体系。
4. 不做多家庭/多租户权限。
5. 不做完整媒体数据库，Jellyfin 是媒体事实源。

### 6.3 推荐 API

```text
GET  /api/health
POST /api/auth/login
GET  /api/home

GET  /api/library/search?q=
GET  /api/library/items
GET  /api/library/items/:id
POST /api/library/items/:id/favorite
POST /api/library/items/:id/watched

GET  /api/discover/search?q=
GET  /api/discover/trending
POST /api/requests
GET  /api/requests

GET  /api/downloads
POST /api/downloads/pause
POST /api/downloads/resume

GET  /api/anime/rules
POST /api/anime/rss
GET  /api/anime/search?q=

GET  /api/playback/providers
POST /api/playback/resolve

GET  /api/settings/services
PATCH /api/settings/services
```

### 6.4 数据模型

```text
MediaItem
  id                 Jellyfin item id if available
  provider           jellyfin | seerr | sonarr | radarr | autobangumi
  type               movie | series | episode | anime | season
  title
  posterUrl
  backdropUrl
  year
  overview
  isAvailable
  playbackProgress
  favorite

Request
  id
  type
  title
  status             pending | approved | processing | available | failed
  qualityProfile

DownloadTask
  id
  source             qbittorrent | autobangumi
  title
  progress
  speed
  eta
  category
  state

PlaybackTarget
  provider
  mode               intent | jsonrpc | stream-url | embedded
  itemId
  url
  extras
```

---

## 7. App 信息架构

TV 端第一屏必须是实际使用界面，不做宣传页。

```text
首页
  - 继续观看
  - 最近添加
  - 正在下载
  - 推荐/热门

找片
  - 搜索
  - 已入库结果
  - 可请求结果
  - 请求状态

媒体库
  - 电影
  - 电视剧
  - 动漫
  - 筛选/排序
  - 详情页

任务
  - 下载中
  - 等待导入
  - 失败/需处理
  - 动漫订阅状态

设置
  - Jellyfin/Seerr/Arr/qBittorrent/AutoBangumi 连接状态
  - 播放 Provider 选择和检测
  - 质量偏好
  - 字幕偏好
```

TV 输入策略:

1. 搜索框支持遥控器输入，但不依赖长文本输入。
2. P1 增加手机配对输入。
3. 优先支持历史搜索、热门推荐、分类筛选，减少电视端打字。
4. 所有主要操作必须有 D-pad 焦点反馈。

手机端:

1. P1 支持浏览、搜索、请求、下载管理。
2. 手机播放可跳转官方 Jellyfin/Swiftfin/Infuse 等客户端，或只提供“在媒体客户端打开”。
3. 手机遥控器是 P2，不进入 MVP。

---

## 8. 部署设计

### 8.1 服务分层

P0 基础:

| 服务 | 必选 | 说明 |
|------|------|------|
| Jellyfin | 是 | 媒体库事实源 |
| qBittorrent | 是 | 下载执行 |
| Prowlarr | 是 | 索引源配置 |
| Sonarr | 是 | 电视剧 |
| Radarr | 是 | 电影 |
| Seerr | 是 | 请求与发现 |
| AutoBangumi | 是 | 动漫追番 |
| Bazarr | 建议 | 字幕 |
| cluo-server | 是 | App API |

可选:

| 服务 | 何时启用 |
|------|----------|
| Caddy | 需要 local domain / HTTPS 时 |
| FlareSolverr | 某个用户已授权索引器明确需要时 |
| ChineseSubFinder | Bazarr 不能满足中文外字幕时 |

### 8.2 路径规划

推荐使用单一数据根，避免 Docker 内外路径不一致导致 Arr import 失败，也方便硬链接:

```text
/nas/cluo/
  data/
    media/
      movies/
      tv/
      anime/
    torrents/
      movies/
      tv/
      anime/
      incomplete/
  appdata/
    jellyfin/
    sonarr/
    radarr/
    prowlarr/
    qbittorrent/
    seerr/
    autobangumi/
    bazarr/
    cluo-server/
  backup/
```

容器内统一挂载:

```text
Jellyfin:     /data/media:ro
Sonarr:       /data
Radarr:       /data
qBittorrent:  /data/torrents
AutoBangumi:  /app/config, /app/data, /data/media/anime
Bazarr:       /data/media
```

### 8.3 Compose 原则

1. 生产环境避免全量 `latest`，至少 pin major/minor tag。
2. Jellyfin 官方镜像可用 `jellyfin/jellyfin` 或 `ghcr.io/jellyfin/jellyfin`。
3. Seerr 使用 `ghcr.io/seerr-team/seerr`，不要继续按旧 Jellyseerr 仓库写新设计。
4. AutoBangumi 使用 `ghcr.io/estrellaxd/auto_bangumi`，并持久化 `/app/config` 和 `/app/data`。
5. qBittorrent 初始密码以容器日志为准，不能写死 `adminadmin`。
6. `/dev/dri` 硬件转码挂载应放到可选 profile/override；没有 Intel/AMD 核显时不应阻止启动。
7. Caddy 不应代理未启用的 `cluo-server`；先有服务再启用路由。
8. 局域网 MVP 用 `http://server-ip:port` 即可；HTTPS/local domain 是第二阶段。

---

## 9. 开发路线图

### Phase 0: 可行性 POC

目标: 在写正式 App 前证明最关键链路可走通。

- [ ] 启动最小 Docker 栈: Jellyfin + qBittorrent + Sonarr + Radarr + Prowlarr + Seerr + AutoBangumi
- [ ] Jellyfin 入库 4 类测试样片
- [ ] TV 上完成播放 Provider POC
- [ ] 验证 qBittorrent 临时密码、Arr import、Jellyfin 扫描
- [ ] 验证 AutoBangumi API 和 RSS 订阅流程
- [ ] 记录默认播放 Provider 和兜底 Provider

通过标准:

1. TV 可播放 4K HDR 样片。
2. 至少一种 Provider 可写回 Jellyfin 进度，或明确实现 Cluo 进度上报方案。
3. 电影/剧集请求到下载到入库闭环可完成。
4. 动漫 RSS 到下载到命名到入库闭环可完成。

### Phase 1: 服务端和 API

- [ ] cluo-server 初始化
- [ ] 服务配置和健康检查
- [ ] Jellyfin 媒体库代理
- [ ] Seerr 请求代理
- [ ] qBittorrent 下载状态代理
- [ ] AutoBangumi 状态和订阅代理
- [ ] PlaybackProvider 配置接口

### Phase 2: TV App MVP

- [ ] Flutter TV 骨架和 D-pad 导航
- [ ] 首页、媒体库、详情页
- [ ] 播放按钮接入已验证 Provider
- [ ] 找片搜索和请求
- [ ] 下载任务页
- [ ] 设置页服务健康检查

### Phase 3: 手机端

- [ ] 手机布局适配
- [ ] 搜索/请求/下载管理
- [ ] 手机端播放跳转策略
- [ ] 手机辅助 TV 输入

### Phase 4: 打磨

- [ ] 图片缓存和列表性能
- [ ] 错误态、空态、重试
- [ ] 自动备份 appdata
- [ ] 服务升级文档
- [ ] 实机回归测试清单

---

## 10. 风险清单

| 风险 | 影响 | 应对 |
|------|------|------|
| 播放器深链不可用 | 无法一键播放指定 item | Phase 0 必测；保留 Provider 抽象 |
| ASS 与 Dolby Vision 很难由同一播放器完美满足 | 动漫和 4K 原盘体验冲突 | 允许按媒体类型选择 Provider；DV 可回退 HDR10 |
| Just Player 等外部播放器不写回 Jellyfin 进度 | 继续观看不准 | 仅作为兜底；默认选可同步方案 |
| TV 输入效率低 | 搜索体验差 | 手机辅助输入、推荐入口、历史搜索 |
| 索引源不可用或规则变化 | 找片失败 | 交给 Prowlarr/AutoBangumi；Cluo 不写站点适配 |
| NAS 路径不一致 | Arr import 失败、无法硬链接 | 统一 `/data` 根挂载 |
| 服务 API 版本变化 | BFF 失效 | cluo-server 做适配层，镜像版本 pinning |
| Docker 运行环境无 `/dev/dri` | Jellyfin 容器启动或转码失败 | 硬件转码 profile 化 |
| 离线预期误解 | 无公网时不能发现新内容 | 文档明确: 已入库可离线，新内容发现需要公网 |

---

## 11. 调研依据

截至 2026-07-05，设计参考了以下公开资料:

- Jellyfin 官方文档: https://jellyfin.org/docs/
- Jellyfin 官方客户端列表: https://jellyfin.org/downloads/clients/all/
- Jellyfin Android TV 仓库: https://github.com/jellyfin/jellyfin-androidtv
- Jellyfin Docker 文档: https://jellyfin.org/docs/general/installation/container/
- Seerr 文档: https://docs.seerr.dev/
- Seerr Docker 文档: https://docs.seerr.dev/getting-started/docker/
- Sonarr API 文档: https://sonarr.tv/docs/api/
- Radarr API 文档: https://radarr.video/docs/api/
- Prowlarr API 文档: https://prowlarr.com/docs/api/
- qBittorrent Web API: https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-5.0)
- LinuxServer qBittorrent 镜像文档: https://docs.linuxserver.io/images/docker-qbittorrent/
- AutoBangumi 文档: https://www.autobangumi.org/
- AutoBangumi API 文档: https://www.autobangumi.org/api/
- Just Player 仓库: https://github.com/moneytoo/Player
- Jellyfin for Kodi 仓库: https://github.com/jellyfin/jellyfin-kodi
- JellyCon 仓库: https://github.com/jellyfin/jellycon
- Kodi JSON-RPC 文档: https://kodi.wiki/view/JSON-RPC_API
- Flutter dpad 包: https://pub.dev/packages/dpad
- Android TV TextField 插件: https://pub.dev/packages/flutter_android_tv_text_field
