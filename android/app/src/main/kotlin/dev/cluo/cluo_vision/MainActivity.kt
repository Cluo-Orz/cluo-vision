package dev.cluo.cluo_vision

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cluo_vision/playback")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "launchIntentUri" -> {
                        val uri = call.argument<String>("uri")
                        if (uri.isNullOrBlank()) {
                            result.success(mapOf("launched" to false, "message" to "缺少 intent uri"))
                            return@setMethodCallHandler
                        }

                        try {
                            val intent = Intent.parseUri(uri, Intent.URI_INTENT_SCHEME)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(mapOf("launched" to true, "message" to "已启动外部播放器"))
                        } catch (error: ActivityNotFoundException) {
                            result.success(mapOf("launched" to false, "message" to "未找到可用播放器"))
                        } catch (error: Exception) {
                            result.success(mapOf("launched" to false, "message" to "播放器启动失败：${error.message}"))
                        }
                    }

                    "launchUrl" -> {
                        val url = call.argument<String>("url")
                        val mimeType = call.argument<String>("mimeType") ?: "video/*"
                        if (url.isNullOrBlank()) {
                            result.success(mapOf("launched" to false, "message" to "缺少播放地址"))
                            return@setMethodCallHandler
                        }

                        try {
                            val intent = Intent(Intent.ACTION_VIEW)
                                .setDataAndType(Uri.parse(url), mimeType)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(mapOf("launched" to true, "message" to "已启动播放流"))
                        } catch (error: ActivityNotFoundException) {
                            result.success(mapOf("launched" to false, "message" to "未找到可用播放器"))
                        } catch (error: Exception) {
                            result.success(mapOf("launched" to false, "message" to "播放流启动失败：${error.message}"))
                        }
                    }

                    "checkPlaybackHandlers" -> {
                        val packageName = call.argument<String>("packageName")?.trim()?.ifBlank { null }
                        val url = call.argument<String>("url")?.trim()?.ifBlank { null }
                        val mimeType = call.argument<String>("mimeType")?.trim()?.ifBlank { "video/*" } ?: "video/*"
                        val intentUri = call.argument<String>("intentUri")?.trim()?.ifBlank { null }

                        try {
                            result.success(
                                mapOf(
                                    "platform" to "android",
                                    "packageName" to packageName,
                                    "packageInstalled" to isPackageInstalled(packageName),
                                    "canHandleUrl" to canHandleUrl(url, mimeType, packageName),
                                    "canHandleIntentUri" to canHandleIntentUri(intentUri),
                                    "urlHandlerCount" to countUrlHandlers(url, mimeType),
                                    "intentHandlerCount" to countIntentHandlers(intentUri),
                                    "urlHandlers" to listUrlHandlers(url, mimeType),
                                    "intentHandlers" to listIntentHandlers(intentUri),
                                )
                            )
                        } catch (error: Exception) {
                            result.success(
                                mapOf(
                                    "platform" to "android",
                                    "packageName" to packageName,
                                    "packageInstalled" to false,
                                    "canHandleUrl" to false,
                                    "canHandleIntentUri" to false,
                                    "urlHandlerCount" to 0,
                                    "intentHandlerCount" to 0,
                                    "urlHandlers" to emptyList<String>(),
                                    "intentHandlers" to emptyList<String>(),
                                    "message" to "播放器检测失败：${error.message}",
                                )
                            )
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun isPackageInstalled(packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun canHandleUrl(url: String?, mimeType: String, packageName: String?): Boolean {
        val intent = buildUrlIntent(url, mimeType, packageName) ?: return false
        return intent.resolveActivity(packageManager) != null
    }

    private fun countUrlHandlers(url: String?, mimeType: String): Int {
        val intent = buildUrlIntent(url, mimeType, null) ?: return 0
        return queryIntentActivityNames(intent).size
    }

    private fun canHandleIntentUri(intentUri: String?): Boolean {
        val intent = parseIntentUri(intentUri) ?: return false
        return intent.resolveActivity(packageManager) != null
    }

    private fun countIntentHandlers(intentUri: String?): Int {
        val intent = parseIntentUri(intentUri) ?: return 0
        return queryIntentActivityNames(intent).size
    }

    private fun listUrlHandlers(url: String?, mimeType: String): List<String> {
        val intent = buildUrlIntent(url, mimeType, null) ?: return emptyList()
        return queryIntentActivityNames(intent)
    }

    private fun listIntentHandlers(intentUri: String?): List<String> {
        val intent = parseIntentUri(intentUri) ?: return emptyList()
        return queryIntentActivityNames(intent)
    }

    private fun buildUrlIntent(url: String?, mimeType: String, packageName: String?): Intent? {
        if (url.isNullOrBlank()) return null
        return Intent(Intent.ACTION_VIEW)
            .setDataAndType(Uri.parse(url), mimeType)
            .addCategory(Intent.CATEGORY_DEFAULT)
            .apply {
                if (!packageName.isNullOrBlank()) setPackage(packageName)
            }
    }

    private fun parseIntentUri(intentUri: String?): Intent? {
        if (intentUri.isNullOrBlank()) return null
        return Intent.parseUri(intentUri, Intent.URI_INTENT_SCHEME)
            .addCategory(Intent.CATEGORY_DEFAULT)
    }

    private fun queryIntentActivityNames(intent: Intent): List<String> {
        val activities = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                intent,
                PackageManager.ResolveInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(intent, 0)
        }
        return activities
            .mapNotNull { info ->
                val activity = info.activityInfo ?: return@mapNotNull null
                val packageName = activity.packageName ?: return@mapNotNull null
                val name = activity.name ?: return@mapNotNull packageName
                if (name.isBlank()) packageName else "$packageName/$name"
            }
            .distinct()
            .take(8)
    }
}
