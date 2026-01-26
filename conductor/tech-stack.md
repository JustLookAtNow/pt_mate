# Technology Stack

## Core Technologies
- **Programming Language**: Dart
- **Framework**: Flutter (Material Design 3)

## State Management & Architecture
- **State Management**: Provider
- **Service Layer**: Custom services and adapters for site communication and download management.

## Networking & Data
- **HTTP Client**: Dio (for API requests and file downloads)
- **Local Storage**: 
    - `shared_preferences`: For application settings and non-sensitive metadata.
    - `flutter_secure_storage`: For encrypted storage of sensitive information (Passkeys, passwords).

## Platforms
- **Mobile**: Android, iOS
- **Desktop**: Linux, macOS, Windows
- **Note**: Web is currently NOT a supported platform for deployment.

## Key Libraries & Tools
- **Logging**: `logger`
- **Dependency Injection**: `get_it`
- **UI Components**: `flutter_svg`, `flutter_markdown`, `flutter_colorpicker`, `dynamic_color`
- **Security**: `dart_jsonwebtoken`, `crypto`
- **Integration**: `url_launcher`, `package_info_plus`, `share_plus`, `permission_handler`
