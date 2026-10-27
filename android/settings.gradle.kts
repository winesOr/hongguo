pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            // Java 的 Properties.load(InputStream) 固定按 ISO-8859-1 解码，
            // SDK 路径含中文（如外置盘 /Volumes/外置SSD/开发/工具/...）会被解成乱码，
            // 因此显式用 UTF-8 Reader 读取。
            file("local.properties").reader(Charsets.UTF_8).use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
