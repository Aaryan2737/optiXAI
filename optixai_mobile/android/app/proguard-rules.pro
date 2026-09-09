# Keep TFLite native bindings from being stripped by R8/ProGuard
-keep class org.tensorflow.** { *; }
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.**

# Keep Flutter plugin registrant
-keep class io.flutter.plugins.** { *; }
