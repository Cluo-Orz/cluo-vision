# Android Playback Channel

> Status: Android platform directory generated, `MainActivity.kt` implemented, and `flutter build apk --debug` passed locally. Pending Android TV device verification.

Flutter client code calls `MethodChannel("cluo_vision/playback")` after `cluo-server` creates a playback session.

When an external player takes focus and the user returns to Cluo, the Flutter app stops the active playback session and estimates the resume position from the time spent outside Cluo. This is a practical fallback for generic `ACTION_VIEW` playback targets. It does not prove that Yamby, Jellyfin Android TV, or another player writes native Jellyfin progress; that still requires device verification.

Local debug APK build output:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

Windows build note: `android/gradle.properties` sets `kotlin.incremental=false` because the project may live on `D:` while Flutter/Pub cache plugin sources live on `C:`. Kotlin incremental compilation can fail when it tries to calculate relative paths across different drive roots.

## Channel Contract

### `launchIntentUri`

Input:

```json
{
  "uri": "intent://server/Videos/item/stream.mkv?...#Intent;scheme=http;action=android.intent.action.VIEW;type=video%2F*;package=is.xyz.mpv;end"
}
```

Return:

```json
{
  "launched": true,
  "message": "已启动外部播放器"
}
```

### `launchUrl`

Input:

```json
{
  "url": "http://server:8096/Videos/item/stream.mkv?...",
  "mimeType": "video/*"
}
```

Return:

```json
{
  "launched": true,
  "message": "已启动播放流"
}
```

### `checkPlaybackHandlers`

Input:

```json
{
  "packageName": "com.hush.yamby",
  "url": "http://server:8096/Videos/item/stream.mkv?...",
  "intentUri": "intent://server/Videos/item/stream.mkv?...#Intent;scheme=http;action=android.intent.action.VIEW;type=video%2F*;package=com.hush.yamby;end",
  "mimeType": "video/*"
}
```

Return:

```json
{
  "platform": "android",
  "packageName": "com.hush.yamby",
  "packageInstalled": true,
  "canHandleUrl": false,
  "canHandleIntentUri": true,
  "urlHandlerCount": 1,
  "intentHandlerCount": 1
}
```

`packageInstalled` only confirms whether the preferred player package exists. `canHandleUrl` and `canHandleIntentUri` confirm whether Android can resolve the generated playback target.

## Android Implementation

The current implementation lives at `android/app/src/main/kotlin/dev/cluo/cluo_vision/MainActivity.kt`.

`AndroidManifest.xml` declares package visibility for common Jellyfin/external player packages:

- `com.hush.yamby` — Yamby package published on Google Play
- `is.xyz.mpv` — mpv-android
- `org.videolan.vlc` — VLC
- `org.jellyfin.androidtv` — Jellyfin Android TV
- `tv.emby.embyatv` — Emby Android TV

## Verification Checklist

1. Configure `cluo-server` playback provider as `external-player`.
2. Set `externalPlayerPackage` to `com.hush.yamby` for Yamby, or leave it empty to let Android choose a player.
3. Use the settings page "检测播放器" action on the Android TV device.
4. Start a Jellyfin-backed media item from Cluo.
5. Confirm the player opens without a chooser dead end.
6. Return to Cluo; verify that Cluo automatically stops the session and updates local history/resume position.
7. Verify whether the chosen player also updates Jellyfin native resume/watched state. If it does not, treat Cluo's elapsed-time update as the fallback until a stronger provider is validated.
