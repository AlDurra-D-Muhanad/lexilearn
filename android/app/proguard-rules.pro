# R8 / ProGuard rules for the lexilearn release build.
#
# WHY THIS FILE EXISTS AT ALL
# ---------------------------
# `android/app/build.gradle.kts` lists this file in `proguardFiles(...)`, and Gradle
# fails the release build outright if a listed file is missing. It must exist even
# when it carries no rules.
#
# It is also picked up automatically, without being listed: the Flutter Gradle
# plugin adds `<module>/proguard-rules.pro` to the release build type when the file
# exists -- see FlutterPlugin.kt:223-226 in
# C:\Flutter\flutter\packages\flutter_tools\gradle\src\main\kotlin\FlutterPlugin.kt.
# Listing it as well is therefore redundant but harmless; it is listed explicitly so
# the dependency does not live inside the Flutter SDK.
#
# WHAT IS ALREADY COVERED WITHOUT ANY RULE HERE
# ---------------------------------------------
#   * `proguard-android-optimize.txt` -- the Android default keep set. The Flutter
#     Gradle plugin adds it at FlutterPlugin.kt:219-221.
#   * `flutter_proguard_rules.pro` -- the Flutter plugin's own rules, added at
#     FlutterPlugin.kt:222. That file already carries the `-dontwarn io.flutter.**`
#     and the `FlutterPlugin` implementors keep.
#   * `io.flutter.plugins.GeneratedPluginRegistrant` -- annotated `@Keep`, so R8 keeps
#     it without a rule. See android/app/src/main/java/io/flutter/plugins/
#     GeneratedPluginRegistrant.java:14.
#   * `com.lexilearn.lexilearn.MainActivity` -- reachable from AndroidManifest.xml,
#     so it is a root and is never shrunk. It subclasses FlutterActivity and adds
#     no reflection.
#   * Multidex keeps (`FlutterLoader`, `PathUtils`) are NOT needed: this module sets
#     minSdk = 24, and legacy multidex only applies below API 21.
#
# The app performs no reflection of its own. If a future plugin ever does, add its
# rule here -- and prove it was needed by watching the build succeed without it.