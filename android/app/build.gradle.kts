import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.teacodeman.yanxin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        // 默认是正式包 id；走查机上都装着正式包（versionCode 更高、签名也不同），
        // 直接 `adb install -r` 会 INSTALL_FAILED_VERSION_DOWNGRADE / 签名冲突，**强行装会丢账本**。
        // 所以留一个 QA 侧装口子：`ORG_GRADLE_PROJECT_qaAppId=com.teacodeman.yanxin.qa flutter build apk --debug`
        // 装上后是**并列的第二份 App**（独立数据目录），走查完 `adb uninstall` 即可，不碰用户数据。
        applicationId = (project.findProperty("qaAppId") as String?) ?: "com.teacodeman.yanxin"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // F8.1 ABI 瘦身：**正式包只打 ARM**（真机全是 ARM）。
        // 依据：ML Kit 的 `libmlkit_google_ocr_pipeline.so` 每个 ABI 约 6–11 MB，
        //       x86_64 那份（11 MB）在手机上永远用不到 —— 只为模拟器存在。
        // ⚠️ AGP 的 `ndk.abiFilters` 在 **buildType 层是并集**（实测：defaultConfig 给
        //    arm64+v7a、buildType 只给 arm64，最终 APK 仍是 arm64+v7a）→ 所以 debug 里
        //    追加 x86_64 是"加"不是"换"；release 不追加 → 正好只剩 defaultConfig 这两项。
        ndk {
            abiFilters.clear()
            abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a"))
        }
    }

    // ⚠️ `signingConfigs` 必须声明在 `buildTypes` **之前**：
    //    `buildTypes.release { }` 的 lambda 在**配置阶段立即执行**，里面
    //    `signingConfigs.getByName("release")` 会在 signingConfig 注册前求值 →
    //    "SigningConfig with name 'release' not found."（连 debug 构建都在配置阶段挂掉）。
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        debug {
            // 模拟器（x86_64）要能跑：debug 补回 x86_64，别让它跟正式包一起被裁掉。
            // （与 defaultConfig 是**并集**，所以这里只写要额外加的那一项。）
            ndk {
                abiFilters.add("x86_64")
            }
        }
        release {
            // 有 `android/key.properties` 时用正式签名；没有（如 clone 仓库的机器）回退
            // debug 签名，保证 `flutter build apk --release` 仍能跑通。
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // ⚠️ F8.1 真机实测（2026-10-24）：Flutter 的 release 构建**默认开 R8**，
            //    而 R8 会把 ML Kit 内部依赖的组件/泛型签名裁掉 → 端上识别在**release 包里**
            //    必抛 `NullPointerException: … Object.getClass() on a null object reference`
            //    （同一张图在 debug 包里识别正常，30 行 / 375 ms）。
            //    这里先关掉压缩/混淆（与 debug 行为一致，最稳）；
            //    将来要瘦身，改成保留 ML Kit 的 keep 规则再测，别直接开回来。
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // F8.1 截图记账：ML Kit 中文文字识别。
    // ⚠️ 这是 **bundled** 变体 —— 模型随 APK（约几 MB/ABI），**不做运行时下载**，
    //    也不需要 Google Play 服务（国产 ROM / 无 GMS 设备同样可用）。
    //    因此 release 包**仍然不需要 `INTERNET` 权限**，「不联网」这条卖点保持不变。
    // 数字 / ¥ / 英文商户名由同一个中文模型识别，不必再引 latency 模型。
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
}

flutter {
    source = "../.."
}
