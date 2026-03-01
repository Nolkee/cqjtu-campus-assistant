package com.example.campus_app

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "campus_app/battery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // ── 查询是否已忽略电池优化 ──────────────────────
                    "isIgnoringBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(POWER_SERVICE) as PowerManager
                            result.success(pm.isIgnoringBatteryOptimizations(packageName))
                        } else {
                            // Android 6 以下没有电池优化概念，视为已豁免
                            result.success(true)
                        }
                    }

                    // ── 请求加入电池优化白名单 ───────────────────────
                    "requestIgnoreBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            try {
                                val intent = Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                                ).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                                startActivity(intent)
                                result.success(null)
                            } catch (e: Exception) {
                                // 部分 MIUI 版本会拦截此 Intent，降级到 App 详情页
                                openAppDetails()
                                result.success(null)
                            }
                        } else {
                            result.success(null)
                        }
                    }

                    // ── 查询 MIUI 自启动权限状态 ─────────────────────
                    // 返回 true=已开启, false=已关闭, null=无法检测(非MIUI)
                    "checkMiuiAutostart" -> {
                        try {
                            val appOps = getSystemService(APP_OPS_SERVICE) as android.app.AppOpsManager
                            // MIUI 自启动 op 码固定为 10021（MIUI12/13/HyperOS均适用）
                            val OP_AUTO_START = 10021
                            
                            val method = appOps.javaClass.getMethod(
                                "checkOpNoThrow",
                                Int::class.javaPrimitiveType,
                                Int::class.javaPrimitiveType,
                                String::class.java
                            )
                            val mode = method.invoke(
                                appOps, 
                                OP_AUTO_START, 
                                android.os.Process.myUid(), 
                                packageName
                            ) as Int
                            
                            result.success(mode == android.app.AppOpsManager.MODE_ALLOWED)
                        } catch (e: Exception) {
                            // 非 MIUI 设备或系统拦截，返回 null 表示无法检测
                            result.success(null)
                        }
                    }

                    // ── 打开 MIUI 自启动管理页 ───────────────────────
                    "openMiuiAutostart" -> {
                        var opened = false

                        // MIUI 12 / 13 / HyperOS 路径（按优先级尝试）
                        val miuiTargets = listOf(
                            "com.miui.securitycenter" to
                                "com.miui.permcenter.autostart.AutoStartManagementActivity",
                            // 部分 HyperOS 版本的路径
                            "com.miui.securitycenter" to
                                "com.miui.powercenter.PowerCenterActivity",
                        )

                        for ((pkg, cls) in miuiTargets) {
                            try {
                                val intent = Intent().apply {
                                    component = ComponentName(pkg, cls)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                opened = true
                                break
                            } catch (_: Exception) {}
                        }

                        if (!opened) {
                            // 非 MIUI 或路径变了，降级到 App 详情页
                            openAppDetails()
                        }
                        result.success(null)
                    }

                    // ── 打开 App 系统详情页 ──────────────────────────
                    "openBatterySettings" -> {
                        openAppDetails()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun openAppDetails() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}