# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
#-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile

# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep native methods
-keepclassmembers class * {
    native <methods>;
}

# Keep Parcelable implementations
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep Serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep HTTP client classes
-keep class com.debrify.app.** { *; }
-keep class * extends java.net.HttpURLConnection { *; }

# Keep JSON parsing classes
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Keep Google Play Core classes (for Play Store features)
-keep class com.google.android.play.core.** { *; }
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }

# Suppress warnings for Google Play Core classes (not used in this app)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# Keep Flutter specific classes
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
-keep class io.flutter.embedding.android.** { *; }

# Keep all native methods
-keepclassmembers class * {
    native <methods>;
}

# Keep Parcelable implementations
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep Serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ============ TV Performance Optimizations ============

# Performance optimizations
-optimizationpasses 5
-allowaccessmodification
-dontpreverify

# ExoPlayer/Media3 rules for video playback performance
-keep class androidx.media3.** { *; }
-keep interface androidx.media3.** { *; }
-keepclassmembers class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# Keep Glide image loading library
-keep public class * implements com.bumptech.glide.module.GlideModule
-keep class * extends com.bumptech.glide.module.AppGlideModule {
 <init>(...);
}
-keep public enum com.bumptech.glide.load.ImageHeaderParser$** {
  **[] $VALUES;
  public *;
}
-keep class com.bumptech.glide.load.data.ParcelFileDescriptorRewinder$InternalRewinder {
  *** rewind();
}
-dontwarn com.bumptech.glide.**

# AndroidX TV specific optimizations
-keep class androidx.leanback.** { *; }
-dontwarn androidx.leanback.**

# Optimize native libraries for TV
-keepclasseswithmembernames class * {
    native <methods>;
}

# Remove logging for better performance in release
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}

# Keep Android TV specific classes
-keep class android.support.v17.leanback.** { *; }
-dontwarn android.support.v17.leanback.**

# ============ Debrify Custom App Classes ============
# Keep MainActivity - used by Flutter method channels
-keep class com.debrify.app.MainActivity { *; }
-keep class com.debrify.app.MainActivity$Companion { *; }

# Keep Activities launched by class name from Dart
-keep class com.debrify.app.tv.TorboxTvPlayerActivity { *; }
-keep class com.debrify.app.tv.AndroidTvTorrentPlayerActivity { *; }
-keep class com.debrify.app.tv.SeekFeedbackManager { *; }

# Keep download service and bridge
-keep class com.debrify.app.download.MediaStoreDownloadService { *; }
-keep class com.debrify.app.download.ChannelBridge { *; }

# Keep all inner classes and data classes
-keep class com.debrify.app.download.MediaStoreDownloadService$** { *; }
-keep class com.debrify.app.tv.AndroidTvTorrentPlayerActivity$** { *; }

# Keep method channel result implementations
-keepclassmembers class * {
    public void onSuccess(java.lang.Object);
    public void error(java.lang.String, java.lang.String, java.lang.Object);
    public void notImplemented();
}

# ============ Flutter Plugin Services ============
# Keep background_downloader plugin service (declared in AndroidManifest.xml)
-keep class background.downloader.DownloadWorkerService { *; }
-keep class background.downloader.** { *; }

# ============ Flutter Plugins (from GeneratedPluginRegistrant) ============
# Keep all Flutter plugin classes to prevent ProGuard issues
-keep class com.llfbandit.app_links.** { *; }
-keep class com.bbflight.background_downloader.** { *; }
-keep class dev.fluttercommunity.plus.connectivity.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class io.flutter.plugins.flutter_plugin_android_lifecycle.** { *; }
-keep class com.alexmercerind.media_kit_libs_android_video.** { *; }
-keep class com.alexmercerind.media_kit_video.** { *; }
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class com.fluttercavalry.saf_stream.** { *; }
-keep class com.aaassseee.screen_brightness_android.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class io.flutter.plugins.videoplayer.** { *; }
-keep class com.kurenai7968.volume_controller.** { *; }
-keep class dev.fluttercommunity.plus.wakelock.** { *; }

# Keep plugin registrant
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }