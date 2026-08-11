# Flutter-specific ProGuard rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Geolocator
-keep class com.baseflow.geolocator.** { *; }

# Camera
-keep class io.flutter.plugins.camera.** { *; }

# Sensors Plus
-keep class dev.fluttercommunity.plus.sensors.** { *; }

# Permission Handler
-keep class com.baseflow.permissionhandler.** { *; }

# Keep annotations
-keepattributes *Annotation*

# Keep native methods
-keepclassmembers class * {
    native <methods>;
}

# Suppress warnings for common third-party libraries
-dontwarn com.google.**
-dontwarn javax.**
-dontwarn org.conscrypt.**
