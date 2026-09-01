import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.debrify.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    // Flutter 3.44 flipped the packaging default to extractNativeLibs=false,
    // which stores the .so files uncompressed. That is Google's recommendation
    // — mmap'd straight from the APK, so LESS space on the device and a faster
    // start — but it nearly doubles the DOWNLOAD (85MB -> 160MB universal),
    // and Debrify ships its APK by hand through GitHub, where the download is
    // the number users see. Keep the pre-upgrade behaviour until that trade is
    // deliberately made; the alternative worth considering is --split-per-abi.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    // JNI shim over the prebuilt ten-vad neural VAD (subtitle auto-sync).
    // Plain C, no STL; ABIs without a prebuilt produce no library and the
    // feature falls back to energy features at runtime.
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.debrify.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resValue("string", "app_name", "Debrify")
        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_STL=none")
            }
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // JVM unit tests (subtitle auto-sync aligner) — run via :app:testDebugUnitTest
    testImplementation("junit:junit:4.13.2")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.media3:media3-exoplayer:1.8.0")
    implementation("androidx.media3:media3-exoplayer-dash:1.8.0")
    // HLS for IPTV (.m3u8) — DefaultMediaSourceFactory finds it by reflection.
    // Was only present transitively via the video_player plugin; pin it so the
    // native players don't silently lose HLS if that plugin ever goes away.
    implementation("androidx.media3:media3-exoplayer-hls:1.8.0")
    implementation("androidx.media3:media3-ui:1.8.0")
    implementation("androidx.media3:media3-session:1.8.0")
    implementation("org.jellyfin.media3:media3-ffmpeg-decoder:1.8.0+1")

    // Glide for image loading
    implementation("com.github.bumptech.glide:glide:4.16.0")

    // SAF tree handling for the custom download-folder feature
    implementation("androidx.documentfile:documentfile:1.0.1")
}
