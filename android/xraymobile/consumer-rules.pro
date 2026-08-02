# JNI uses statically named entry points and looks these classes/methods up by name.
-keep class org.xrayrust.mobile.XrayCore { *; }
-keep class org.xrayrust.mobile.XrayCoreException { *; }
-keep class org.xrayrust.mobile.SocketProtector { *; }
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

