# Dejavoo Tap to Pay (TOP SDK) rules, exactly as sent by the Dejavoo team for production (2026-10-12).
# Only applied when the TOP SDK is in the build (see app/build.gradle), so -dontshrink doesn't
# affect builds without it.

-dontshrink
-keep class sun.misc.** { *; }

-keep class com.cloudpos.** { *; }
-dontwarn com.cloudpos.**
-keepattributes InnerClasses

##---------------Begin: proguard configuration for Gson  ----------
# Gson uses generic type information stored in a class file when working with fields. Proguard
# removes such information by default, so configure it to keep all of it.
##-keepattributes Signature

-keep class com.denovo.app.top.business.webservice.ApiInterface{ *; }
-keep class com.denovo.app.top.business.webservice.NetworkCall{ *; }
-keep class com.denovo.app.top.business.crypto.AESHelper{ *; }
-keep class com.denovo.app.top.device.tap_on_phone.detect_tap.CardTapManager{ *; }
-keep class com.denovo.app.top.utility.Constants{ *; }
-keep class com.denovo.app.top.business.webservice.ApiPath{ *; }
-keep class com.denovo.app.top.business.tap_on_phone.host_config.TopHostManager{ *; }
-keep class com.denovo.app.top.business.tap_on_phone.host_config.TopTxnManager{ *; }
-keep class com.denovo.app.top.business.tap_on_phone.checksum.CheckSumValidator{ *; }
# Gson specific classes
-keep class sun.misc.Unsafe.** { *; }
-keep class com.google.gson.stream.** { *; }

# Application classes that will be serialized/deserialized over Gson
-keep class com.denovo.app.top.business.models.** { *; }
-keep public class com.wizarpos.jni.* { public *; }
-keep class com.wizarpos.security.injectkey.* { *; }
-keep class com.denovo.app.top.device.emv.* { *; }
-keep class com.wizarpos.security.injectkey.aidl.* { *; }

-keep class com.denovo.app.invokeiposgo.models.** { *; }
-keep class com.denovo.top.epay.hppDataResult.models.** { *; }

#SoftPos-v1.3.66.4-Debug_Test
-keep class com.cardtek.softpos.**{*;}
-keep class orion.acquila.libra.**{*;}


# Required for Retrofit/OkHttp
-dontwarn javax.annotation.**
-dontwarn org.codehaus.mojo.animal_sniffer.IgnoreJRERequirement
-keepattributes *Annotation*, Signature, Exceptions

# This optimization conflicts with how Retrofit uses proxy objects without concrete implementations
-optimizations !method/removal/parameter

# A resource is loaded with a relative path so the package of this class must be preserved.
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

-dontwarn retrofit2.**
-keep class retrofit2.** { *; }
-keepattributes Signature
-keepattributes Exceptions
-keepattributes *Annotation*

-keepclasseswithmembers class * {
    @retrofit2.http.* <methods>;
}
-keepclassmembernames interface * {
        @retrofit.http.* <methods>;
}
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn okhttp3.**

-dontwarn okio.**
-dontwarn sun.misc.Unsafe

### Moshi
-dontwarn com.squareup.moshi.**
-keep class com.squareup.moshi.** { *; }
-keep interface com.squareup.moshi.** { *; }
-keep @com.squareup.moshi.JsonQualifier interface *

-keepclasseswithmembers class * {
    @com.squareup.moshi.* <methods>;
}
-keep @com.squareup.moshi.JsonQualifier interface *
-keepclassmembers class * {
    @com.squareup.moshi.FromJson <methods>;
    @com.squareup.moshi.ToJson <methods>;
}

# SoftPOS, Firebase, Integrity, AWS, and other required dontwarn rules
-dontwarn com.cardtek.softpos.kernel.L2KernelNative2Java
-dontwarn com.google.android.play.core.integrity.IntegrityManager
-dontwarn com.google.android.play.core.integrity.IntegrityManagerFactory
-dontwarn com.google.android.play.core.integrity.IntegrityTokenRequest$Builder
-dontwarn com.google.android.play.core.integrity.IntegrityTokenRequest
-dontwarn com.google.android.play.core.integrity.IntegrityTokenResponse
-dontwarn com.google.firebase.auth.**
-dontwarn com.google.firebase.firestore.**
-dontwarn com.softpos.pin.sdk.**
-dontwarn com.sun.**
-dontwarn dalvik.system.VMDebug
-dontwarn java.awt.**
-dontwarn javax.naming.**
-dontwarn javax.security.auth.**
-dontwarn javax.smartcardio.**
-dontwarn org.ietf.jgss.**
-dontwarn software.amazon.awssdk.**
-dontwarn sun.**
-dontwarn orion.acquila.libra.**
-dontwarn org.aspectj.lang.JoinPoint$StaticPart
-dontwarn org.aspectj.lang.JoinPoint
-dontwarn org.aspectj.lang.ProceedingJoinPoint
-dontwarn org.aspectj.lang.Signature
-dontwarn org.aspectj.lang.reflect.MethodSignature
-dontwarn org.aspectj.runtime.reflect.Factory
