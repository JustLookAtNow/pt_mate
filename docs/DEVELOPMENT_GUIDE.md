# 开发指南

## 项目结构

```text
lib/
├── app.dart
├── main.dart
├── models/
├── pages/
├── providers/
├── services/
├── utils/
└── widgets/
```

## 技术栈

- Flutter
- Provider
- Dio
- SharedPreferences
- FlutterSecureStorage

## 快速开始

### 环境要求
- Flutter SDK 3.0+
- Dart SDK 3.0+
- Android Studio / VS Code

### 安装依赖

```bash
flutter pub get
```

如新增网站配置，请运行：

```bash
./generate_sites_manifest.sh
```

可选：在 `.git/hooks/pre-commit` 添加自动更新脚本。

### 运行应用

```bash
flutter run
flutter run --release
```

### 构建 APK

```bash
flutter build apk --debug
flutter build apk --release
```

### 适配新网站
1. 新增网站配置到 `assets/sites/`
2. 运行 `./generate_sites_manifest.sh`
3. 验证新网站功能

详见：[网站配置指南](./SITE_CONFIGURATION_GUIDE.md)

## 配置说明

### 站点配置
- 支持多种站点类型（M-Team、NexusPHP、NexusPHPWeb、RousiPro、Unit3D）
- 支持自定义站点域名
- 使用 Passkey 身份验证
- 自动保存登录状态

### 下载器配置（qBittorrent / Transmission）
- 支持多个下载器实例
- 自动获取分类和标签
- 支持本地中转下载模式

## 安全性

- 敏感信息（Passkey、密码）使用 FlutterSecureStorage 加密存储
- 日志不记录敏感信息
- 支持 HTTPS 证书验证

## 许可证

MIT License，详见 [LICENSE](../LICENSE)。
