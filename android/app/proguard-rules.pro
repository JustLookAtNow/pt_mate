# flutter_secure_storage may include the full logical key in Android Log on
# cryptographic failures. Release builds retain only PT Mate's sanitized Dart
# audit file and strip every android.util.Log call, including dependency logs.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
    public static int w(...);
    public static int e(...);
    public static int wtf(...);
}
