# Vendor SDK uses reflection and firmware-provided JNI names.
-keep class com.senter.** { *; }
-keep class com.hsm.** { *; }
-keep class com.zebra.** { *; }
-dontwarn com.senter.**
-dontwarn com.hsm.**
-dontwarn com.zebra.**
-dontwarn android.device.**
