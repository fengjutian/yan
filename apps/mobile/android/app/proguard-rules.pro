# R8 规则：Flutter 引擎与各插件的 consumer rules 已由 aar 提供，
# 这里只补 Flutter 主入口和反射相关的保护，避免 release 混淆后
# 出现 "Platform channel ... not found" 或 ML Kit 回调丢失。
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# 原生相机（Camera2 专业模式）通过 JNI/反射回调，保留入口类。
-keep class com.yan.ai.ai_image_studio.** { *; }

# Google ML Kit 依赖反射加载可选的模型实现。
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.mlkit.**

# Flutter 引擎里的 Play Core 延迟组件（deferred components）在未集成
# play-core 时会缺少这些类；本 App 不用延迟组件，直接忽略即可。
# 规则来源：build/app/outputs/mapping/release/missing_rules.txt
-dontwarn com.google.android.play.core.**

# 保留行号信息，便于线上崩溃定位；不保留源文件名。
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
