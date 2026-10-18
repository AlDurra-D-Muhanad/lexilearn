import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing.
//
// `android/key.properties` and `android/app/upload-keystore.jks` are both covered by
// android/.gitignore, so a fresh clone has neither. That is exactly the CI case: the
// workflow builds the bundle on a public repo where the upload key must never exist, and
// the release build type below falls back to debug signing so the build still succeeds.
//
// A key.properties that EXISTS but is broken must not fall back silently -- that is how a
// Play release ends up signed with the debug key and rejected days later. So that case
// raises at configuration time, with the resolved path in the message.
val keystoreProperties = Properties().apply {
    val propertiesFile = rootProject.file("key.properties")
    if (propertiesFile.exists()) propertiesFile.inputStream().use { load(it) }
}
// `project`, not `rootProject`: key.properties sits in android/ but the keystore sits in
// android/app/, and project.file() resolves relative paths against the module directory,
// so storeFile=upload-keystore.jks finds android/app/upload-keystore.jks.
val releaseStoreFile = keystoreProperties.getProperty("storeFile")?.let { project.file(it) }
if (keystoreProperties.containsKey("storeFile") && releaseStoreFile?.isFile != true) {
    throw GradleException(
        "android/key.properties names storeFile=$releaseStoreFile, which is not a file. " +
            "Restore the upload keystore, or delete key.properties entirely to fall back " +
            "to debug signing.",
    )
}

android {
    namespace = "com.lexilearn.lexilearn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.lexilearn.lexilearn"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Both come from `version: <name>+<code>` in pubspec.yaml. The +code is the Play
        // versionCode and MUST be incremented on every single upload.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Created unconditionally so getByName("release") below always resolves. It is
        // only ever attached to the release build type when an upload keystore was found.
        create("release") {
            if (releaseStoreFile != null) {
                storeFile = releaseStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Debug signing when there is no upload key, so a fresh clone -- and CI --
            // can still run `flutter build appbundle`. With a key present, the upload
            // key wins. Both branches are exercised by the release task's CI job.
            signingConfig =
                if (releaseStoreFile != null) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }

            // R8. These two lines are NOT what turns shrinking on: the Flutter Gradle
            // plugin already sets both on the release build type (FlutterPlugin.kt:217-218
            // in the Flutter SDK) and contributes proguard-android-optimize.txt plus
            // flutter_proguard_rules.pro (FlutterPlugin.kt:219-222). They are repeated here
            // so this module's release configuration does not silently depend on the
            // inside of the Flutter SDK.
            isMinifyEnabled = true
            isShrinkResources = true

            // Only this module's own rules; the Android and Flutter defaults are already
            // contributed by the Flutter plugin, and listing them again would feed R8 the
            // same file twice. This file MUST exist -- Gradle fails on a missing one.
            proguardFiles("proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}