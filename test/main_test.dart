import "package:flutter_test/flutter_test.dart";

import "package:cluo_vision/main.dart";

void main() {
  test("normalizeBaseUrl removes trailing slash", () {
    expect(normalizeBaseUrl("http://127.0.0.1:3000/"), "http://127.0.0.1:3000");
    expect(
        normalizeBaseUrl("http://127.0.0.1:3000///"), "http://127.0.0.1:3000");
    expect(normalizeBaseUrl("http://127.0.0.1:3000"), "http://127.0.0.1:3000");
    expect(normalizeBaseUrl("  "), "http://127.0.0.1:3000");
  });

  test("normalizeBaseUrlWithFallback supports build-time default server URL",
      () {
    expect(
      normalizeBaseUrlWithFallback("  ", "http://192.168.1.20:3000"),
      "http://192.168.1.20:3000",
    );
    expect(
      normalizeBaseUrlWithFallback(" http://192.168.1.20:3000/ ", "unused"),
      "http://192.168.1.20:3000",
    );
  });

  test("PlaybackSession parses Android intent target", () {
    final session = PlaybackSession.fromJson({
      "id": "session-1",
      "provider": "external-player",
      "mode": "intent",
      "state": "playing",
      "positionSeconds": 12,
      "durationSeconds": 120,
      "progress": 0.1,
      "url": "http://server:8096/Videos/item/stream.mkv",
      "intent": {
        "uri":
            "intent://server:8096/Videos/item/stream.mkv#Intent;scheme=http;type=video%2F*;end",
      },
    });

    expect(session.provider, "external-player");
    expect(session.mode, "intent");
    expect(session.intentUri, startsWith("intent://server:8096"));
    expect(session.progress, 0.1);
    expect(session.shouldTrackExternalReturn, isTrue);
  });

  test("external playback return estimator updates resumable position", () {
    final session = PlaybackSession.fromJson({
      "id": "session-1",
      "provider": "external-player",
      "mode": "intent",
      "state": "playing",
      "positionSeconds": 90,
      "durationSeconds": 120,
      "progress": 0.75,
      "url": "http://server:8096/Videos/item/stream.mkv",
      "intent": {
        "uri":
            "intent://server:8096/Videos/item/stream.mkv#Intent;scheme=http;type=video%2F*;end",
      },
    });

    expect(
      estimateExternalPlaybackReturnPosition(
        session: session,
        elapsed: const Duration(seconds: 15),
      ),
      105,
    );
    expect(
      estimateExternalPlaybackReturnPosition(
        session: session,
        elapsed: const Duration(minutes: 10),
      ),
      120,
    );
  });

  test("local mock playback does not use external return tracking", () {
    final session = PlaybackSession.fromJson({
      "id": "session-1",
      "provider": "local-dev",
      "mode": "mock-stream",
      "state": "playing",
      "positionSeconds": 12,
      "durationSeconds": 120,
      "progress": 0.1,
      "url": "mock://stream",
    });

    expect(session.shouldTrackExternalReturn, isFalse);
  });

  test("buildAndroidViewIntentUri includes external player package", () {
    final intentUri = buildAndroidViewIntentUri(
      "http://server:8096/Videos/item/stream.mkv?mediaSourceId=source 1",
      "video/*",
      "com.hush.yamby",
    );

    expect(
        intentUri, startsWith("intent://server:8096/Videos/item/stream.mkv"));
    expect(intentUri, contains("scheme=http"));
    expect(intentUri, contains("type=video%2F*"));
    expect(intentUri, contains("package=com.hush.yamby"));
    expect(intentUri, endsWith(";end"));
  });

  test("PlaybackHandlerDiagnostics summarizes external player readiness", () {
    final ready = PlaybackHandlerDiagnostics.fromPlatform({
      "platform": "android",
      "packageName": "com.hush.yamby",
      "packageInstalled": true,
      "canHandleUrl": false,
      "canHandleIntentUri": true,
      "urlHandlerCount": 1,
      "intentHandlerCount": 1,
      "urlHandlers": ["com.hush.yamby/.PlayerActivity"],
      "intentHandlers": ["com.hush.yamby/.PlayerActivity"],
    });
    final missing = PlaybackHandlerDiagnostics.fromPlatform({
      "platform": "android",
      "packageName": "com.hush.yamby",
      "packageInstalled": false,
      "canHandleUrl": false,
      "canHandleIntentUri": false,
      "urlHandlerCount": 0,
      "intentHandlerCount": 0,
    });

    expect(ready.summary, "播放器检测通过");
    expect(ready.urlHandlers, ["com.hush.yamby/.PlayerActivity"]);
    expect(ready.intentHandlers, ["com.hush.yamby/.PlayerActivity"]);
    expect(missing.summary, "未检测到播放器包：com.hush.yamby");
    expect(missing.urlHandlers, isEmpty);
  });

  test("DownloadTask exposes local-dev completion capability", () {
    final localTask = DownloadTask.fromJson({
      "id": "task-1",
      "title": "迷宫饭",
      "episodeTitle": "迷宫饭 - S01E01",
      "source": "local-dev",
      "state": "downloading",
      "progress": 40,
      "speedBytesPerSecond": 0,
    });
    final remoteTask = DownloadTask.fromJson({
      "id": "remote-1",
      "title": "迷宫饭",
      "episodeTitle": "迷宫饭 - S01E01",
      "source": "autobangumi",
      "state": "downloading",
      "progress": 40,
      "speedBytesPerSecond": 0,
    });

    expect(localTask.canCompleteLocally, isTrue);
    expect(localTask.canPause, isTrue);
    expect(remoteTask.canCompleteLocally, isFalse);
    expect(remoteTask.canPause, isTrue);
  });

  test("queued AutoBangumi task does not expose local controls", () {
    final queuedTask = DownloadTask.fromJson({
      "id": "remote-waiting",
      "title": "迷宫饭",
      "episodeTitle": "迷宫饭 - S01E01",
      "source": "autobangumi",
      "state": "queued",
      "progress": 0,
      "speedBytesPerSecond": 0,
    });

    expect(queuedTask.canCompleteLocally, isFalse);
    expect(queuedTask.canPause, isFalse);
    expect(queuedTask.canResume, isFalse);
    expect(queuedTask.stateLabel, "等待队列");
  });

  test("completed downloads due for auto import are throttled", () {
    final now = DateTime.parse("2026-07-05T12:00:00.000Z");
    final completed = DownloadTask.fromJson({
      "id": "completed-1",
      "title": "迷宫饭",
      "episodeTitle": "迷宫饭 - S01E01",
      "source": "qbittorrent",
      "state": "completed",
      "progress": 100,
      "speedBytesPerSecond": 0,
    });
    final downloading = DownloadTask.fromJson({
      "id": "downloading-1",
      "title": "迷宫饭",
      "episodeTitle": "迷宫饭 - S01E02",
      "source": "qbittorrent",
      "state": "downloading",
      "progress": 40,
      "speedBytesPerSecond": 1024,
    });

    expect(
      completedDownloadIdsDueForAutoImport(
        downloads: [completed, downloading],
        lastAttemptById: const {},
        now: now,
        retryDelay: const Duration(minutes: 2),
      ),
      ["completed-1"],
    );
    expect(
      completedDownloadIdsDueForAutoImport(
        downloads: [completed],
        lastAttemptById: {
          "completed-1": now.subtract(const Duration(seconds: 30)),
        },
        now: now,
        retryDelay: const Duration(minutes: 2),
      ),
      isEmpty,
    );
    expect(
      completedDownloadIdsDueForAutoImport(
        downloads: [completed],
        lastAttemptById: {
          "completed-1": now.subtract(const Duration(minutes: 3)),
        },
        now: now,
        retryDelay: const Duration(minutes: 2),
      ),
      ["completed-1"],
    );
  });

  test("Anime tracking models parse subscription and rule status", () {
    final subscription = AnimeSubscription.fromJson({
      "id": "sub-1",
      "title": "迷宫饭",
      "provider": "local-dev",
      "status": "active",
      "createdAt": "2026-07-05T00:00:00.000Z",
      "rssUrl": "mock://rss/delicious-in-dungeon",
    });
    final rule = AnimeRule.fromJson({
      "id": "rule-1",
      "title": "迷宫饭",
      "provider": "autobangumi",
      "status": "active",
      "rssUrls": ["https://example.test/rss"],
      "needsReview": true,
    });

    expect(subscription.title, "迷宫饭");
    expect(subscription.provider, "local-dev");
    expect(rule.rssUrls, ["https://example.test/rss"]);
    expect(rule.needsReview, isTrue);
  });

  test("Search history entry parses discover result counts", () {
    final entry = SearchHistoryEntry.fromJson({
      "query": "迷宫",
      "searchCount": 2,
      "resultCounts": {"library": 1, "anime": 3},
      "lastSearchedAt": "2026-07-05T00:00:00.000Z",
    });

    expect(entry.query, "迷宫");
    expect(entry.searchCount, 2);
    expect(entry.libraryCount, 1);
    expect(entry.animeCount, 3);
  });
}
