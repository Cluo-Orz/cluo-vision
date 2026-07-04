import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";

import "package:cluo_vision/main.dart";

void main() {
  test("CluoApi follows the BFF main-flow contract", () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = <String>[];
    final errors = <Object>[];
    server.listen((request) async {
      try {
        await _handleContractRequest(request, seen);
      } catch (error) {
        errors.add(error);
        await _writeJson(
          request,
          {"error": error.toString()},
          statusCode: HttpStatus.internalServerError,
        );
      }
    });

    try {
      final api = CluoApi("http://127.0.0.1:${server.port}/");

      final health = await api.health();
      expect(health["status"], "ok");

      final register = await api.register(
        username: "owner",
        password: "change-me",
        displayName: "Owner",
      );
      expect(asMap(register["user"])["displayName"], "Owner");

      final login = await api.login(username: "owner", password: "change-me");
      api.token = stringValue(login["token"]);

      final sources = listOf((await api.discoverSources())["items"])
          .map(DiscoverSource.fromJson)
          .toList();
      expect(sources.first.id, "jellyfin-library");
      expect(sources.first.available, isTrue);

      final discover = await api.discoverSearch("迷宫 饭");
      final anime = AnimeSearchResult.fromJson(listOf(discover["anime"]).first);
      expect(anime.title, "迷宫饭");
      expect(listOf(discover["recent"]).first["query"], "迷宫 饭");

      final subscribe = await api.subscribeAnime(
        title: anime.title,
        provider: anime.provider,
        rssUrl: anime.rssUrl,
        posterUrl: anime.posterUrl,
        autoBangumi: anime.raw,
      );
      final task = DownloadTask.fromJson(asMap(subscribe["download"]));
      expect(task.canCompleteLocally, isTrue);

      expect(
        DownloadTask.fromJson(
                asMap((await api.controlDownload(task.id, "pause"))["item"]))
            .state,
        "paused",
      );
      expect(
        DownloadTask.fromJson(
                asMap((await api.controlDownload(task.id, "resume"))["item"]))
            .state,
        "downloading",
      );

      final complete = await api.completeDownload(task.id);
      final media = MediaItem.fromJson(listOf(complete["mediaItems"]).first);
      expect(media.title, "迷宫饭 - S01E01");

      final imported = await api.importDownload(task.id);
      expect(MediaItem.fromJson(listOf(imported["items"]).first).id, media.id);

      final batchImport = await api.importCompletedDownloads();
      expect(batchImport["imported"], 1);
      expect(
          MediaItem.fromJson(listOf(batchImport["items"]).first).id, media.id);

      final automation = await api.runDownloadImportAutomation();
      expect(automation["attempted"], 1);
      expect(automation["imported"], 1);

      expect(
        MediaItem.fromJson(listOf((await api.libraryItems())["items"]).first)
            .id,
        media.id,
      );
      final jellyfinSync = await api.syncJellyfinLibrary(
        searchTerm: "迷宫 饭",
        scan: true,
      );
      expect(jellyfinSync["scanTriggered"], isTrue);
      expect(jellyfinSync["synced"], 1);
      expect(
        MediaItem.fromJson(
                listOf((await api.librarySearch("迷宫 饭"))["items"]).first)
            .id,
        media.id,
      );

      final playback = PlaybackSession.fromJson(
        asMap((await api.startPlayback(media.id))["session"]),
      );
      expect(playback.mode, "mock-stream");

      final heartbeat = PlaybackSession.fromJson(
        asMap(
          (await api.playbackHeartbeat(
            playback.id,
            positionSeconds: 600,
          ))["session"],
        ),
      );
      expect(heartbeat.positionSeconds, 600);

      final history =
          HistoryEntry.fromJson(listOf((await api.history())["items"]).first);
      expect(history.itemId, media.id);
      expect(history.progress, closeTo(600 / 1440, 0.001));

      final stopped = PlaybackSession.fromJson(
        asMap(
          (await api.stopPlayback(
            playback.id,
            positionSeconds: 700,
          ))["session"],
        ),
      );
      expect(stopped.state, "stopped");

      final watched = MediaItem.fromJson(
        asMap((await api.setWatched(media.id, true))["item"]),
      );
      expect(watched.watched, isTrue);

      final favorite = MediaItem.fromJson(
        asMap((await api.setFavorite(media.id, true))["item"]),
      );
      expect(favorite.favorite, isTrue);

      expect(HomeData.fromJson(await api.home()).recentlyAdded.single.title,
          media.title);

      expect(errors, isEmpty);
      expect(
          seen,
          contains(
              "GET /api/discover/search?q=%E8%BF%B7%E5%AE%AB+%E9%A5%AD&limit=12"));
      expect(seen, contains("GET /api/discover/sources"));
      expect(seen, contains("POST /api/downloads/task%201/pause"));
      expect(seen, contains("POST /api/downloads/import-completed"));
      expect(seen, contains("POST /api/automation/download-import/run"));
      expect(seen, contains("POST /api/library/sync/jellyfin"));
      expect(seen, contains("PATCH /api/playback/sessions/session%201"));
    } finally {
      await server.close(force: true);
    }
  });
}

Future<void> _handleContractRequest(
    HttpRequest request, List<String> seen) async {
  seen.add("${request.method} ${request.uri}");

  if (request.method == "GET" && request.uri.path == "/api/health") {
    await _writeJson(request, {"status": "ok", "version": "0.1.0"});
    return;
  }

  if (request.method == "POST" && request.uri.path == "/api/auth/register") {
    final body = await _readJson(request);
    expect(body["username"], "owner");
    expect(body["password"], "change-me");
    expect(body["displayName"], "Owner");
    await _writeJson(
      request,
      {
        "user": {"username": "owner", "displayName": "Owner"},
        "token": "register-token",
      },
      statusCode: HttpStatus.created,
    );
    return;
  }

  if (request.method == "POST" && request.uri.path == "/api/auth/login") {
    final body = await _readJson(request);
    expect(body["username"], "owner");
    expect(body["password"], "change-me");
    await _writeJson(
      request,
      {
        "user": {"username": "owner", "displayName": "Owner"},
        "token": "contract-token",
      },
    );
    return;
  }

  _expectAuth(request);

  if (request.method == "GET" && request.uri.path == "/api/discover/sources") {
    await _writeJson(request, {
      "items": [
        {
          "id": "jellyfin-library",
          "label": "Jellyfin 媒体库",
          "kind": "library",
          "configured": true,
          "available": true,
          "status": "ready",
          "description": "已接入 Jellyfin",
          "provider": "jellyfin",
          "baseUrl": "http://127.0.0.1:8096",
          "tags": ["媒体库", "海报墙"],
          "requiredFor": ["library", "playback"],
        },
      ],
    });
    return;
  }

  if (request.method == "GET" && request.uri.path == "/api/discover/search") {
    expect(request.uri.queryParameters["q"], "迷宫 饭");
    expect(request.uri.queryParameters["limit"], "12");
    await _writeJson(request, {
      "query": "迷宫 饭",
      "library": [],
      "anime": [
        {
          "title": "迷宫饭",
          "provider": "local-dev",
          "rssUrl": "mock://rss/dungeon",
          "posterUrl": "https://example.test/poster.jpg",
          "confidence": 0.95,
          "raw": {"id": 1},
        },
      ],
      "recent": [
        {
          "query": "迷宫 饭",
          "searchCount": 1,
          "resultCounts": {"library": 0, "anime": 1},
          "lastSearchedAt": "2026-07-05T00:00:00.000Z",
        },
      ],
    });
    return;
  }

  if (request.method == "POST" && request.uri.path == "/api/anime/subscribe") {
    final body = await _readJson(request);
    expect(body["title"], "迷宫饭");
    expect(body["provider"], "local-dev");
    expect(body["rssUrl"], "mock://rss/dungeon");
    expect(body["posterUrl"], "https://example.test/poster.jpg");
    expect(asMap(body["autoBangumi"])["id"], 1);
    await _writeJson(
        request,
        {
          "subscription": {
            "id": "sub 1",
            "title": "迷宫饭",
            "provider": "local-dev",
            "status": "active",
            "rssUrl": "mock://rss/dungeon",
            "createdAt": "2026-07-05T00:00:00.000Z",
          },
          "download": _downloadTask("downloading"),
        },
        statusCode: HttpStatus.created);
    return;
  }

  final segments = request.uri.pathSegments;
  if (_matches(segments, ["api", "downloads", "task 1", "pause"])) {
    await _writeJson(request, {"item": _downloadTask("paused")});
    return;
  }
  if (_matches(segments, ["api", "downloads", "task 1", "resume"])) {
    await _writeJson(request, {"item": _downloadTask("downloading")});
    return;
  }
  if (_matches(segments, ["api", "anime", "downloads", "task 1", "complete"])) {
    await _writeJson(request, {
      "item": _downloadTask("completed"),
      "mediaItems": [_mediaItem()],
    });
    return;
  }
  if (_matches(segments, ["api", "downloads", "task 1", "import"])) {
    await _writeJson(request, {
      "configured": false,
      "status": "local-only",
      "synced": 1,
      "items": [_mediaItem()],
      "searchTerms": ["迷宫饭"],
      "message": "Local media item already exists.",
    });
    return;
  }
  if (_matches(segments, ["api", "downloads", "import-completed"])) {
    await _writeJson(request, {
      "total": 1,
      "imported": 1,
      "pending": 0,
      "failed": 0,
      "synced": 1,
      "items": [_mediaItem()],
      "results": [
        {
          "configured": false,
          "status": "local-only",
          "synced": 1,
          "items": [_mediaItem()],
          "searchTerms": ["迷宫饭"],
          "message": "Local media item already exists.",
        }
      ],
    });
    return;
  }

  if (_matches(segments, ["api", "automation", "download-import", "run"])) {
    await _writeJson(request, {
      "checkedAt": "2026-07-05T00:00:00.000Z",
      "totalCompleted": 1,
      "attempted": 1,
      "imported": 1,
      "pending": 0,
      "failed": 0,
      "synced": 1,
      "skipped": 0,
      "results": [
        {
          "configured": false,
          "status": "local-only",
          "synced": 1,
          "items": [_mediaItem()],
          "searchTerms": ["迷宫饭"],
          "message": "Local media item already exists.",
        }
      ],
      "errors": [],
    });
    return;
  }

  if (request.method == "GET" && request.uri.path == "/api/library/items") {
    expect(request.uri.queryParameters["limit"], "100");
    await _writeJson(request, {
      "items": [_mediaItem()]
    });
    return;
  }

  if (_matches(segments, ["api", "library", "sync", "jellyfin"])) {
    final body = await _readJson(request);
    expect(body["searchTerm"], "迷宫 饭");
    expect(body["scan"], true);
    await _writeJson(request, {
      "configured": true,
      "scanTriggered": true,
      "synced": 1,
      "items": [_mediaItem()],
    });
    return;
  }

  if (request.method == "GET" && request.uri.path == "/api/library/search") {
    expect(request.uri.queryParameters["q"], "迷宫 饭");
    await _writeJson(request, {
      "items": [_mediaItem()]
    });
    return;
  }

  if (_matches(segments, ["api", "playback", "sessions"]) &&
      request.method == "POST") {
    final body = await _readJson(request);
    expect(body["itemId"], "media 1");
    await _writeJson(
      request,
      {"session": _playbackSession(positionSeconds: 0, state: "playing")},
      statusCode: HttpStatus.created,
    );
    return;
  }

  if (_matches(segments, ["api", "playback", "sessions", "session 1"]) &&
      request.method == "PATCH") {
    final body = await _readJson(request);
    expect(body["positionSeconds"], 600);
    expect(body["state"], "playing");
    await _writeJson(
      request,
      {"session": _playbackSession(positionSeconds: 600, state: "playing")},
    );
    return;
  }

  if (_matches(
      segments, ["api", "playback", "sessions", "session 1", "stop"])) {
    final body = await _readJson(request);
    expect(body["positionSeconds"], 700);
    await _writeJson(
      request,
      {"session": _playbackSession(positionSeconds: 700, state: "stopped")},
    );
    return;
  }

  if (request.method == "GET" && request.uri.path == "/api/history") {
    await _writeJson(request, {
      "items": [
        {
          "itemId": "media 1",
          "title": "迷宫饭 - S01E01",
          "positionSeconds": 600,
          "durationSeconds": 1440,
          "progress": 600 / 1440,
          "lastWatchedAt": "2026-07-05T00:00:00.000Z",
        },
      ],
    });
    return;
  }

  if (_matches(segments, ["api", "library", "items", "media 1", "watched"])) {
    final body = await _readJson(request);
    expect(body["watched"], true);
    await _writeJson(request, {
      "item": {..._mediaItem(), "watched": true},
    });
    return;
  }

  if (_matches(segments, ["api", "library", "items", "media 1", "favorite"])) {
    final body = await _readJson(request);
    expect(body["favorite"], true);
    await _writeJson(request, {
      "item": {..._mediaItem(), "favorite": true},
    });
    return;
  }

  if (request.method == "GET" && request.uri.path == "/api/home") {
    await _writeJson(request, {
      "continueWatching": [
        {
          "itemId": "media 1",
          "title": "迷宫饭 - S01E01",
          "positionSeconds": 600,
          "durationSeconds": 1440,
          "progress": 600 / 1440,
          "lastWatchedAt": "2026-07-05T00:00:00.000Z",
        },
      ],
      "recentlyAdded": [_mediaItem()],
      "activeDownloads": [],
    });
    return;
  }

  throw StateError("Unexpected request: ${request.method} ${request.uri}");
}

void _expectAuth(HttpRequest request) {
  expect(
    request.headers.value(HttpHeaders.authorizationHeader),
    "Bearer contract-token",
  );
}

Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
  final text = await utf8.decoder.bind(request).join();
  if (text.isEmpty) return <String, dynamic>{};
  final decoded = jsonDecode(text);
  expect(decoded, isA<Map>());
  return Map<String, dynamic>.from(decoded as Map);
}

Future<void> _writeJson(
  HttpRequest request,
  Object body, {
  int statusCode = HttpStatus.ok,
}) async {
  request.response.statusCode = statusCode;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

bool _matches(List<String> actual, List<String> expected) {
  if (actual.length != expected.length) return false;
  for (var i = 0; i < expected.length; i += 1) {
    if (actual[i] != expected[i]) return false;
  }
  return true;
}

Map<String, Object?> _downloadTask(String state) => {
      "id": "task 1",
      "title": "迷宫饭",
      "episodeTitle": "迷宫饭 - S01E01",
      "source": "local-dev",
      "state": state,
      "progress": state == "completed" ? 100 : 40,
      "speedBytesPerSecond": 0,
    };

Map<String, Object?> _mediaItem() => {
      "id": "media 1",
      "title": "迷宫饭 - S01E01",
      "source": "local-dev",
      "type": "anime-episode",
      "durationSeconds": 1440,
      "downloadTaskId": "task 1",
      "animeId": "sub 1",
      "createdAt": "2026-07-05T00:00:00.000Z",
    };

Map<String, Object?> _playbackSession({
  required int positionSeconds,
  required String state,
}) =>
    {
      "id": "session 1",
      "provider": "local-dev",
      "mode": "mock-stream",
      "state": state,
      "positionSeconds": positionSeconds,
      "durationSeconds": 1440,
      "progress": positionSeconds / 1440,
      "url": "mock://media/task 1.mkv",
    };
