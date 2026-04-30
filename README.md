# PT Mate

[简体中文](./README.zh-CN.md)

A Flutter-based private tracker client built with Material Design 3. PT Mate supports torrent browsing, search, and download management across multiple PT site types.

📣 Official Telegram group: [Join the PT Mate community](https://t.me/pt_mate)

## Features

- Browse torrents, search, view details, favorite items, and perform bulk actions
- Aggregated search across multiple sites
- Downloader integration (`qBittorrent` / `Transmission`)
- Local relay download support
- Backup and restore, including WebDAV

## Supported Site Types

- `Gazelle`
- `M-Team`
- `NexusPHP`
- `NexusPHPWeb`
- `RousiPro`
- `Unit3D`

## Supported Sites

The following list is based on `assets/sites/*.json` (37 total):

- `Gazelle` (1): DIC Music
- `M-Team` (1): M-Team
- `NexusPHP` (13): 藏宝阁, 天枢, 自由农场, 好学, 垃圾堆, 幸运, momentpt, PTFans, PT GTK, PTSKit, PTZone, 肉丝, 织梦
- `NexusPHPWeb` (20): AFUN, 末日, Audiences, 比特校园, 财神, FRDS, HDDolby, HDFans, 麒麟, HHanClub, 老师, OurBits, ptt, 青蛙, SSD, TTG, U2Share, UBits, 星陨阁, 猪猪
- `RousiPro` (1): 肉丝Pro(beta)
- `Unit3D` (1): MonikaDesign

## Screenshots

<p align="center">
  <img src="screenshots/1.png" width="600" alt="Screenshot 1">
  <img src="screenshots/2.jpg" width="300" alt="Screenshot 2">
  <img src="screenshots/3.jpg" width="300" alt="Screenshot 3">
</p>

## Quick Start

```bash
flutter pub get
flutter run
```

## iOS Sideloading Source

SideStore:
[Add PT Mate Source](https://intradeus.github.io/http-protocol-redirector?r=sidestore://source?url=https://raw.githubusercontent.com/JustLookAtNow/pt_mate/refs/heads/master/altsource/AltSource.json)

Direct source URL:

```text
https://raw.githubusercontent.com/JustLookAtNow/pt_mate/refs/heads/master/altsource/AltSource.json
```

## Documentation

- [Documentation Index](./docs/README.md)
- [User Guide](./docs/USER_GUIDE.md)
- [Development Guide](./docs/DEVELOPMENT_GUIDE.md)
- [Site Configuration Guide](./docs/SITE_CONFIGURATION_GUIDE.md)
- [API Docs](./docs/api)

## License

MIT License. See [LICENSE](./LICENSE) for details.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=JustLookAtNow/pt_mate&type=Date)](https://star-history.com/#JustLookAtNow/pt_mate&Date)
