import java.util.Properties

// Dejavoo Tap to Pay (TOP SDK), as in the AURA POS app (pos-app android/build.gradle).
// Resolved once here; app/build.gradle.kts reads rootProject.extra["dejavoo*"].
// android/local.properties (never committed):
//   dejavoo.env=sandbox            (default) or prod
//   sandbox: dejavoo.aws.accessKey, dejavoo.aws.secretKey,
//            dejavoo.maven.url (optional, defaults to the testing repo)
//   prod:    dejavoo.prod.aws.accessKey, dejavoo.prod.aws.secretKey, dejavoo.prod.maven.url,
//            dejavoo.prod.aar (file name of the production SoftPos AAR in android/app/libs)
// Switch: dejavoo.top.enabled in android/gradle.properties (override per build with
// -Pdejavoo.top.enabled=false). Sandbox without credentials builds without the SDK (Tap to Pay
// then answers TOP_NOT_CONFIGURED). Prod never falls back: anything missing fails the build,
// so a test SDK can't ship as live.
val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.reader(Charsets.UTF_8).use { load(it) }
}
val dejavooTopWanted = (findProperty("dejavoo.top.enabled") ?: "true").toString().trim().toBoolean()
val dejavooEnv = localProperties.getProperty("dejavoo.env", "sandbox").trim()
if (dejavooTopWanted && dejavooEnv !in listOf("sandbox", "prod")) {
    throw GradleException("dejavoo.env must be 'sandbox' or 'prod', got '$dejavooEnv'")
}
val dejavooProd = dejavooEnv == "prod"
fun dejavooKey(name: String): String? =
    localProperties.getProperty((if (dejavooProd) "dejavoo.prod." else "dejavoo.") + name)?.trim()?.ifEmpty { null }

val dejavooAccessKey = dejavooKey("aws.accessKey")
val dejavooSecretKey = dejavooKey("aws.secretKey")
val dejavooMavenUrl = dejavooKey("maven.url") ?: (if (dejavooProd) null else "s3://denovo-android.s3.amazonaws.com/testing")
if (dejavooTopWanted && dejavooProd) {
    val missing = listOf("aws.accessKey", "aws.secretKey", "maven.url", "aar").filter { dejavooKey(it) == null }
    if (missing.isNotEmpty()) {
        throw GradleException(
            "dejavoo.env=prod but local.properties is missing: " + missing.joinToString { "dejavoo.prod.$it" })
    }
}
val dejavooTopEnabled =
    dejavooTopWanted && dejavooAccessKey != null && dejavooSecretKey != null && dejavooMavenUrl != null

extra["dejavooTopWanted"] = dejavooTopWanted
extra["dejavooTopEnabled"] = dejavooTopEnabled
extra["dejavooEnv"] = dejavooEnv
extra["dejavooSdk"] = if (dejavooProd) "com.denovo:topliteapp-PROD:3.0.5.6" else "com.denovo:topliteapp:2.5.0.37"
extra["dejavooAar"] = (if (dejavooProd) dejavooKey("aar") else "SoftPos-v1.3.66.7-Debug_Test.aar") ?: ""

allprojects {
    repositories {
        google()
        mavenCentral()
        // Dejavoo TOP SDK repo for the selected environment (see above).
        if (dejavooTopEnabled) {
            maven {
                url = uri(dejavooMavenUrl!!)
                credentials(AwsCredentials::class) {
                    accessKey = dejavooAccessKey
                    secretKey = dejavooSecretKey
                }
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
