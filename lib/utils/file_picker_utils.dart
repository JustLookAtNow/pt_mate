/// Converts picker locations to paths while preserving Android document URIs.
String filePickerLocation(Uri uri) =>
    uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
