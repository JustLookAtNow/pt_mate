# PT Mate（PT伴侣）

[English](./README.md)

基于 Flutter（Material Design 3）开发的私有种子站点客户端，支持多种 PT 站点的种子浏览、搜索和下载管理。

📣 官方交流群（Telegram）：[加入 PT Mate 官方交流群](https://t.me/pt_mate)

## 功能概览

- 种子浏览、搜索、详情、收藏、批量操作
- 多网站聚合搜索
- 下载器集成（qBittorrent / Transmission）
- 本地中转下载
- 数据备份与恢复（含 WebDAV）
- Cookie Cloud 同步与免密批量配置

## 当前支持的网站类型

- `Gazelle`
- `M-Team`
- `NexusPHP`
- `NexusPHPWeb`
- `RousiPro`
- `Unit3D`

## 当前支持的网站

以下清单基于 `assets/sites/*.json`（共 37 个）：

- `Gazelle`（1）：DIC Music
- `M-Team`（1）：M-Team
- `NexusPHP`（13）：藏宝阁、天枢、自由农场、好学、垃圾堆、幸运、momentpt、PTFans、PT GTK、PTSKit、PTZone、肉丝、织梦
- `NexusPHPWeb`（20）：AFUN、末日、Audiences、比特校园、财神、FRDS、HDDolby、HDFans、麒麟、HHanClub、老师、OurBits、ptt、青蛙、SSD、TTG、U2Share、UBits、星陨阁、猪猪
- `RousiPro`（1）：肉丝Pro(beta)
- `Unit3D`（1）：MonikaDesign

## 截图预览

<p align="center">
  <img src="screenshots/1.png" width="600" alt="截图1">
  <img src="screenshots/2.jpg" width="300" alt="截图2">
  <img src="screenshots/3.jpg" width="300" alt="截图3">
</p>

## Cookie Cloud 同步与安全警示

PT Mate 支持 **Cookie Cloud** 同步功能，该功能允许您将桌面浏览器中已登录的 PT 站点的 Cookie 自动/手动同步至移动端的 PT Mate，免去在手机上繁琐输入 Cookie 的不便，并支持基于 Presets 的批量一键站点导入与更新。

> [!CAUTION]
> ### ⚠️ 极其重要的安全与封号风险警示（请务必仔细阅读！）
>
> Cookie 是您在各大 PT 站点上的唯一**身份凭证**。泄漏 Cookie 相当于将账号的完全控制权拱手让人。开启本功能前，请务必完全知晓并同意以下安全与封号风险：
>
> 1. **严禁使用不可信的公共 Cookie Cloud 服务器**
>    - 公共服务器的运营者或恶意攻击者极易通过服务器日志或数据库漏洞截获您的 Cookie。
>    - **强烈建议**：仅使用您自己搭建的、受信任的私有 Cookie Cloud 服务器（例如通过 Docker 部署在您的 NAS、VPS 等私有设备上）。
> 2. **封号风险（异地/多 IP 访问限制）**
>    - 许多 PT 站点有非常严苛的安全风控策略，限制同一账号在短时间内出现异地或多 IP 登录（如手机流量与家用宽带 IP 冲突）。
>    - 当 PT Mate 使用通过 Cookie Cloud 同步来的 Cookie，在移动网络（4G/5G）或异地网络发起请求时，可能会触发站点的**“账号分享”或“异地登录劫持”监测，从而导致账号被永久封禁**。
>    - **安全建议**：如果您在户外或非家庭宽带网络环境下使用 PT Mate，请谨慎开启或使用相关站点的自动刷新/同步功能；对风控极严的站点，请谨慎使用或配置代理。
> 3. **传输加密不等于绝对安全**
>    - 尽管 Cookie Cloud 采用了客户端加密（UUID + 密码混淆 MD5 派生密钥进行 AES 加密），但如果您的 UUID 和密码强度过低，仍有被暴力破解的可能。请务必设置高强度的同步密码。
> 4. **范围超出预期风险（不仅同步 PT 站 Cookie）**
>    - 在默认配置下，浏览器 Cookie Cloud 插件会**无差别同步浏览器中所有网站的 Cookie**（包括但不限于您的邮箱、网银、社交媒体或购物网站）。
>    - **安全建议**：在浏览器的 Cookie Cloud 插件设置中，务必配置域名过滤黑白名单，仅允许同步 PT 相关的域名，避免无关的高价值敏感 Cookie 泄露到云端。
> 5. **操作系统限制与明文存储风险**
>    - 尽管本软件已竭尽全力调用系统底层安全区域（Keychain/Keystore）加密存储配置，但是在某些 Linux 操作系统或无图形桌面的环境下，受底层机制限制，软件可能仍会以**明文形式**保存您的 Cookie Cloud 配置和密码。
> 6. **备份导出与云端上报风险**
>    - 本软件的备份导出功能以及自动同步到 WebDAV 备份的功能中**包含完整的 Cookie Cloud 配置**。
>    - **安全建议**：请妥善保管导出的备份 JSON 文件；配置 WebDAV 服务器时，**必须确保使用 HTTPS 加密传输链路**，防止备份文件在网络传输中被劫持或嗅探。
> 7. **运行期内存读取风险**
>    - 当本软件运行时，系统内存中必然会以**明文状态**加载并处理您站点的 Cookie 及 Cookie Cloud 配置信息。如果您的运行设备已被恶意软件（木马、间谍软件或越狱后拥有 Root 权限的进程）控制，这些信息可能会从进程内存中被直接窃取。
>
> **一旦您启用此功能，即代表您已充分理解并愿意自行承担由 Cookie 泄露、异地登录或多 IP 冲突导致的任何站点封号、封禁及其他资产损失风险。**

## 快速开始

```bash
flutter pub get
flutter run
```

## iOS 侧载源

SideStore：
[添加 PT Mate Source](https://intradeus.github.io/http-protocol-redirector?r=sidestore://source?url=https://raw.githubusercontent.com/JustLookAtNow/pt_mate/refs/heads/master/altsource/AltSource.json)

直接源地址：

```text
https://raw.githubusercontent.com/JustLookAtNow/pt_mate/refs/heads/master/altsource/AltSource.json
```

## 文档

- [文档目录](./docs/README.md)
- [使用指南](./docs/USER_GUIDE.md)
- [开发指南](./docs/DEVELOPMENT_GUIDE.md)
- [网站配置指南](./docs/SITE_CONFIGURATION_GUIDE.md)
- [API 文档目录](./docs/api)

## 许可证

MIT License，详见 [LICENSE](./LICENSE)。

## Star 趋势

[![Star History Chart](https://api.star-history.com/svg?repos=JustLookAtNow/pt_mate&type=Date)](https://star-history.com/#JustLookAtNow/pt_mate&Date)
