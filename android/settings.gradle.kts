pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // 国内镜像优先（google()/mavenCentral() 直连在境内会长时间无响应甚至卡死）
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/central")
        maven("https://maven.aliyun.com/repository/gradle-plugin")
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    // ⚠️ PREFER_SETTINGS 会忽略工程内声明的仓库（含 Flutter 插件的引擎仓库），
    //    必须在这里手动补 https://storage.googleapis.com/download.flutter.io，
    //    否则报 Could not find io.flutter:arm64_v8a_debug:1.0.0-<engine-hash>
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        // 国内镜像（境外 storage.googleapis.com 经代理仅 ~130KB/s）
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/central")
        maven("https://storage.flutter-io.cn/download.flutter.io")
        google()
        mavenCentral()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
