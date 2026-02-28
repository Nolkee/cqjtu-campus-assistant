# 修复 flutter_local_notifications 在 release 包中 Gson 泛型被 R8 裁掉的问题
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepattributes Signature
-keepattributes *Annotation*

# 保留 flutter_local_notifications 的通知模型类
-keep class com.dexterous.** { *; }