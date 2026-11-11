plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Dejavoo Tap to Pay (TOP SDK), resolved in android/build.gradle.kts; same setup as the AURA POS app.
val dejavooTopEnabled = rootProject.extra["dejavooTopEnabled"] as Boolean
val dejavooTopWanted = rootProject.extra["dejavooTopWanted"] as Boolean
val dejavooEnv = rootProject.extra["dejavooEnv"] as String
val dejavooSdk = rootProject.extra["dejavooSdk"] as String
val dejavooAar = rootProject.extra["dejavooAar"] as String
if (dejavooTopEnabled && !file("libs/$dejavooAar").exists()) {
    throw GradleException("Dejavoo SoftPos AAR not found: android/app/libs/$dejavooAar")
}
println(
    "Dejavoo Tap to Pay (TOP SDK): " + when {
        dejavooTopEnabled -> "INCLUDED, ${dejavooEnv.uppercase()} ($dejavooSdk + $dejavooAar)"
        dejavooTopWanted -> "NOT included (no Dejavoo credentials in android/local.properties)"
        else -> "NOT included (dejavoo.top.enabled=false)"
    }
)
if (dejavooTopEnabled && dejavooEnv == "prod") {
    println("Dejavoo PROD: only release-signed, finalized APKs can register; debug builds will be rejected.")
}

android {
    namespace = "tech.aura.aura_gym"
    // 37: Dejavoo's prod SoftPos AAR declares minCompileSdk=37 (only needed with Tap to Pay).
    compileSdk = if (dejavooTopEnabled) 37 else flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }

    sourceSets {
        // TopPaymentHandler / ThemeApplication: the real ones with the SDK, stubs without it.
        getByName("main").java.srcDirs(if (dejavooTopEnabled) "src/top/java" else "src/notop/java")
    }

    defaultConfig {
        applicationId = "tech.aura.aura_gym"
        // 28: Dejavoo's SoftPos AAR requires Android 9+. Without Tap to Pay, Flutter's default
        // keeps older tablets (e.g. MI PAD 4 on 8.1) installable.
        minSdk = if (dejavooTopEnabled) 28 else flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Read by MainActivity ("topEnvironment") and TopPaymentHandler diagnostics.
        buildConfigField("String", "DEJAVOO_ENV", "\"${if (dejavooTopEnabled) dejavooEnv else "none"}\"")
        buildConfigField(
            "String", "DEJAVOO_SDK", "\"${if (dejavooTopEnabled) "$dejavooSdk + $dejavooAar" else "none"}\""
        )
    }

    buildTypes {
        release {
            // TODO: release keystore. Debug keys for now, so `flutter run --release` works.
            // A prod Tap to Pay APK must be release-signed AND finalized with Dejavoo's tool.
            signingConfig = signingConfigs.getByName("debug")
            // Dejavoo's TOP SDK rules (include -dontshrink), only for builds with the SDK.
            if (dejavooTopEnabled) {
                proguardFile("proguard-top.pro")
            }
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

dependencies {
    // Dejavoo Tap to Pay (TOP SDK) for the selected environment, as in the POS app.
    if (dejavooTopEnabled) {
        implementation(dejavooSdk) {
            exclude(group = "com.denovo", module = "invoke-dvpay-lite")
        }
        implementation(files("libs/$dejavooAar"))
        // Dependencies the Dejavoo team asked for alongside the production SDK (2026-10-12).
        implementation("org.aspectj:aspectjrt:1.9.25")
        val roomVersion = "2.7.2"
        implementation("androidx.room:room-runtime:$roomVersion")
        annotationProcessor("androidx.room:room-compiler:$roomVersion")
        implementation("androidx.startup:startup-runtime:1.1.0")
        implementation("androidx.work:work-runtime:2.9.0")
        implementation("androidx.work:work-multiprocess:2.9.0")
        implementation("com.google.guava:guava:31.1-android")
    }
}

// Dejavoo's TOP sample excludes org.json (Android already provides it).
if (dejavooTopEnabled) {
    configurations.all {
        exclude(group = "org.json", module = "json")
    }
}
