import "dart:convert";
import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  runApp(const CluoApp());
}

class _SelectTabIntent extends Intent {
  const _SelectTabIntent(this.tab);

  final int tab;
}

const _localDevServerUrl = "http://127.0.0.1:3000";
const _configuredDefaultServerUrl = String.fromEnvironment(
  "CLUO_DEFAULT_SERVER_URL",
  defaultValue: _localDevServerUrl,
);
const _prefsServerUrlKey = "cluo.serverUrl";
const _prefsAuthTokenKey = "cluo.authToken";
const _prefsDisplayNameKey = "cluo.displayName";
const _autoImportRetryDelay = Duration(minutes: 2);

String get defaultServerUrl => normalizeBaseUrlWithFallback(
    _configuredDefaultServerUrl, _localDevServerUrl);

class CluoApp extends StatefulWidget {
  const CluoApp({super.key});

  @override
  State<CluoApp> createState() => _CluoAppState();
}

class _CluoAppState extends State<CluoApp> with WidgetsBindingObserver {
  final _serverController = TextEditingController(text: defaultServerUrl);
  final _usernameController = TextEditingController(text: "owner");
  final _passwordController = TextEditingController(text: "change-me");
  final _animeSearchController = TextEditingController();
  final _librarySearchController = TextEditingController();
  final _autoBangumiUrlController = TextEditingController();
  final _autoBangumiTokenController = TextEditingController();
  final _autoBangumiProviderController = TextEditingController(text: "mikan");
  final _qBittorrentUrlController = TextEditingController();
  final _qBittorrentUsernameController = TextEditingController();
  final _qBittorrentPasswordController = TextEditingController();
  final _qBittorrentApiKeyController = TextEditingController();
  final _jellyfinUrlController = TextEditingController();
  final _jellyfinTokenController = TextEditingController();
  final _jellyfinUserIdController = TextEditingController();
  final _jellyfinUsernameController = TextEditingController();
  final _jellyfinPasswordController = TextEditingController();
  final _jellyfinDeviceIdController = TextEditingController(
    text: "cluo-server-dev",
  );
  final _externalPlayerPackageController = TextEditingController();
  final _externalPlayerMimeTypeController = TextEditingController(
    text: "video/*",
  );

  late CluoApi _api;
  int _tab = 0;
  bool _loading = false;
  bool _backgroundRefreshing = false;
  String _status = "未连接";
  String _displayName = "";
  String _playbackProvider = "local-dev";

  HomeData? _home;
  SystemStatus? _systemStatus;
  PlaybackHandlerDiagnostics? _playbackHandlers;
  List<AnimeSearchResult> _animeResults = [];
  List<AnimeSubscription> _animeSubscriptions = [];
  List<AnimeRule> _animeRules = [];
  bool _animeRulesConfigured = false;
  List<SearchHistoryEntry> _discoverHistory = [];
  List<MediaItem> _discoverLibraryMatches = [];
  List<DownloadTask> _downloads = [];
  List<MediaItem> _library = [];
  List<HistoryEntry> _history = [];
  MediaItem? _selectedMedia;
  PlaybackSession? _session;
  Timer? _refreshTimer;
  DateTime? _externalPlaybackLeftAt;
  bool _externalPlaybackWasBackgrounded = false;
  bool _finalizingExternalPlayback = false;
  bool _autoImportingCompletedDownloads = false;
  final Map<String, DateTime> _autoImportLastAttemptByDownloadId = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = CluoApi(_serverController.text);
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _backgroundRefresh(),
    );
    _run(_bootstrap);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _animeSearchController.dispose();
    _librarySearchController.dispose();
    _autoBangumiUrlController.dispose();
    _autoBangumiTokenController.dispose();
    _autoBangumiProviderController.dispose();
    _qBittorrentUrlController.dispose();
    _qBittorrentUsernameController.dispose();
    _qBittorrentPasswordController.dispose();
    _qBittorrentApiKeyController.dispose();
    _jellyfinUrlController.dispose();
    _jellyfinTokenController.dispose();
    _jellyfinUserIdController.dispose();
    _jellyfinUsernameController.dispose();
    _jellyfinPasswordController.dispose();
    _jellyfinDeviceIdController.dispose();
    _externalPlayerPackageController.dispose();
    _externalPlayerMimeTypeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = _session;
    if (session == null || !session.shouldTrackExternalReturn) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _externalPlaybackWasBackgrounded = true;
      _externalPlaybackLeftAt ??= DateTime.now();
      return;
    }

    if (state == AppLifecycleState.resumed &&
        _externalPlaybackWasBackgrounded) {
      unawaited(_finalizeExternalPlaybackReturn());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Cluo Vision",
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff1fb6a6),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff101416),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          bodyLarge: TextStyle(fontSize: 19),
          bodyMedium: TextStyle(fontSize: 17),
        ),
      ),
      home: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(
            TraversalDirection.left,
          ),
          SingleActivator(LogicalKeyboardKey.arrowRight):
              DirectionalFocusIntent(TraversalDirection.right),
          SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
            TraversalDirection.up,
          ),
          SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
            TraversalDirection.down,
          ),
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.digit1): _SelectTabIntent(0),
          SingleActivator(LogicalKeyboardKey.digit2): _SelectTabIntent(1),
          SingleActivator(LogicalKeyboardKey.digit3): _SelectTabIntent(2),
          SingleActivator(LogicalKeyboardKey.digit4): _SelectTabIntent(3),
          SingleActivator(LogicalKeyboardKey.digit5): _SelectTabIntent(4),
          SingleActivator(LogicalKeyboardKey.digit6): _SelectTabIntent(5),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _SelectTabIntent: CallbackAction<_SelectTabIntent>(
              onInvoke: (intent) {
                _selectTab(intent.tab);
                return null;
              },
            ),
          },
          child: Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  _SideNav(
                    selected: _tab,
                    signedIn: _api.token != null,
                    onSelected: _selectTab,
                  ),
                  Expanded(
                    child: FocusTraversalGroup(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Header(
                              title: _titleForTab(),
                              status: _loading ? "处理中..." : _status,
                              displayName: _displayName,
                              onRefresh: () => _run(_refreshAll),
                            ),
                            const SizedBox(height: 24),
                            Expanded(child: _page()),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectTab(int value) {
    final next = _api.token == null && value != 0 && value != 5 ? 0 : value;
    if (_tab == next) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _tab = next);
  }

  String _titleForTab() {
    return switch (_tab) {
      0 => "首页",
      1 => "找片",
      2 => "媒体库",
      3 => "下载",
      4 => "历史",
      _ => "设置",
    };
  }

  Widget _page() {
    if (_tab != 5 && _api.token == null) {
      return _signedOutPanel();
    }

    return switch (_tab) {
      0 => _homePage(),
      1 => _discoverPage(),
      2 => _libraryPage(),
      3 => _downloadsPage(),
      4 => _historyPage(),
      _ => _settingsPage(),
    };
  }

  Widget _signedOutPanel() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "先登录本地 cluo-server",
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text("默认地址是开发机本地服务。电视实机需要改成局域网服务器 IP。"),
          const SizedBox(height: 24),
          _authFields(),
        ],
      ),
    );
  }

  Widget _homePage() {
    final home = _home;
    if (home == null) return _empty("登录后刷新首页");

    return ListView(
      children: [
        _SectionTitle("继续观看", trailing: "${home.continueWatching.length}"),
        _HorizontalRail(
          children: [
            for (final item in home.continueWatching)
              _InfoCard(
                title: item.title,
                subtitle: "${(item.progress * 100).round()}% · ${item.source}",
                posterUrl: item.posterUrl,
                actionLabel: "播放",
                onAction: () => _run(() => _playItem(item.itemId)),
              ),
          ],
        ),
        const SizedBox(height: 28),
        _SectionTitle("最近添加", trailing: "${home.recentlyAdded.length}"),
        _HorizontalRail(
          children: [
            for (final item in home.recentlyAdded)
              _MediaCard(
                item: item,
                onDetail: () => _run(() => _loadMediaDetail(item.id)),
                onPlay: () => _run(() => _playItem(item.id)),
              ),
          ],
        ),
        const SizedBox(height: 28),
        _SectionTitle("下载中", trailing: "${home.activeDownloads.length}"),
        _TaskList(
          tasks: home.activeDownloads,
          onPause: (task) => _run(() => _controlDownload(task, "pause")),
          onResume: (task) => _run(() => _controlDownload(task, "resume")),
          onComplete: (task) => _run(() => _completeDownload(task)),
          onImport: (task) => _run(() => _importDownload(task)),
        ),
      ],
    );
  }

  Widget _discoverPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _animeSearchController,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: "搜索番剧",
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _run(_searchAnime),
              ),
            ),
            const SizedBox(width: 16),
            _PrimaryAction(label: "搜索", onPressed: () => _run(_searchAnime)),
          ],
        ),
        const SizedBox(height: 16),
        if (_discoverHistory.isNotEmpty) ...[
          _SearchHistoryBar(
            items: _discoverHistory,
            onSelected: (entry) {
              _animeSearchController.text = entry.query;
              _run(_searchAnime);
            },
          ),
          const SizedBox(height: 16),
        ],
        _AnimeTrackingPanel(
          subscriptions: _animeSubscriptions,
          rules: _animeRules,
          rulesConfigured: _animeRulesConfigured,
          onRefresh: () => _run(_loadAnimeTracking),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: _animeResults.isEmpty && _discoverLibraryMatches.isEmpty
              ? _empty("输入番名后搜索 AutoBangumi 或本地开发目录")
              : ListView(
                  children: [
                    if (_discoverLibraryMatches.isNotEmpty) ...[
                      _SectionTitle(
                        "库内命中",
                        trailing: "${_discoverLibraryMatches.length}",
                      ),
                      _HorizontalRail(
                        children: [
                          for (final item in _discoverLibraryMatches)
                            _MediaCard(
                              item: item,
                              onDetail: () =>
                                  _run(() => _loadMediaDetail(item.id)),
                              onPlay: () => _run(() => _playItem(item.id)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                    _SectionTitle("番剧结果", trailing: "${_animeResults.length}"),
                    if (_animeResults.isEmpty)
                      const SizedBox(
                        height: 120,
                        child: Center(child: Text("没有找到可订阅番剧")),
                      )
                    else
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        mainAxisSpacing: 18,
                        crossAxisSpacing: 18,
                        childAspectRatio: 1.45,
                        children: [
                          for (final result in _animeResults)
                            _InfoCard(
                              title: result.title,
                              subtitle:
                                  "${result.provider} · ${(result.confidence * 100).round()}%",
                              body: result.description,
                              posterUrl: result.posterUrl,
                              actionLabel: "订阅",
                              onAction: () =>
                                  _run(() => _subscribeAnime(result)),
                            ),
                        ],
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _libraryPage() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _librarySearchController,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        labelText: "搜索媒体库",
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _run(_searchLibrary),
                    ),
                  ),
                  const SizedBox(width: 16),
                  _SecondaryAction(
                    label: "刷新",
                    onPressed: () => _run(_loadLibrary),
                  ),
                  const SizedBox(width: 12),
                  _PrimaryAction(
                    label: "搜索",
                    onPressed: () => _run(_searchLibrary),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _library.isEmpty
                    ? _empty("媒体库为空。先订阅番剧或同步 Jellyfin。")
                    : GridView.count(
                        crossAxisCount: 3,
                        mainAxisSpacing: 18,
                        crossAxisSpacing: 18,
                        childAspectRatio: 1.28,
                        children: [
                          for (final item in _library)
                            _MediaCard(
                              item: item,
                              onDetail: () =>
                                  _run(() => _loadMediaDetail(item.id)),
                              onPlay: () => _run(() => _playItem(item.id)),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(flex: 2, child: _detailPanel()),
      ],
    );
  }

  Widget _detailPanel() {
    final media = _selectedMedia;
    if (media == null) return _Panel(child: _empty("选择条目查看详情"));

    return _Panel(
      child: ListView(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 108,
                child: _PosterArt(url: media.posterUrl, title: media.title),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.title,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      [
                        media.source,
                        media.year?.toString(),
                        media.communityRating == null
                            ? null
                            : "${media.communityRating!.toStringAsFixed(1)} 分",
                        media.watched ? "已看" : "未看",
                        media.favorite ? "已收藏" : null,
                      ].whereType<String>().join(" · "),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(media.overview?.isNotEmpty == true ? media.overview! : "暂无简介"),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _PrimaryAction(
                label: "播放",
                onPressed: () => _run(() => _playItem(media.id)),
              ),
              _SecondaryAction(
                label: media.watched ? "标记未看" : "标记已看",
                onPressed: () => _run(() => _setWatched(media, !media.watched)),
              ),
              _SecondaryAction(
                label: media.favorite ? "取消收藏" : "收藏",
                onPressed: () =>
                    _run(() => _setFavorite(media, !media.favorite)),
              ),
            ],
          ),
          if (_session != null) ...[
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 16),
            Text("播放会话", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              "${_session!.provider} / ${_session!.mode} / ${_session!.state} / ${(_session!.progress * 100).round()}% / ${formatDuration(_session!.positionSeconds)}",
            ),
            if (_session!.url != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                _session!.url!,
                style: const TextStyle(fontSize: 14),
              ),
            ],
            if (_session!.intentUri != null) ...[
              const SizedBox(height: 8),
              const Text(
                "Android Intent URI",
                style: TextStyle(color: Color(0xff9fb3b7)),
              ),
              const SizedBox(height: 4),
              SelectableText(
                _session!.intentUri!,
                style: const TextStyle(fontSize: 14),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                _SecondaryAction(
                  label: "记录 25%",
                  onPressed: () => _run(() => _heartbeat(0.25)),
                ),
                _SecondaryAction(
                  label: "标记看完",
                  onPressed: () => _run(() => _stopPlayback(ratio: 0.95)),
                ),
                _SecondaryAction(
                  label: "停止",
                  onPressed: () => _run(() => _stopPlayback()),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _downloadsPage() {
    final completedCount =
        _downloads.where((task) => task.state == "completed").length;

    return _downloads.isEmpty
        ? _empty("暂无下载任务")
        : ListView(
            children: [
              if (completedCount > 0) ...[
                _Panel(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "$completedCount 个任务已完成，正在自动尝试 Jellyfin 扫描和入库匹配",
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _SecondaryAction(
                            label: "运行后台入库",
                            onPressed: () => _run(_runDownloadImportAutomation),
                          ),
                          _PrimaryAction(
                            label: "重试入库",
                            onPressed: () => _run(_importCompletedDownloads),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _TaskList(
                tasks: _downloads,
                onPause: (task) => _run(() => _controlDownload(task, "pause")),
                onResume: (task) =>
                    _run(() => _controlDownload(task, "resume")),
                onComplete: (task) => _run(() => _completeDownload(task)),
                onImport: (task) => _run(() => _importDownload(task)),
              ),
            ],
          );
  }

  Widget _historyPage() {
    if (_history.isEmpty) return _empty("暂无观看历史");

    return ListView.separated(
      itemCount: _history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = _history[index];
        return _Panel(
          child: ListTile(
            title: Text(entry.title),
            subtitle: Text(
              "${(entry.progress * 100).round()}% · ${entry.lastWatchedAt}",
            ),
            trailing: _SecondaryAction(
              label: "播放",
              onPressed: () => _run(() => _playItem(entry.itemId)),
            ),
          ),
        );
      },
    );
  }

  Widget _settingsPage() {
    return ListView(
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "服务器",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _serverController,
                      decoration: const InputDecoration(
                        labelText: "cluo-server 地址",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  _PrimaryAction(label: "应用", onPressed: _applyServer),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _Panel(child: _authFields()),
        if (_api.token != null) ...[
          const SizedBox(height: 20),
          _serviceSettingsPanel(),
          const SizedBox(height: 20),
          _diagnosticsPanel(),
        ],
        const SizedBox(height: 20),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "播放策略",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                "App 通过 cluo-server 创建播放 session，并尝试经 MethodChannel 启动外部播放器；未接 Android 原生桥接时会保留播放 URL/intent。",
              ),
              const SizedBox(height: 12),
              Text(
                _session == null
                    ? "暂无播放会话"
                    : "${_session!.provider} / ${_session!.mode}",
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _serviceSettingsPanel() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "底层服务",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          _twoColumnFields([
            _settingField(
              "AutoBangumi",
              _autoBangumiUrlController,
              "http://127.0.0.1:7892",
            ),
            _settingField(
              "AutoBangumi Token",
              _autoBangumiTokenController,
              "留空保持不变",
              obscure: true,
            ),
            _settingField("搜索源", _autoBangumiProviderController, "mikan"),
            _settingField(
              "qBittorrent",
              _qBittorrentUrlController,
              "http://127.0.0.1:8080",
            ),
            _settingField(
              "qBittorrent 用户",
              _qBittorrentUsernameController,
              "admin",
            ),
            _settingField(
              "qBittorrent 密码",
              _qBittorrentPasswordController,
              "留空保持不变",
              obscure: true,
            ),
            _settingField(
              "qBittorrent API Key",
              _qBittorrentApiKeyController,
              "可选",
              obscure: true,
            ),
            _settingField(
              "Jellyfin",
              _jellyfinUrlController,
              "http://127.0.0.1:8096",
            ),
            _settingField(
              "Jellyfin Token",
              _jellyfinTokenController,
              "留空保持不变",
              obscure: true,
            ),
            _settingField(
              "Jellyfin User ID",
              _jellyfinUserIdController,
              "用户 ID",
            ),
            _settingField(
              "Jellyfin 用户名",
              _jellyfinUsernameController,
              "用于一键获取 token/userId",
            ),
            _settingField(
              "Jellyfin 密码",
              _jellyfinPasswordController,
              "不会保存",
              obscure: true,
            ),
            _settingField(
              "Device ID",
              _jellyfinDeviceIdController,
              "cluo-server-dev",
            ),
            _settingField(
              "外部播放器包名",
              _externalPlayerPackageController,
              "可选，例如 com.hush.yamby",
            ),
            _settingField(
              "外部播放器 MIME",
              _externalPlayerMimeTypeController,
              "video/*",
            ),
            DropdownButtonFormField<String>(
              initialValue: _playbackProvider,
              decoration: const InputDecoration(
                labelText: "播放 Provider",
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: "local-dev", child: Text("local-dev")),
                DropdownMenuItem(value: "jellyfin", child: Text("jellyfin")),
                DropdownMenuItem(
                  value: "external-player",
                  child: Text("external-player"),
                ),
                DropdownMenuItem(value: "kodi", child: Text("kodi")),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _playbackProvider = value);
              },
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _PrimaryAction(
                label: "保存配置",
                onPressed: () => _run(_saveServiceSettings),
              ),
              _SecondaryAction(
                label: "登录 Jellyfin",
                onPressed: () => _run(_loginJellyfin),
              ),
              _SecondaryAction(
                label: "刷新诊断",
                onPressed: () => _run(_loadSystemStatus),
              ),
              _SecondaryAction(
                label: "Yamby 预设",
                onPressed: _useYambyPreset,
              ),
              _SecondaryAction(
                label: "检测播放器",
                onPressed: () => _run(_checkPlaybackHandlers),
              ),
            ],
          ),
          if (_playbackHandlers != null) ...[
            const SizedBox(height: 16),
            _playbackHandlerPanel(_playbackHandlers!),
          ],
        ],
      ),
    );
  }

  Widget _playbackHandlerPanel(PlaybackHandlerDiagnostics handlers) {
    final rows = [
      ("平台", handlers.platform),
      (
        "包名",
        handlers.packageName?.isNotEmpty == true ? handlers.packageName! : "未指定"
      ),
      ("包已安装", handlers.packageInstalled ? "是" : "否"),
      ("URL 可处理", handlers.canHandleUrl ? "是" : "否"),
      ("Intent 可处理", handlers.canHandleIntentUri ? "是" : "否"),
      ("URL 候选", "${handlers.urlHandlerCount}"),
      ("Intent 候选", "${handlers.intentHandlerCount}"),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xff182125),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xff334247)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        children: [
          for (final row in rows)
            SizedBox(
              width: 180,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.$1,
                    style: const TextStyle(
                      color: Color(0xff8aa0a6),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    row.$2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          if (handlers.message != null)
            SizedBox(
              width: 360,
              child: Text(
                handlers.message!,
                style: const TextStyle(color: Color(0xffffc66d)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _diagnosticsPanel() {
    final status = _systemStatus;
    if (status == null) {
      return SizedBox(height: 160, child: _empty("暂无诊断数据"));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                "系统诊断",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              status.overall,
              style: const TextStyle(color: Color(0xff9fb3b7)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in status.items)
              SizedBox(width: 300, child: _DiagnosticCard(item: item)),
          ],
        ),
      ],
    );
  }

  Widget _twoColumnFields(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return GridView.count(
          crossAxisCount: wide ? 2 : 1,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: wide ? 5.2 : 4.8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }

  Widget _settingField(
    String label,
    TextEditingController controller,
    String hint, {
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _authFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: "用户名",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "密码",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          children: [
            _PrimaryAction(label: "登录", onPressed: () => _run(_login)),
            _SecondaryAction(label: "注册", onPressed: () => _run(_register)),
            if (_api.token != null)
              _SecondaryAction(label: "退出登录", onPressed: () => _run(_logout)),
          ],
        ),
      ],
    );
  }

  Widget _empty(String message) {
    return Center(
      child: Text(
        message,
        style: const TextStyle(fontSize: 22, color: Color(0xffb6c2c6)),
      ),
    );
  }

  void _applyServer() {
    _run(_applyServerChange);
  }

  Future<void> _applyServerChange() async {
    final baseUrl = normalizeBaseUrl(_serverController.text);
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_prefsServerUrlKey, baseUrl),
      prefs.remove(_prefsAuthTokenKey),
      prefs.remove(_prefsDisplayNameKey),
    ]);

    if (!mounted) return;
    setState(() {
      _serverController.text = baseUrl;
      _api = CluoApi(baseUrl);
      _status = "已切换服务器，需重新登录";
      _displayName = "";
      _animeResults = [];
      _animeSubscriptions = [];
      _animeRules = [];
      _animeRulesConfigured = false;
      _discoverHistory = [];
      _discoverLibraryMatches = [];
      _home = null;
      _systemStatus = null;
      _downloads = [];
      _library = [];
      _history = [];
      _selectedMedia = null;
      _session = null;
    });
    await _health();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _status = error.toString().replaceFirst("Exception: ", ""),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = normalizeBaseUrl(
      prefs.getString(_prefsServerUrlKey) ?? defaultServerUrl,
    );
    final token = prefs.getString(_prefsAuthTokenKey);
    final displayName = prefs.getString(_prefsDisplayNameKey) ?? "";

    if (!mounted) return;
    setState(() {
      _serverController.text = baseUrl;
      _api = CluoApi(baseUrl)..token = token;
      _displayName = displayName;
      _status = token == null ? "未登录" : "已恢复登录：$displayName";
    });

    await _health();
    if (token != null) {
      await _refreshAll();
    }
  }

  Future<void> _health() async {
    final result = await _api.health();
    setState(() => _status = "服务正常 · ${result["version"]}");
  }

  Future<void> _register() async {
    final username = _usernameController.text.trim();
    final result = await _api.register(
      username: username,
      password: _passwordController.text,
      displayName: username,
    );
    await _saveAuth(result);
    await _refreshAll();
  }

  Future<void> _login() async {
    final result = await _api.login(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
    await _saveAuth(result);
    await _refreshAll();
  }

  Future<void> _saveAuth(Map<String, dynamic> result) async {
    final user = asMap(result["user"]);
    final token = result["token"] as String?;
    final displayName = stringValue(user["displayName"]);
    final prefs = await SharedPreferences.getInstance();
    if (token != null) {
      await Future.wait([
        prefs.setString(
            _prefsServerUrlKey, normalizeBaseUrl(_serverController.text)),
        prefs.setString(_prefsAuthTokenKey, token),
        prefs.setString(_prefsDisplayNameKey, displayName),
      ]);
    } else {
      await Future.wait([
        prefs.remove(_prefsAuthTokenKey),
        prefs.remove(_prefsDisplayNameKey),
      ]);
    }

    if (!mounted) return;
    _api.token = token;
    setState(() {
      _displayName = displayName;
      _autoImportLastAttemptByDownloadId.clear();
      _status = "已登录：$_displayName";
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_prefsAuthTokenKey),
      prefs.remove(_prefsDisplayNameKey),
    ]);
    if (!mounted) return;
    setState(() {
      _api.token = null;
      _displayName = "";
      _home = null;
      _systemStatus = null;
      _animeResults = [];
      _animeSubscriptions = [];
      _animeRules = [];
      _animeRulesConfigured = false;
      _discoverHistory = [];
      _discoverLibraryMatches = [];
      _downloads = [];
      _library = [];
      _history = [];
      _selectedMedia = null;
      _session = null;
      _autoImportLastAttemptByDownloadId.clear();
      _status = "已退出登录";
      _tab = 5;
    });
  }

  Future<void> _refreshAll() async {
    if (_api.token == null) return;
    await Future.wait([
      _loadSettings(),
      _loadSystemStatus(),
      _loadAnimeTracking(),
      _loadDiscoverHistory(),
      _loadHome(),
      _loadDownloads(),
      _loadLibrary(),
      _loadHistory(),
    ]);
    setState(() => _status = "已刷新");
  }

  Future<void> _backgroundRefresh() async {
    if (!mounted || _api.token == null || _loading || _backgroundRefreshing) {
      return;
    }

    _backgroundRefreshing = true;
    try {
      await Future.wait([
        _loadHome(),
        _loadDownloads(),
        if (_tab == 1) _loadAnimeTracking(),
        if (_tab == 4) _loadHistory(),
      ]);
    } catch (_) {
      // Keep periodic refresh quiet; explicit refresh still reports errors.
    } finally {
      _backgroundRefreshing = false;
    }
  }

  Future<void> _loadHome() async {
    final result = await _api.home();
    setState(() => _home = HomeData.fromJson(result));
  }

  Future<void> _loadSettings() async {
    final result = await _api.serviceSettings();
    final services = asMap(result["services"]);
    final autoBangumi = asMap(services["autoBangumi"]);
    final qBittorrent = asMap(services["qBittorrent"]);
    final jellyfin = asMap(services["jellyfin"]);
    final playback = asMap(services["playback"]);

    setState(() {
      _autoBangumiUrlController.text = stringValue(autoBangumi["baseUrl"]);
      _autoBangumiTokenController.text = "";
      _autoBangumiProviderController.text = stringValue(
        autoBangumi["preferredProvider"],
        fallback: "mikan",
      );
      _qBittorrentUrlController.text = stringValue(qBittorrent["baseUrl"]);
      _qBittorrentUsernameController.text = stringValue(
        qBittorrent["username"],
      );
      _qBittorrentPasswordController.text = "";
      _qBittorrentApiKeyController.text = "";
      _jellyfinUrlController.text = stringValue(jellyfin["baseUrl"]);
      _jellyfinTokenController.text = "";
      _jellyfinUserIdController.text = stringValue(jellyfin["userId"]);
      _jellyfinPasswordController.text = "";
      _jellyfinDeviceIdController.text = stringValue(
        jellyfin["deviceId"],
        fallback: "cluo-server-dev",
      );
      _playbackProvider = stringValue(
        playback["preferredProvider"],
        fallback: "local-dev",
      );
      _externalPlayerPackageController.text = stringValue(
        playback["externalPlayerPackage"],
      );
      _externalPlayerMimeTypeController.text = stringValue(
        playback["externalPlayerMimeType"],
        fallback: "video/*",
      );
    });
  }

  Future<void> _loadSystemStatus() async {
    final result = await _api.systemStatus();
    setState(() => _systemStatus = SystemStatus.fromJson(result));
  }

  Future<void> _saveServiceSettings() async {
    final body = <String, Object?>{
      "autoBangumi": {
        "baseUrl": nullIfBlank(_autoBangumiUrlController.text),
        "preferredProvider":
            nullIfBlank(_autoBangumiProviderController.text) ?? "mikan",
        if (_autoBangumiTokenController.text.trim().isNotEmpty)
          "token": _autoBangumiTokenController.text.trim(),
      },
      "qBittorrent": {
        "baseUrl": nullIfBlank(_qBittorrentUrlController.text),
        "username": nullIfBlank(_qBittorrentUsernameController.text),
        if (_qBittorrentPasswordController.text.trim().isNotEmpty)
          "password": _qBittorrentPasswordController.text.trim(),
        if (_qBittorrentApiKeyController.text.trim().isNotEmpty)
          "apiKey": _qBittorrentApiKeyController.text.trim(),
      },
      "jellyfin": {
        "baseUrl": nullIfBlank(_jellyfinUrlController.text),
        "userId": nullIfBlank(_jellyfinUserIdController.text),
        "deviceId":
            nullIfBlank(_jellyfinDeviceIdController.text) ?? "cluo-server-dev",
        if (_jellyfinTokenController.text.trim().isNotEmpty)
          "token": _jellyfinTokenController.text.trim(),
      },
      "playback": {
        "preferredProvider": _playbackProvider,
        "externalPlayerPackage": nullIfBlank(
          _externalPlayerPackageController.text,
        ),
        "externalPlayerMimeType":
            nullIfBlank(_externalPlayerMimeTypeController.text) ?? "video/*",
      },
    };

    await _api.saveServiceSettings(body);
    await Future.wait([_loadSettings(), _loadSystemStatus()]);
    setState(() => _status = "配置已保存");
  }

  void _useYambyPreset() {
    setState(() {
      _playbackProvider = "external-player";
      _externalPlayerPackageController.text = "com.hush.yamby";
      _externalPlayerMimeTypeController.text = "video/*";
      _playbackHandlers = null;
      _status = "已填入 Yamby 预设，保存配置后生效";
    });
  }

  Future<void> _checkPlaybackHandlers() async {
    final result = await PlaybackLauncher.checkHandlers(
      packageName: nullIfBlank(_externalPlayerPackageController.text),
      mimeType:
          nullIfBlank(_externalPlayerMimeTypeController.text) ?? "video/*",
      sampleUrl: _session?.url,
      sampleIntentUri: _session?.intentUri,
    );
    setState(() {
      _playbackHandlers = result;
      _status = result.summary;
    });
  }

  Future<void> _loginJellyfin() async {
    final result = await _api.loginJellyfin(
      baseUrl: _jellyfinUrlController.text.trim(),
      username: _jellyfinUsernameController.text.trim(),
      password: _jellyfinPasswordController.text,
      deviceId:
          nullIfBlank(_jellyfinDeviceIdController.text) ?? "cluo-server-dev",
    );
    final user = asMap(result["user"]);
    _jellyfinPasswordController.text = "";
    await Future.wait([_loadSettings(), _loadSystemStatus()]);
    setState(() => _status = "Jellyfin 已登录：${stringValue(user["name"])}");
  }

  Future<void> _searchAnime() async {
    final query = _animeSearchController.text.trim();
    if (query.isEmpty) return;
    final result = await _api.discoverSearch(query);
    final anime = listOf(
      result["anime"],
    ).map(AnimeSearchResult.fromJson).toList();
    final library = listOf(
      result["library"],
    ).map(MediaItem.fromJson).toList();
    final recent = listOf(
      result["recent"],
    ).map(SearchHistoryEntry.fromJson).toList();
    setState(() {
      _animeResults = anime;
      _discoverLibraryMatches = library;
      _discoverHistory = recent;
      _status = "库内 ${library.length} 个 · 番剧 ${anime.length} 个";
    });
  }

  Future<void> _subscribeAnime(AnimeSearchResult result) async {
    await _api.subscribeAnime(
      title: result.title,
      provider: result.provider,
      rssUrl: result.rssUrl,
      posterUrl: result.posterUrl,
      autoBangumi: result.raw,
    );
    await Future.wait([
      _loadAnimeTracking(),
      _loadDiscoverHistory(),
      _loadDownloads(),
      _loadHome(),
    ]);
    setState(() => _status = "已订阅 ${result.title}");
  }

  Future<void> _loadDiscoverHistory() async {
    final result = await _api.discoverRecent();
    setState(
      () => _discoverHistory = listOf(
        result["items"],
      ).map(SearchHistoryEntry.fromJson).toList(),
    );
  }

  Future<void> _loadAnimeTracking() async {
    final responses = await Future.wait([
      _api.animeSubscriptions(),
      _api.animeRules(),
    ]);
    final subscriptionResult = responses[0];
    final rulesResult = responses[1];
    setState(() {
      _animeSubscriptions = listOf(
        subscriptionResult["items"],
      ).map(AnimeSubscription.fromJson).toList();
      _animeRules =
          listOf(rulesResult["items"]).map(AnimeRule.fromJson).toList();
      _animeRulesConfigured = boolValue(rulesResult["configured"]);
    });
  }

  Future<void> _loadDownloads({bool autoImport = true}) async {
    final result = await _api.downloads();
    final downloads = listOf(
      result["items"],
    ).map(DownloadTask.fromJson).toList();
    _pruneAutoImportAttempts(downloads);
    setState(() => _downloads = downloads);
    if (autoImport) {
      await _autoImportCompletedDownloadsIfNeeded(downloads);
    }
  }

  void _pruneAutoImportAttempts(List<DownloadTask> downloads) {
    final completedIds = downloads
        .where((task) => task.state == "completed")
        .map((task) => task.id)
        .toSet();
    _autoImportLastAttemptByDownloadId.removeWhere(
      (id, _) => !completedIds.contains(id),
    );
  }

  Future<void> _autoImportCompletedDownloadsIfNeeded(
    List<DownloadTask> downloads,
  ) async {
    if (_autoImportingCompletedDownloads || _api.token == null) return;

    final now = DateTime.now();
    final dueIds = completedDownloadIdsDueForAutoImport(
      downloads: downloads,
      lastAttemptById: _autoImportLastAttemptByDownloadId,
      now: now,
      retryDelay: _autoImportRetryDelay,
    );
    if (dueIds.isEmpty) return;

    for (final id in dueIds) {
      _autoImportLastAttemptByDownloadId[id] = now;
    }

    _autoImportingCompletedDownloads = true;
    try {
      final result = await _api.importCompletedDownloads();
      final imported = intValue(result["imported"]);
      final pending = intValue(result["pending"]);
      final failed = intValue(result["failed"]);
      final synced = intValue(result["synced"]);
      final importedItems =
          listOf(result["items"]).map(MediaItem.fromJson).toList();
      await Future.wait([
        _loadDownloads(autoImport: false),
        _loadLibrary(),
        _loadHome(),
      ]);
      if (!mounted) return;
      if (imported > 0 || pending > 0 || failed > 0 || synced > 0) {
        setState(() {
          if (importedItems.isNotEmpty && _selectedMedia == null) {
            _selectedMedia = importedItems.first;
          }
          _status = "自动入库：已入库 $imported，等待扫描 $pending，失败 $failed，同步 $synced 条";
        });
      }
    } catch (_) {
      for (final id in dueIds) {
        _autoImportLastAttemptByDownloadId.remove(id);
      }
    } finally {
      _autoImportingCompletedDownloads = false;
    }
  }

  Future<void> _controlDownload(DownloadTask task, String action) async {
    await _api.controlDownload(task.id, action);
    await Future.wait([_loadDownloads(), _loadHome()]);
    setState(
      () => _status = action == "pause"
          ? "已暂停 ${task.episodeTitle}"
          : "已恢复 ${task.episodeTitle}",
    );
  }

  Future<void> _completeDownload(DownloadTask task) async {
    final result = await _api.completeDownload(task.id);
    final mediaItems =
        listOf(result["mediaItems"]).map(MediaItem.fromJson).toList();
    await Future.wait([_loadDownloads(), _loadLibrary(), _loadHome()]);
    if (!mounted) return;
    setState(() {
      if (mediaItems.isNotEmpty) {
        _selectedMedia = mediaItems.first;
        _tab = 2;
        _status = "已完成并入库：${mediaItems.first.title}";
      } else {
        _status = "已完成模拟下载：${task.episodeTitle}";
      }
    });
  }

  Future<void> _importDownload(DownloadTask task) async {
    _autoImportLastAttemptByDownloadId[task.id] = DateTime.now();
    final result = await _api.importDownload(task.id);
    final synced = intValue(result["synced"]);
    final importStatus = stringValue(result["status"]);
    final message = stringValue(result["message"]);
    final searchTerms = listOfStrings(result["searchTerms"]);
    final importedItems =
        listOf(result["items"]).map(MediaItem.fromJson).toList();
    await Future.wait([
      _loadDownloads(autoImport: false),
      _loadLibrary(),
      _loadHome(),
    ]);
    if (!mounted) return;
    setState(() {
      if (importedItems.isNotEmpty) {
        _selectedMedia = importedItems.first;
        _tab = 2;
        _status = "已入库：${importedItems.first.title}";
      } else if (importStatus == "pending-scan") {
        final terms = searchTerms.take(3).join(" / ");
        _status = "已触发 Jellyfin 扫描，暂未匹配；稍后重试。候选：$terms";
      } else if (message.isNotEmpty) {
        _status = message;
      } else {
        _status = "已触发入库：${task.episodeTitle}，匹配 $synced 条";
      }
    });
  }

  Future<void> _importCompletedDownloads() async {
    final now = DateTime.now();
    for (final task in _downloads.where((task) => task.state == "completed")) {
      _autoImportLastAttemptByDownloadId[task.id] = now;
    }
    final result = await _api.importCompletedDownloads();
    final imported = intValue(result["imported"]);
    final pending = intValue(result["pending"]);
    final failed = intValue(result["failed"]);
    final synced = intValue(result["synced"]);
    final importedItems =
        listOf(result["items"]).map(MediaItem.fromJson).toList();
    await Future.wait([
      _loadDownloads(autoImport: false),
      _loadLibrary(),
      _loadHome(),
    ]);
    if (!mounted) return;
    setState(() {
      if (importedItems.isNotEmpty) {
        _selectedMedia = importedItems.first;
      }
      _status = "批量入库完成：已入库 $imported，等待扫描 $pending，失败 $failed，同步 $synced 条";
      if (importedItems.isNotEmpty) {
        _tab = 2;
      }
    });
  }

  Future<void> _runDownloadImportAutomation() async {
    final result = await _api.runDownloadImportAutomation();
    final attempted = intValue(result["attempted"]);
    final imported = intValue(result["imported"]);
    final pending = intValue(result["pending"]);
    final failed = intValue(result["failed"]);
    final skipped = intValue(result["skipped"]);
    final synced = intValue(result["synced"]);
    await Future.wait([
      _loadDownloads(autoImport: false),
      _loadLibrary(),
      _loadHome(),
    ]);
    if (!mounted) return;
    setState(() {
      _status =
          "后台入库执行：尝试 $attempted，已入库 $imported，等待 $pending，失败 $failed，跳过 $skipped，同步 $synced 条";
    });
  }

  Future<void> _loadLibrary() async {
    final result = await _api.libraryItems();
    setState(
      () => _library = listOf(result["items"]).map(MediaItem.fromJson).toList(),
    );
  }

  Future<void> _searchLibrary() async {
    final query = _librarySearchController.text.trim();
    if (query.isEmpty) {
      await _loadLibrary();
      return;
    }

    final result = await _api.librarySearch(query);
    setState(
      () => _library = listOf(result["items"]).map(MediaItem.fromJson).toList(),
    );
  }

  Future<void> _loadMediaDetail(String itemId) async {
    final result = await _api.mediaDetail(itemId);
    setState(() => _selectedMedia = MediaItem.fromJson(asMap(result["item"])));
  }

  Future<void> _setWatched(MediaItem media, bool watched) async {
    final result = await _api.setWatched(media.id, watched);
    setState(() => _selectedMedia = MediaItem.fromJson(asMap(result["item"])));
    await Future.wait([_loadLibrary(), _loadHome()]);
  }

  Future<void> _setFavorite(MediaItem media, bool favorite) async {
    final result = await _api.setFavorite(media.id, favorite);
    setState(() => _selectedMedia = MediaItem.fromJson(asMap(result["item"])));
    await _loadLibrary();
  }

  Future<void> _playItem(String itemId) async {
    final result = await _api.startPlayback(itemId);
    final session = PlaybackSession.fromJson(asMap(result["session"]));
    setState(() {
      _session = session;
      _status = "已创建播放会话";
    });
    _beginExternalPlaybackTracking(session);
    final launch = await PlaybackLauncher.launch(session);
    if (!mounted) return;
    if (!launch.launched) {
      _clearExternalPlaybackTracking();
    }
    setState(() => _status = launch.message);
    await Future.wait([_loadHistory(), _loadHome(), _loadLibrary()]);
  }

  void _beginExternalPlaybackTracking(PlaybackSession session) {
    if (!session.shouldTrackExternalReturn) return;
    _externalPlaybackLeftAt = DateTime.now();
    _externalPlaybackWasBackgrounded = false;
  }

  void _clearExternalPlaybackTracking() {
    _externalPlaybackLeftAt = null;
    _externalPlaybackWasBackgrounded = false;
  }

  Future<void> _finalizeExternalPlaybackReturn() async {
    final session = _session;
    final leftAt = _externalPlaybackLeftAt;
    if (_finalizingExternalPlayback ||
        session == null ||
        leftAt == null ||
        !session.shouldTrackExternalReturn) {
      return;
    }

    _finalizingExternalPlayback = true;
    try {
      final position = estimateExternalPlaybackReturnPosition(
        session: session,
        elapsed: DateTime.now().difference(leftAt),
      );
      final result = await _api.stopPlayback(
        session.id,
        positionSeconds: position,
      );
      if (!mounted) return;
      setState(() {
        _session = PlaybackSession.fromJson(asMap(result["session"]));
        _status = "外部播放器返回，已同步到 ${formatDuration(position)}";
      });
      final selectedMedia = _selectedMedia;
      await Future.wait([
        _loadHistory(),
        _loadHome(),
        _loadLibrary(),
        if (selectedMedia != null) _loadMediaDetail(selectedMedia.id),
      ]);
    } catch (error) {
      if (mounted) {
        setState(() => _status = "外部播放器返回，进度同步失败：$error");
      }
    } finally {
      _clearExternalPlaybackTracking();
      _finalizingExternalPlayback = false;
    }
  }

  Future<void> _heartbeat(double ratio) async {
    final session = _session;
    if (session == null) return;
    if (ratio >= 0.9) {
      await _stopPlayback(ratio: ratio);
      return;
    }

    final position = (session.durationSeconds * ratio).round();
    final result = await _api.playbackHeartbeat(
      session.id,
      positionSeconds: position,
      state: ratio >= 0.9 ? "paused" : "playing",
    );
    setState(
      () => _session = PlaybackSession.fromJson(asMap(result["session"])),
    );
    final selectedMedia = _selectedMedia;
    await Future.wait([
      _loadHistory(),
      _loadHome(),
      _loadLibrary(),
      if (selectedMedia != null) _loadMediaDetail(selectedMedia.id),
    ]);
  }

  Future<void> _stopPlayback({double? ratio}) async {
    final session = _session;
    if (session == null) return;

    final position = ratio == null
        ? session.positionSeconds
        : (session.durationSeconds * ratio).round();
    final result = await _api.stopPlayback(
      session.id,
      positionSeconds: position,
    );
    setState(
      () => _session = PlaybackSession.fromJson(asMap(result["session"])),
    );
    final selectedMedia = _selectedMedia;
    await Future.wait([
      _loadHistory(),
      _loadHome(),
      _loadLibrary(),
      if (selectedMedia != null) _loadMediaDetail(selectedMedia.id),
    ]);
  }

  Future<void> _loadHistory() async {
    final result = await _api.history();
    setState(
      () => _history = listOf(
        result["items"],
      ).map(HistoryEntry.fromJson).toList(),
    );
  }
}

class CluoApi {
  CluoApi(String baseUrl) : baseUrl = normalizeBaseUrl(baseUrl);

  String baseUrl;
  String? token;

  Future<Map<String, dynamic>> health() => get("/api/health");

  Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    String? displayName,
  }) =>
      post("/api/auth/register", {
        "username": username,
        "password": password,
        if (displayName != null) "displayName": displayName,
      });

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) =>
      post("/api/auth/login", {
        "username": username,
        "password": password,
      });

  Future<Map<String, dynamic>> home() => get("/api/home");

  Future<Map<String, dynamic>> serviceSettings() =>
      get("/api/settings/services");

  Future<Map<String, dynamic>> systemStatus() => get("/api/system/status");

  Future<Map<String, dynamic>> saveServiceSettings(
    Map<String, Object?> body,
  ) =>
      patch("/api/settings/services", body);

  Future<Map<String, dynamic>> loginJellyfin({
    required String baseUrl,
    required String username,
    required String password,
    required String deviceId,
  }) =>
      post("/api/settings/jellyfin/login", {
        "baseUrl": baseUrl,
        "username": username,
        "password": password,
        "deviceId": deviceId,
      });

  Future<Map<String, dynamic>> discoverSearch(
    String query, {
    int limit = 12,
  }) =>
      get(
        "/api/discover/search?q=${Uri.encodeQueryComponent(query)}&limit=$limit",
      );

  Future<Map<String, dynamic>> discoverRecent() => get("/api/discover/recent");

  Future<Map<String, dynamic>> animeSubscriptions() =>
      get("/api/anime/subscriptions");

  Future<Map<String, dynamic>> animeRules() => get("/api/anime/rules");

  Future<Map<String, dynamic>> subscribeAnime({
    required String title,
    String? provider,
    String? rssUrl,
    String? posterUrl,
    Object? autoBangumi,
  }) =>
      post("/api/anime/subscribe", {
        "title": title,
        if (provider != null) "provider": provider,
        if (rssUrl != null) "rssUrl": rssUrl,
        if (posterUrl != null) "posterUrl": posterUrl,
        if (autoBangumi != null) "autoBangumi": autoBangumi,
      });

  Future<Map<String, dynamic>> downloads() => get("/api/downloads");

  Future<Map<String, dynamic>> controlDownload(
    String id,
    String action,
  ) {
    if (action != "pause" && action != "resume") {
      throw ArgumentError.value(action, "action", "Expected pause or resume");
    }
    return post("/api/downloads/${Uri.encodeComponent(id)}/$action", null);
  }

  Future<Map<String, dynamic>> completeDownload(String id) => post(
        "/api/anime/downloads/${Uri.encodeComponent(id)}/complete",
        null,
      );

  Future<Map<String, dynamic>> importDownload(String id) => post(
        "/api/downloads/${Uri.encodeComponent(id)}/import",
        null,
      );

  Future<Map<String, dynamic>> importCompletedDownloads() =>
      post("/api/downloads/import-completed", null);

  Future<Map<String, dynamic>> runDownloadImportAutomation() =>
      post("/api/automation/download-import/run", null);

  Future<Map<String, dynamic>> libraryItems({int limit = 100}) =>
      get("/api/library/items?limit=$limit");

  Future<Map<String, dynamic>> librarySearch(String query) => get(
        "/api/library/search?q=${Uri.encodeQueryComponent(query)}",
      );

  Future<Map<String, dynamic>> mediaDetail(String itemId) => get(
        "/api/library/items/${Uri.encodeComponent(itemId)}",
      );

  Future<Map<String, dynamic>> setWatched(String itemId, bool watched) => post(
        "/api/library/items/${Uri.encodeComponent(itemId)}/watched",
        {"watched": watched},
      );

  Future<Map<String, dynamic>> setFavorite(String itemId, bool favorite) =>
      post(
        "/api/library/items/${Uri.encodeComponent(itemId)}/favorite",
        {"favorite": favorite},
      );

  Future<Map<String, dynamic>> startPlayback(String itemId) => post(
        "/api/playback/sessions",
        {"itemId": itemId},
      );

  Future<Map<String, dynamic>> playbackHeartbeat(
    String sessionId, {
    required int positionSeconds,
    String state = "playing",
  }) =>
      patch(
        "/api/playback/sessions/${Uri.encodeComponent(sessionId)}",
        {
          "positionSeconds": positionSeconds,
          "state": state,
        },
      );

  Future<Map<String, dynamic>> stopPlayback(
    String sessionId, {
    required int positionSeconds,
  }) =>
      post(
        "/api/playback/sessions/${Uri.encodeComponent(sessionId)}/stop",
        {"positionSeconds": positionSeconds},
      );

  Future<Map<String, dynamic>> history() => get("/api/history");

  Future<Map<String, dynamic>> get(String path) => _request("GET", path);

  Future<Map<String, dynamic>> post(String path, Object? body) =>
      _request("POST", path, body: body);

  Future<Map<String, dynamic>> patch(String path, Object? body) =>
      _request("PATCH", path, body: body);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Object? body,
  }) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse("$baseUrl$path");
      final request = await client.openUrl(method, uri);
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      if (body != null) {
        request.headers.contentType = ContentType.json;
      }
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, "Bearer $token");
      }
      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
      final data = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : {"data": decoded};

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data["error"] ?? "HTTP ${response.statusCode}");
      }

      return data;
    } finally {
      client.close(force: true);
    }
  }
}

class SystemStatus {
  SystemStatus({
    required this.checkedAt,
    required this.overall,
    required this.items,
  });

  factory SystemStatus.fromJson(Map<String, dynamic> json) {
    return SystemStatus(
      checkedAt: stringValue(json["checkedAt"]),
      overall: stringValue(json["overall"]),
      items: listOf(json["items"]).map(ServiceHealth.fromJson).toList(),
    );
  }

  final String checkedAt;
  final String overall;
  final List<ServiceHealth> items;
}

class ServiceHealth {
  ServiceHealth({
    required this.id,
    required this.label,
    required this.state,
    required this.configured,
    required this.reachable,
    required this.message,
    this.baseUrl,
  });

  factory ServiceHealth.fromJson(Map<String, dynamic> json) {
    return ServiceHealth(
      id: stringValue(json["id"]),
      label: stringValue(json["label"]),
      state: stringValue(json["state"]),
      configured: boolValue(json["configured"]),
      reachable: boolValue(json["reachable"]),
      message: stringValue(json["message"]),
      baseUrl: nullableString(json["baseUrl"]),
    );
  }

  final String id;
  final String label;
  final String state;
  final bool configured;
  final bool reachable;
  final String message;
  final String? baseUrl;
}

class HomeData {
  HomeData({
    required this.continueWatching,
    required this.recentlyAdded,
    required this.activeDownloads,
  });

  factory HomeData.fromJson(Map<String, dynamic> json) {
    return HomeData(
      continueWatching: listOf(
        json["continueWatching"],
      ).map(ContinueItem.fromJson).toList(),
      recentlyAdded: listOf(
        json["recentlyAdded"],
      ).map(MediaItem.fromJson).toList(),
      activeDownloads: listOf(
        json["activeDownloads"],
      ).map(DownloadTask.fromJson).toList(),
    );
  }

  final List<ContinueItem> continueWatching;
  final List<MediaItem> recentlyAdded;
  final List<DownloadTask> activeDownloads;
}

class ContinueItem {
  ContinueItem({
    required this.itemId,
    required this.title,
    required this.progress,
    required this.source,
    this.posterUrl,
  });

  factory ContinueItem.fromJson(Map<String, dynamic> json) {
    return ContinueItem(
      itemId: stringValue(json["itemId"]),
      title: stringValue(json["title"]),
      progress: doubleValue(json["progress"]),
      source: stringValue(json["source"], fallback: "local"),
      posterUrl: nullableString(json["posterUrl"]),
    );
  }

  final String itemId;
  final String title;
  final double progress;
  final String source;
  final String? posterUrl;
}

class SearchHistoryEntry {
  SearchHistoryEntry({
    required this.query,
    required this.searchCount,
    required this.libraryCount,
    required this.animeCount,
    required this.lastSearchedAt,
  });

  factory SearchHistoryEntry.fromJson(Map<String, dynamic> json) {
    final counts = asMap(json["resultCounts"]);
    return SearchHistoryEntry(
      query: stringValue(json["query"]),
      searchCount: intValue(json["searchCount"]),
      libraryCount: intValue(counts["library"]),
      animeCount: intValue(counts["anime"]),
      lastSearchedAt: stringValue(json["lastSearchedAt"]),
    );
  }

  final String query;
  final int searchCount;
  final int libraryCount;
  final int animeCount;
  final String lastSearchedAt;
}

class AnimeSearchResult {
  AnimeSearchResult({
    required this.title,
    required this.provider,
    required this.confidence,
    this.description,
    this.rssUrl,
    this.posterUrl,
    this.raw,
  });

  factory AnimeSearchResult.fromJson(Map<String, dynamic> json) {
    return AnimeSearchResult(
      title: stringValue(json["title"]),
      provider: stringValue(json["provider"]),
      confidence: doubleValue(json["confidence"]),
      description: nullableString(json["description"]),
      rssUrl: nullableString(json["rssUrl"]),
      posterUrl: nullableString(json["posterUrl"]),
      raw: json["raw"],
    );
  }

  final String title;
  final String provider;
  final double confidence;
  final String? description;
  final String? rssUrl;
  final String? posterUrl;
  final Object? raw;
}

class AnimeSubscription {
  AnimeSubscription({
    required this.id,
    required this.title,
    required this.provider,
    required this.status,
    required this.createdAt,
    this.rssUrl,
    this.posterUrl,
  });

  factory AnimeSubscription.fromJson(Map<String, dynamic> json) {
    return AnimeSubscription(
      id: stringValue(json["id"]),
      title: stringValue(json["title"]),
      provider: stringValue(json["provider"], fallback: "local-dev"),
      status: stringValue(json["status"], fallback: "active"),
      createdAt: stringValue(json["createdAt"]),
      rssUrl: nullableString(json["rssUrl"]),
      posterUrl: nullableString(json["posterUrl"]),
    );
  }

  final String id;
  final String title;
  final String provider;
  final String status;
  final String createdAt;
  final String? rssUrl;
  final String? posterUrl;
}

class AnimeRule {
  AnimeRule({
    required this.id,
    required this.title,
    required this.provider,
    required this.status,
    required this.rssUrls,
    required this.needsReview,
    this.posterUrl,
  });

  factory AnimeRule.fromJson(Map<String, dynamic> json) {
    return AnimeRule(
      id: stringValue(json["id"]),
      title: stringValue(json["title"]),
      provider: stringValue(json["provider"], fallback: "local-dev"),
      status: stringValue(json["status"], fallback: "active"),
      rssUrls: listOfStrings(json["rssUrls"]),
      needsReview: boolValue(json["needsReview"]),
      posterUrl: nullableString(json["posterUrl"]),
    );
  }

  final String id;
  final String title;
  final String provider;
  final String status;
  final List<String> rssUrls;
  final bool needsReview;
  final String? posterUrl;
}

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.title,
    required this.episodeTitle,
    required this.source,
    required this.state,
    required this.progress,
    required this.speedBytesPerSecond,
    this.etaSeconds,
    this.error,
  });

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: stringValue(json["id"]),
      title: stringValue(json["title"]),
      episodeTitle: stringValue(json["episodeTitle"]),
      source: stringValue(json["source"]),
      state: stringValue(json["state"]),
      progress: doubleValue(json["progress"]),
      speedBytesPerSecond: intValue(json["speedBytesPerSecond"]),
      etaSeconds: nullableInt(json["etaSeconds"]),
      error: nullableString(json["error"]),
    );
  }

  final String id;
  final String title;
  final String episodeTitle;
  final String source;
  final String state;
  final double progress;
  final int speedBytesPerSecond;
  final int? etaSeconds;
  final String? error;

  bool get canCompleteLocally {
    return source == "local-dev" && state != "completed" && state != "failed";
  }

  bool get canPause {
    return state == "downloading" &&
        (source == "local-dev" ||
            source == "qbittorrent" ||
            source == "autobangumi");
  }

  bool get canResume {
    return state == "paused" &&
        (source == "local-dev" ||
            source == "qbittorrent" ||
            source == "autobangumi");
  }

  String get stateLabel {
    return switch (state) {
      "queued" => "等待队列",
      "downloading" => "下载中",
      "paused" => "已暂停",
      "completed" => "已完成",
      "failed" => "失败",
      _ => state,
    };
  }
}

List<String> completedDownloadIdsDueForAutoImport({
  required List<DownloadTask> downloads,
  required Map<String, DateTime> lastAttemptById,
  required DateTime now,
  required Duration retryDelay,
}) {
  final ids = <String>[];
  final seen = <String>{};
  for (final task in downloads) {
    if (task.state != "completed" || !seen.add(task.id)) continue;
    final lastAttempt = lastAttemptById[task.id];
    if (lastAttempt == null || now.difference(lastAttempt) >= retryDelay) {
      ids.add(task.id);
    }
  }
  return ids;
}

class MediaItem {
  MediaItem({
    required this.id,
    required this.title,
    required this.source,
    required this.durationSeconds,
    required this.watched,
    required this.favorite,
    this.posterUrl,
    this.overview,
    this.year,
    this.communityRating,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: stringValue(json["id"]),
      title: stringValue(json["title"]),
      source: stringValue(json["source"]),
      durationSeconds: intValue(json["durationSeconds"]),
      watched: boolValue(json["watched"]),
      favorite: boolValue(json["favorite"]),
      posterUrl: nullableString(json["posterUrl"]),
      overview: nullableString(json["overview"]),
      year: nullableInt(json["year"]),
      communityRating: nullableDouble(json["communityRating"]),
    );
  }

  final String id;
  final String title;
  final String source;
  final int durationSeconds;
  final bool watched;
  final bool favorite;
  final String? posterUrl;
  final String? overview;
  final int? year;
  final double? communityRating;
}

class PlaybackSession {
  PlaybackSession({
    required this.id,
    required this.provider,
    required this.mode,
    required this.state,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.progress,
    this.url,
    this.intentUri,
  });

  factory PlaybackSession.fromJson(Map<String, dynamic> json) {
    final intent = asMap(json["intent"]);
    return PlaybackSession(
      id: stringValue(json["id"]),
      provider: stringValue(json["provider"]),
      mode: stringValue(json["mode"]),
      state: stringValue(json["state"]),
      positionSeconds: intValue(json["positionSeconds"]),
      durationSeconds: intValue(json["durationSeconds"]),
      progress: doubleValue(json["progress"]),
      url: nullableString(json["url"]),
      intentUri: nullableString(intent["uri"]),
    );
  }

  final String id;
  final String provider;
  final String mode;
  final String state;
  final int positionSeconds;
  final int durationSeconds;
  final double progress;
  final String? url;
  final String? intentUri;

  bool get shouldTrackExternalReturn {
    if (state != "playing") return false;
    if (provider == "local-dev") return false;
    return mode == "intent" || mode == "stream-url";
  }
}

int estimateExternalPlaybackReturnPosition({
  required PlaybackSession session,
  required Duration elapsed,
}) {
  final estimate = session.positionSeconds + elapsed.inSeconds;
  final duration = session.durationSeconds;
  if (duration <= 0) return estimate < 0 ? 0 : estimate;
  if (estimate < 0) return 0;
  if (estimate > duration) return duration;
  return estimate;
}

class PlaybackLaunchResult {
  const PlaybackLaunchResult({required this.launched, required this.message});

  factory PlaybackLaunchResult.fromPlatform(Object? value) {
    if (value is Map) {
      final data = Map<String, dynamic>.from(value);
      return PlaybackLaunchResult(
        launched: boolValue(data["launched"]),
        message: stringValue(data["message"], fallback: "已尝试启动播放器"),
      );
    }
    return const PlaybackLaunchResult(launched: false, message: "平台启动返回无效");
  }

  final bool launched;
  final String message;
}

class PlaybackHandlerDiagnostics {
  const PlaybackHandlerDiagnostics({
    required this.platform,
    required this.packageName,
    required this.packageInstalled,
    required this.canHandleUrl,
    required this.canHandleIntentUri,
    required this.urlHandlerCount,
    required this.intentHandlerCount,
    this.message,
  });

  factory PlaybackHandlerDiagnostics.fromPlatform(Object? value) {
    if (value is Map) {
      final data = Map<String, dynamic>.from(value);
      return PlaybackHandlerDiagnostics(
        platform: stringValue(data["platform"], fallback: "unknown"),
        packageName: nullIfBlank(stringValue(data["packageName"])),
        packageInstalled: boolValue(data["packageInstalled"]),
        canHandleUrl: boolValue(data["canHandleUrl"]),
        canHandleIntentUri: boolValue(data["canHandleIntentUri"]),
        urlHandlerCount: intValue(data["urlHandlerCount"]),
        intentHandlerCount: intValue(data["intentHandlerCount"]),
        message: nullIfBlank(stringValue(data["message"])),
      );
    }
    return const PlaybackHandlerDiagnostics(
      platform: "unknown",
      packageName: null,
      packageInstalled: false,
      canHandleUrl: false,
      canHandleIntentUri: false,
      urlHandlerCount: 0,
      intentHandlerCount: 0,
      message: "平台检测返回无效",
    );
  }

  factory PlaybackHandlerDiagnostics.missingPlugin({
    String? packageName,
  }) {
    return PlaybackHandlerDiagnostics(
      platform: "unsupported",
      packageName: packageName,
      packageInstalled: false,
      canHandleUrl: false,
      canHandleIntentUri: false,
      urlHandlerCount: 0,
      intentHandlerCount: 0,
      message: "当前平台尚未接入 Android 播放器检测桥接",
    );
  }

  final String platform;
  final String? packageName;
  final bool packageInstalled;
  final bool canHandleUrl;
  final bool canHandleIntentUri;
  final int urlHandlerCount;
  final int intentHandlerCount;
  final String? message;

  String get summary {
    if (message != null && platform == "unsupported") return message!;
    if (packageName != null && !packageInstalled) {
      return "未检测到播放器包：$packageName";
    }
    if (canHandleIntentUri || canHandleUrl) {
      return "播放器检测通过";
    }
    return "未检测到可处理当前播放目标的播放器";
  }
}

class PlaybackLauncher {
  static const _channel = MethodChannel("cluo_vision/playback");
  static const _probeUrl = "http://127.0.0.1:8096/Videos/cluo-probe/stream.mkv";

  static Future<PlaybackLaunchResult> launch(PlaybackSession session) async {
    final intentUri = session.intentUri;
    if (session.mode == "intent" && intentUri != null) {
      return _invoke("launchIntentUri", {"uri": intentUri});
    }

    final url = session.url;
    if (url != null &&
        (session.mode == "stream-url" || session.mode == "mock-stream")) {
      return _invoke("launchUrl", {"url": url, "mimeType": "video/*"});
    }

    return const PlaybackLaunchResult(
      launched: false,
      message: "已创建播放会话；当前 provider 没有可启动目标",
    );
  }

  static Future<PlaybackHandlerDiagnostics> checkHandlers({
    String? packageName,
    String mimeType = "video/*",
    String? sampleUrl,
    String? sampleIntentUri,
  }) async {
    final url = sampleUrl ?? _probeUrl;
    final intentUri = sampleIntentUri ??
        buildAndroidViewIntentUri(url, mimeType, packageName);
    try {
      final result = await _channel.invokeMethod<Object?>(
        "checkPlaybackHandlers",
        {
          "packageName": packageName,
          "mimeType": mimeType,
          "url": url,
          "intentUri": intentUri,
        },
      );
      return PlaybackHandlerDiagnostics.fromPlatform(result);
    } on MissingPluginException {
      return PlaybackHandlerDiagnostics.missingPlugin(packageName: packageName);
    } on PlatformException catch (error) {
      return PlaybackHandlerDiagnostics(
        platform: "android",
        packageName: packageName,
        packageInstalled: false,
        canHandleUrl: false,
        canHandleIntentUri: false,
        urlHandlerCount: 0,
        intentHandlerCount: 0,
        message: "播放器检测失败：${error.message ?? error.code}",
      );
    }
  }

  static Future<PlaybackLaunchResult> _invoke(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final result = await _channel.invokeMethod<Object?>(method, arguments);
      return PlaybackLaunchResult.fromPlatform(result);
    } on MissingPluginException {
      return const PlaybackLaunchResult(
        launched: false,
        message: "已创建播放会话；当前平台尚未接入播放器启动桥接",
      );
    } on PlatformException catch (error) {
      return PlaybackLaunchResult(
        launched: false,
        message: "播放器启动失败：${error.message ?? error.code}",
      );
    }
  }
}

String buildAndroidViewIntentUri(
  String data,
  String mimeType,
  String? packageName,
) {
  final uri = Uri.parse(data);
  final pathAndQuery =
      "${uri.authority}${uri.path}${uri.hasQuery ? "?${uri.query}" : ""}";
  final parts = [
    "intent://$pathAndQuery#Intent",
    "scheme=${Uri.encodeComponent(uri.scheme)}",
    "action=android.intent.action.VIEW",
    "type=${Uri.encodeComponent(mimeType)}",
    if (packageName != null && packageName.trim().isNotEmpty)
      "package=${Uri.encodeComponent(packageName.trim())}",
    "end",
  ];
  return parts.join(";");
}

class HistoryEntry {
  HistoryEntry({
    required this.itemId,
    required this.title,
    required this.progress,
    required this.lastWatchedAt,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      itemId: stringValue(json["itemId"]),
      title: stringValue(json["title"]),
      progress: doubleValue(json["progress"]),
      lastWatchedAt: stringValue(json["lastWatchedAt"]),
    );
  }

  final String itemId;
  final String title;
  final double progress;
  final String lastWatchedAt;
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.selected,
    required this.signedIn,
    required this.onSelected,
  });

  final int selected;
  final bool signedIn;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = ["首页", "找片", "媒体库", "下载", "历史", "设置"];
    return Container(
      width: 220,
      color: const Color(0xff0b0f10),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Cluo",
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
          ),
          const Text(
            "Vision",
            style: TextStyle(fontSize: 20, color: Color(0xff9fb3b7)),
          ),
          const SizedBox(height: 36),
          for (var i = 0; i < items.length; i++) ...[
            _NavButton(
              label: items[i],
              selected: selected == i,
              enabled: signedIn || i == 0 || i == 5,
              autofocus: selected == i && (signedIn || i == 0 || i == 5),
              onPressed: () => onSelected(i),
            ),
            const SizedBox(height: 10),
          ],
          const Spacer(),
          Text(
            signedIn ? "已登录" : "未登录",
            style: const TextStyle(color: Color(0xff9fb3b7)),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.status,
    required this.displayName,
    required this.onRefresh,
  });

  final String title;
  final String status;
  final String displayName;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 4),
              Text(
                [
                  displayName.isEmpty ? null : displayName,
                  status,
                ].whereType<String>().join(" · "),
                style: const TextStyle(color: Color(0xffb6c2c6)),
              ),
            ],
          ),
        ),
        _SecondaryAction(label: "刷新", onPressed: onRefresh),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.autofocus,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final bool autofocus;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: enabled ? onPressed : null,
      autofocus: autofocus,
      style: FilledButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size.fromHeight(54),
        foregroundColor: selected ? Colors.black : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return const Color(0xff111719);
          }
          if (states.contains(WidgetState.focused)) {
            return selected ? const Color(0xff4ff7e4) : const Color(0xff25383d);
          }
          return selected ? const Color(0xff1fb6a6) : const Color(0xff172023);
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return const BorderSide(color: Colors.white, width: 3);
          }
          return BorderSide.none;
        }),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xff172023),
        border: Border.all(color: const Color(0xff263235)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 12),
          Text(trailing, style: const TextStyle(color: Color(0xff9fb3b7))),
        ],
      ),
    );
  }
}

class _SearchHistoryBar extends StatelessWidget {
  const _SearchHistoryBar({
    required this.items,
    required this.onSelected,
  });

  final List<SearchHistoryEntry> items;
  final ValueChanged<SearchHistoryEntry> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final item in items.take(8))
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: OutlinedButton.icon(
              onPressed: () => onSelected(item),
              icon: const Icon(Icons.history, size: 20),
              label: Text(
                item.query,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ).copyWith(
                side: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.focused)) {
                    return const BorderSide(color: Colors.white, width: 3);
                  }
                  return const BorderSide(color: Color(0xff4a5b60));
                }),
              ),
            ),
          ),
      ],
    );
  }
}

class _HorizontalRail extends StatelessWidget {
  const _HorizontalRail({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox(height: 132, child: Center(child: Text("暂无数据")));
    }

    return SizedBox(
      height: 164,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) =>
            SizedBox(width: 280, child: children[index]),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.subtitle,
    this.body,
    this.posterUrl,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? body;
  final String? posterUrl;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: _PosterArt(url: posterUrl, title: title),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xff9fb3b7)),
                ),
                if (body != null) ...[
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(
                      body!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else
                  const Spacer(),
                if (actionLabel != null && onAction != null)
                  _PrimaryAction(label: actionLabel!, onPressed: onAction!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimeTrackingPanel extends StatelessWidget {
  const _AnimeTrackingPanel({
    required this.subscriptions,
    required this.rules,
    required this.rulesConfigured,
    required this.onRefresh,
  });

  final List<AnimeSubscription> subscriptions;
  final List<AnimeRule> rules;
  final bool rulesConfigured;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final reviewCount = rules.where((item) => item.needsReview).length;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "订阅状态",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              _SecondaryAction(label: "刷新", onPressed: onRefresh),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 190,
                child: _MetricTile(
                  label: "本地订阅",
                  value: "${subscriptions.length}",
                  subtitle: subscriptions.isEmpty ? "暂无" : "已记录",
                ),
              ),
              SizedBox(
                width: 190,
                child: _MetricTile(
                  label: rulesConfigured ? "AutoBangumi 规则" : "本地规则",
                  value: "${rules.length}",
                  subtitle: reviewCount > 0 ? "$reviewCount 条需确认" : "正常",
                ),
              ),
              for (final item in subscriptions.take(3))
                SizedBox(
                  width: 260,
                  child: _AnimeTrackingTile(
                    title: item.title,
                    subtitle: "${item.provider} · ${item.status}",
                    posterUrl: item.posterUrl,
                  ),
                ),
              for (final item in rules.take(3))
                SizedBox(
                  width: 260,
                  child: _AnimeTrackingTile(
                    title: item.title,
                    subtitle:
                        "${item.provider} · ${item.status}${item.needsReview ? " · 需确认" : ""}",
                    posterUrl: item.posterUrl,
                  ),
                ),
              if (subscriptions.isEmpty && rules.isEmpty)
                const Text(
                  "暂无订阅。搜索番剧后点击订阅，会在这里显示本地订阅和 AutoBangumi 规则状态。",
                  style: TextStyle(color: Color(0xff9fb3b7)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.subtitle,
  });

  final String label;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xff101719),
        border: Border.all(color: const Color(0xff263235)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xff9fb3b7))),
          const SizedBox(height: 6),
          Text(value,
              style:
                  const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _AnimeTrackingTile extends StatelessWidget {
  const _AnimeTrackingTile({
    required this.title,
    required this.subtitle,
    this.posterUrl,
  });

  final String title;
  final String subtitle;
  final String? posterUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xff101719),
        border: Border.all(color: const Color(0xff263235)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(width: 42, child: _PosterArt(url: posterUrl, title: title)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xff9fb3b7)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterArt extends StatelessWidget {
  const _PosterArt({required this.title, this.url});

  final String title;
  final String? url;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: title,
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: url == null
              ? _placeholder()
              : Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder(),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return _placeholder(loading: true);
                  },
                ),
        ),
      ),
    );
  }

  Widget _placeholder({bool loading = false}) {
    return Container(
      color: const Color(0xff223034),
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(
              Icons.movie_creation_outlined,
              size: 34,
              color: Color(0xff9fb3b7),
            ),
    );
  }
}

class _DiagnosticCard extends StatelessWidget {
  const _DiagnosticCard({required this.item});

  final ServiceHealth item;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StatePill(state: item.state),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.configured ? "已配置" : "未配置",
            style: const TextStyle(color: Color(0xff9fb3b7)),
          ),
          const SizedBox(height: 8),
          Text(item.message, maxLines: 3, overflow: TextOverflow.ellipsis),
          if (item.baseUrl != null) ...[
            const SizedBox(height: 8),
            Text(
              item.baseUrl!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Color(0xff9fb3b7)),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.state});

  final String state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      "ready" => const Color(0xff1fb6a6),
      "unreachable" => const Color(0xffd66d65),
      _ => const Color(0xffd6b85d),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        state,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.item,
    required this.onDetail,
    required this.onPlay,
  });

  final MediaItem item;
  final VoidCallback onDetail;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: _PosterArt(url: item.posterUrl, title: item.title),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    item.source,
                    "${(item.durationSeconds / 60).round()} 分钟",
                    item.watched ? "已看" : null,
                    item.favorite ? "收藏" : null,
                  ].whereType<String>().join(" · "),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xff9fb3b7)),
                ),
                const Spacer(),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _SecondaryAction(label: "详情", onPressed: onDetail),
                    _PrimaryAction(label: "播放", onPressed: onPlay),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({
    required this.tasks,
    this.onPause,
    this.onResume,
    this.onComplete,
    this.onImport,
  });

  final List<DownloadTask> tasks;
  final ValueChanged<DownloadTask>? onPause;
  final ValueChanged<DownloadTask>? onResume;
  final ValueChanged<DownloadTask>? onComplete;
  final ValueChanged<DownloadTask>? onImport;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const SizedBox(height: 120, child: Center(child: Text("暂无任务")));
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.episodeTitle,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "${task.source} · ${task.stateLabel} · ${task.progress.round()}%",
              ),
              if (task.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  task.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xffd6b85d)),
                ),
              ],
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: (task.progress / 100).clamp(0.0, 1.0).toDouble(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (task.canCompleteLocally && onComplete != null)
                    _PrimaryAction(
                      label: "完成",
                      onPressed: () => onComplete!(task),
                    ),
                  if (task.canResume && onResume != null)
                    _SecondaryAction(
                      label: "恢复",
                      onPressed: () => onResume!(task),
                    )
                  else if (task.state == "completed" && onImport != null)
                    _PrimaryAction(
                      label: "入库",
                      onPressed: () => onImport!(task),
                    )
                  else if (task.canPause && onPause != null)
                    _SecondaryAction(
                      label: "暂停",
                      onPressed: () => onPause!(task),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(110, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ).copyWith(
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return const BorderSide(color: Colors.white, width: 3);
          }
          return BorderSide.none;
        }),
        elevation: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.focused) ? 8.0 : 0.0;
        }),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(110, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ).copyWith(
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return const BorderSide(color: Colors.white, width: 3);
          }
          return BorderSide(
            color: states.contains(WidgetState.disabled)
                ? const Color(0xff2a3437)
                : const Color(0xff7f9298),
            width: 1.2,
          );
        }),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
  }
}

String normalizeBaseUrl(String value) {
  return normalizeBaseUrlWithFallback(value, defaultServerUrl);
}

String normalizeBaseUrlWithFallback(String value, String fallback) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return fallback;
  return trimmed.replaceFirst(RegExp(r"/+$"), "");
}

Map<String, dynamic> asMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> listOf(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

List<String> listOfStrings(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList();
}

String stringValue(Object? value, {String fallback = ""}) {
  if (value == null) return fallback;
  return value.toString();
}

String? nullableString(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

String? nullIfBlank(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String formatDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final remaining = seconds % 60;
  return "$minutes:${remaining.toString().padLeft(2, "0")}";
}

int intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? "") ?? 0;
}

int? nullableInt(Object? value) {
  if (value == null) return null;
  return intValue(value);
}

double doubleValue(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? "") ?? 0;
}

double? nullableDouble(Object? value) {
  if (value == null) return null;
  return doubleValue(value);
}

bool boolValue(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return value?.toString().toLowerCase() == "true";
}
