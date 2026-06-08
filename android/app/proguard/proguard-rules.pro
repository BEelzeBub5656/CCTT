# MQTT Client — keep all classes (uses dynamic dispatch)
-keep class mqtt_client.** { *; }
-dontwarn mqtt_client.**

# Dart FFI — keep native bindings
-keep class dart.** { *; }
-dontwarn dart.**

# General
-keepattributes Signature
-keepattributes *Annotation*
