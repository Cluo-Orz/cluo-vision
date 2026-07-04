# Cluo Vision 落地架构设计

> 版本: v2.0
> 日期: 2026-07-05
> 状态: 落地设计 + 当前实现基线
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

推荐架构分两层：P0 先保证番剧主链路稳定；电影/剧集的 Seerr/Arr/Prowlarr 继续作为 P1 候选，不再写成当前必选前提。

```text
Android TV / Mobile App
        |
        v
cluo-server (本地 BFF, 统一认证、聚合 API、隐藏服务密钥)
        |
        +-- P0 Jellyfin: 已入库媒体、元数据、播放历史、收藏、播放流
        +-- P0 AutoBangumi: 动漫搜索、RSS 订阅、追番规则、动漫下载状态
        +-- P0 qBittorrent: 下载队列与暂停/恢复控制
        +-- P0 Playback Provider: local-dev / Jellyfin stream-url / Android external-player
        +-- P1 Seerr: 影片/剧集发现与请求
        +-- P1 Sonarr/Radarr: 剧集/电影自动下载与归档
        +-- P1 Prowlarr: 用户配置的索引源管理
        +-- P1 Bazarr: 字幕管理
        |
        v
Playback Provider (可插拔播放策略)
```

核心原则:

1. App 不直接保存 Sonarr/Radarr/qBittorrent/Prowlarr 的密钥。
2. App 不实现站点爬虫，不内置具体资源站规则。
3. 播放能力先通过 POC 决策，不能把未验证的 Intent 深链写成既定事实。
4. P0 下载自动化先走 AutoBangumi + qBittorrent + Jellyfin 入库；Seerr + Sonarr/Radarr + Prowlarr 在本项目里仍需真实环境验证后再升级为主路径。
5. 本地已入库媒体的浏览和播放不依赖公网；新内容发现、索引搜索、RSS 更新自然需要公网。

当前实现已经完成并本地验证的主链路：

```text
注册/登录
  -> 统一发现搜索
  -> AutoBangumi/local-dev 番剧结果
  -> 订阅并生成下载任务
  -> 下载状态/暂停/恢复/完成
  -> 自动或手动入 Jellyfin/本地媒体库
  -> 媒体库筛选/详情/相关推荐
  -> Playback Provider 解析并启动播放
  -> 播放进度、历史、继续观看、已看/收藏写回
```

---

## 3. 组件选型

| 层级 | 推荐组件 | 用途 | 信心 | 备注 |
|------|----------|------|------|------|
| TV/手机 App | Flutter + StatefulWidget MVP | 统一 UI、遥控器导航、移动端复用 | 高 | 源码已落地；复杂度上来后再引入 Riverpod |
| TV 焦点 | Flutter 原生 Focus/Shortcuts | D-pad 焦点、确认、数字键导航 | 中高 | 已接入基础遥控器交互；仍需雷鸟电视实机测试 |
| TV 输入 | 原生输入桥 / `flutter_android_tv_text_field` / 手机辅助输入 | 搜索输入 | 中 | 不把长文本输入作为 TV 核心流程 |
| BFF | cluo-server | API 聚合、认证、凭据隔离 | 高 | Node.js/TypeScript 已实现主链路 |
| 媒体库 | Jellyfin | 媒体管理、进度、收藏、海报、播放流 | 高 | 已接入列表/搜索/详情/同步/扫描/播放上报 |
| 请求/发现 | Seerr | 发现、请求、连接 Sonarr/Radarr | 待验证 | 不进入番剧 P0；电影/剧集阶段再 POC |
| 剧集/电影 | Sonarr / Radarr | 搜索、下载调度、重命名、归档 | 待验证 | 成熟组件，但当前未接入本项目主链路 |
| 索引器 | Prowlarr | 用户配置索引器，同步给 Arr | 待验证 | 当前不直接依赖；Cluo 不处理站点规则 |
| 下载器 | qBittorrent | BT/PT 下载队列 | 中高 | 已接入队列、暂停/恢复和 v5/v4 控制兼容 |
| 动漫 | AutoBangumi | RSS 解析、追番、番剧整理 | 高 | 已按当前 SSE 搜索/订阅/规则/下载状态 API 适配 |
| 字幕 | Bazarr | Sonarr/Radarr 字幕自动化 | P1 | 电影/剧集阶段再接入 |
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

### 5.2 电影/电视剧流程（P1 候选，待验证）

该流程仍是合理候选，但不作为当前番剧 P0 的成功标准。接入前需要在真实 Seerr/Sonarr/Radarr/Prowlarr 环境里重新验证 API、路径映射、导入行为和质量配置。

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

当前实现状态：

- 已实现 AutoBangumi 搜索、订阅、状态、规则、RSS、下载状态代理，并保留 `local-dev` 回退，便于没有 Docker/真实服务时验证完整主链路。
- 下载队列已统一合并 AutoBangumi 和 qBittorrent；远端 qBittorrent 支持暂停/恢复，本地任务支持模拟完成。
- 已完成 `completed` 下载的手动入库、批量入库和服务端后台自动入库；Jellyfin 已配置时会触发扫描并按下载标题同步匹配条目。
- 电影/剧集仍保留 Seerr + Sonarr/Radarr + Prowlarr 方向，但不进入当前 P0 判定。等番剧链路在真实电视/真实服务上验证后再接。

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

### 6.3 当前 API 基线

```text
GET  /api/health
POST /api/auth/register
POST /api/auth/login
GET  /api/auth/me
GET  /api/system/status
GET  /api/home

GET  /api/discover/search?q=
GET  /api/discover/recent
GET  /api/discover/sources
GET  /api/discover/trending

GET  /api/anime/search?q=
GET  /api/anime/status
GET  /api/anime/rules
GET  /api/anime/rss
GET  /api/anime/subscriptions
POST /api/anime/subscribe
GET  /api/anime/downloads

GET  /api/downloads
POST /api/downloads/:id/pause
POST /api/downloads/:id/resume
POST /api/downloads/:id/import
POST /api/downloads/import-completed
POST /api/automation/download-import/run
POST /api/anime/downloads/:id/complete

GET  /api/library/items?limit=&status=
GET  /api/library/search?q=&limit=&status=
GET  /api/library/items/:id
GET  /api/library/items/:id/related
POST /api/library/items/:id/favorite
POST /api/library/items/:id/watched
POST /api/library/sync/jellyfin

GET  /api/playback/providers
POST /api/playback/resolve
GET  /api/playback/sessions
POST /api/playback/sessions
PATCH /api/playback/sessions/:id
POST /api/playback/sessions/:id/stop

GET  /api/history
POST /api/history/events

GET  /api/settings/services
PATCH /api/settings/services
POST /api/settings/jellyfin/login
```

P1 预留但当前未实现：`POST /api/requests`、`GET /api/requests`、Seerr/Sonarr/Radarr/Prowlarr 相关代理。

### 6.4 数据模型

```text
MediaItem
  id                 Cluo 本地 id；Jellyfin 条目通常是 jellyfin:<itemId>
  source             local-dev | jellyfin | autobangumi | qbittorrent
  type               anime-episode | movie | series-episode
  title
  posterUrl
  backdropUrl
  year
  overview
  durationSeconds
  playbackPositionSeconds
  watched
  favorite
  jellyfin.itemId

Request
  id
  type
  title
  status             pending | approved | processing | available | failed
  qualityProfile

DownloadTask
  id
  source             local-dev | qbittorrent | autobangumi
  title
  progress
  speedBytesPerSecond
  state              queued | downloading | paused | completed | failed
  importStatus

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
  - 基于本地事实源的推荐入口

找片
  - 统一搜索
  - 已接入来源和能力
  - 最近搜索
  - 推荐入口
  - 已入库结果
  - 番剧搜索结果
  - AutoBangumi 订阅/规则状态

媒体库
  - 全部/续播/未看/已看/收藏
  - 搜索
  - Jellyfin 同步/扫描同步
  - 详情页
  - 相关推荐

下载
  - 下载中
  - 已完成
  - 自动/手动入库
  - 失败/需处理

历史
  - 最近观看
  - 继续观看进度

设置
  - Jellyfin/qBittorrent/AutoBangumi 连接状态
  - 播放 Provider 选择和检测
  - Jellyfin 用户名/密码换 token
  - 外部播放器包名、MIME type、intent 目标检测
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

P0 番剧主链路最小栈:

| 服务 | 必选 | 说明 |
|------|------|------|
| Jellyfin | 是 | 媒体库事实源 |
| qBittorrent | 是 | 下载执行 |
| AutoBangumi | 是 | 动漫追番 |
| cluo-server | 是 | App API |

P1 电影/剧集扩展栈:

| 服务 | 必选 | 说明 |
|------|------|------|
| Prowlarr | 待验证 | 索引源配置 |
| Sonarr | 待验证 | 电视剧自动化 |
| Radarr | 待验证 | 电影自动化 |
| Seerr | 待验证 | 请求与发现 |
| Bazarr | 建议 | 字幕 |

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
    qbittorrent/
    autobangumi/
    sonarr/       # P1
    radarr/       # P1
    prowlarr/     # P1
    seerr/        # P1
    bazarr/
    cluo-server/
  backup/
```

容器内统一挂载:

```text
Jellyfin:     /data/media:ro
qBittorrent:  /data/torrents
AutoBangumi:  /app/config, /app/data, /data/media/anime
Sonarr:       /data                         # P1
Radarr:       /data                         # P1
Bazarr:       /data/media                   # P1
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

目标: 证明最关键链路可走通。当前机器无 Docker，先以本地 BFF + local-dev + 可选真实服务 smoke 为验收方式。

- [x] local-dev 主链路: 注册/登录 -> 搜索番剧 -> 订阅 -> 下载 -> 入库 -> 播放 session -> 历史/续播
- [x] cluo-server API、Flutter API 契约、Android debug APK 本地构建验证
- [x] AutoBangumi 当前 SSE 搜索/订阅/规则/下载状态 API 适配
- [x] qBittorrent v5/v4 队列控制适配
- [x] Jellyfin 媒体库、播放解析、进度上报、已看/收藏适配
- [ ] 目标服务器启动最小 Docker 栈: Jellyfin + qBittorrent + AutoBangumi + cluo-server
- [ ] Jellyfin 入库 4 类测试样片
- [ ] TV 上完成播放 Provider POC
- [ ] 验证 qBittorrent 临时密码、AutoBangumi 整理、Jellyfin 扫描
- [ ] 在真实 AutoBangumi + qBittorrent + Jellyfin 上跑 `npm run smoke:services`
- [ ] 记录默认播放 Provider 和兜底 Provider

通过标准:

1. TV 可播放 4K HDR 样片。
2. 至少一种 Provider 可写回 Jellyfin 进度，或明确实现 Cluo 进度上报方案。
3. 动漫 RSS 到下载到命名到入库闭环可完成。
4. 电影/剧集请求到下载到入库闭环作为 P1，不阻塞番剧 P0。

### Phase 1: 服务端和 API

- [x] cluo-server 初始化
- [x] 登录/注册/token 恢复
- [x] 服务配置和健康检查
- [x] Jellyfin 媒体库代理、同步、扫描、详情、已看/收藏、播放解析、进度上报
- [x] qBittorrent 下载状态代理、暂停/恢复
- [x] AutoBangumi 搜索、订阅、状态、规则、RSS、下载状态代理
- [x] 下载完成入库、批量入库、后台自动入库
- [x] PlaybackProvider 配置和解析接口
- [x] 统一发现搜索、已接入来源、推荐入口、最近搜索
- [x] 观看历史、首页继续观看/最近添加/下载中
- [ ] Seerr 请求代理（P1）
- [ ] Sonarr/Radarr/Prowlarr 代理（P1）

### Phase 2: TV App MVP

- [x] Flutter TV 骨架和 D-pad 导航
- [x] 首页、找片、媒体库、下载、历史、设置
- [x] 媒体库筛选、搜索、同步/扫描同步、详情、相关推荐
- [x] 番剧搜索、订阅、订阅/规则状态
- [x] 下载任务页、暂停/恢复、完成入库、自动入库状态
- [x] 设置页服务健康检查、Jellyfin 登录、播放 Provider 检测
- [x] 播放按钮接入 local-dev/Jellyfin stream-url/Android external-player
- [ ] 安装到雷鸟 Android TV 验证 external-player/Yamby 拉起
- [ ] 用真实样片验证 4K HDR、ASS 字幕、多音轨/多字幕

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
- Android TV TextField 插件: https://pub.dev/packages/flutter_android_tv_text_field
