plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val secureStorageTestApplicationIdSuffixes = mapOf(
    "oaepGcm" to ".securestoragetest.oaepgcm",
    "pkcs1Gcm" to ".securestoragetest.pkcs1gcm",
    "pkcs1Cbc" to ".securestoragetest.pkcs1cbc",
)
val secureStorageTestProfile = providers
    .gradleProperty("secureStorageTestProfile")
    .orNull
    ?.trim()
    ?.takeIf { it.isNotEmpty() }
if (secureStorageTestProfile != null &&
    secureStorageTestProfile !in secureStorageTestApplicationIdSuffixes
) {
    throw GradleException(
        "Unsupported secureStorageTestProfile '$secureStorageTestProfile'. " +
            "Expected one of: ${secureStorageTestApplicationIdSuffixes.keys.joinToString()}.",
    )
}
val secureStorageTestApplicationIdSuffix =
    secureStorageTestProfile?.let(secureStorageTestApplicationIdSuffixes::getValue).orEmpty()

android {
    namespace = "com.github.justlookatnow.ptmate"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.github.justlookatnow.ptmate"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("String", "SECURE_STORAGE_TEST_PROFILE", "\"\"")
        buildConfigField("String", "SECURE_STORAGE_TEST_APPLICATION_ID_SUFFIX", "\"\"")
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = if (keystoreProperties["storeFile"] != null) file(keystoreProperties["storeFile"] as String) else null
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        debug {
            if (secureStorageTestProfile != null) {
                applicationIdSuffix = secureStorageTestApplicationIdSuffix
                buildConfigField(
                    "String",
                    "SECURE_STORAGE_TEST_PROFILE",
                    "\"$secureStorageTestProfile\"",
                )
                buildConfigField(
                    "String",
                    "SECURE_STORAGE_TEST_APPLICATION_ID_SUFFIX",
                    "\"$secureStorageTestApplicationIdSuffix\"",
                )
            }
        }
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // Release values are deliberately forced empty even if a test property was supplied.
            buildConfigField("String", "SECURE_STORAGE_TEST_PROFILE", "\"\"")
            buildConfigField("String", "SECURE_STORAGE_TEST_APPLICATION_ID_SUFFIX", "\"\"")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    testImplementation("junit:junit:4.13.2")
}
