# Implementation Plan and Task List in Chinese

本计划详细阐述了在 **PT Mate** 中接入并支持 **Cookie Cloud** 同步与批量导入站点的技术方案。

---

## 目标描述

支持 **Cookie Cloud** 免密端到端加密同步协议，允许用户通过云端服务器一键拉取、解密并批量同步已有的 PT 站 Cookie。同时支持智能推荐一键导入新站点，实现移动端 PT 站点的零门槛维护。

---

## 用户审核要求

> [!IMPORTANT]
> 1. **数据安全性**：Cookie Cloud 的密码、UUID 和解密后的 Cookie 属于高度敏感隐私数据。方案中敏感凭据一律优先写入 `FlutterSecureStorage`（系统级安全存储），仅在安全存储不可用时才使用加密混淆后的降级存储。
> 2. **对已有站点的破坏防范**：同步过程中可能会覆盖已有站点的 Cookie。为了防止误操作导致原有 Cookie 丢失，在执行写入前会**自动备份**现有站点配置，并提供**同步预览确认界面**让用户手动挑选需要导入或更新的站点。
> 3. **三方库引入**：解密需要标准的 AES-CBC-PKCS7 算法与 EVP 字节派生算法。本方案提议在 `pubspec.yaml` 中引入成熟的 `encrypt: ^5.0.3`（其底层是 `pointycastle`）以确保算法安全和维护效率，避免手写低效不安全的底层解密代码。

---

## 开放性问题

1. **同步频率**：是否需要支持“后台自动定时同步”？
   * *建议*：第一期仅提供**手动一键同步**与**进入页面时自动同步**，避免不必要的后台能耗与后台任务复杂性。
2. **多套 Cookie Cloud 配置**：是否有用户需要配置多个 Cookie Cloud 服务器？
   * *建议*：大部分用户仅需要单套 Cookie Cloud 存储，因此只提供单套配置项，保持简洁（KISS原则）。

---

## 拟议的变更

### 1. 依赖变更
#### [MODIFY] [pubspec.yaml](file:///home/lee/projectSpace/m-team-flutter/flutter_application_m_team/pubspec.yaml)
* 引入 `encrypt: ^5.0.3` 支持标准的 CryptoJS 兼容解密逻辑。

---

### 2. 存储服务变更
#### [MODIFY] [storage_service.dart](file:///home/lee/projectSpace/m-team-flutter/flutter_application_m_team/lib/services/storage/storage_service.dart)
* 添加 Cookie Cloud 相关的安全键定义：
  * `cookieCloudUrl`（服务器地址，如 `https://cookiecloud.example.com`）
  * `cookieCloudUuid`（用户 UUID）
  * `cookieCloudPassword`（解密密码，保存在 `FlutterSecureStorage` 中）
* 添加对应的持久化读取与保存接口。

---

### 3. 同步与解密核心服务
#### [NEW] [cookie_cloud_service.dart](file:///home/lee/projectSpace/m-team-flutter/flutter_application_m_team/lib/services/network/cookie_cloud_service.dart)
* **网络拉取**：使用已有 `Dio` 实例发起 POST 请求拉取加密 payload。
* **密码学派生与解密**：
  * 实现基于 MD5 的 OpenSSL 兼容 `EVP_BytesToKey` 算法。
  * 提取 Base64 密文中的 Salt（盐），派生出 Key (32字节) 与 IV (16字节)。
  * 使用 `encrypt` 库解密出明文 JSON 数据。
* **数据比对与映射**：
  * 解析明文，将其整理为 `domain -> cookieString` 结构。
  * 读取本地所有 `SiteConfig`，通过 `baseUrl` 提取的 Host 与 Cookie Cloud 中的域名进行最佳模糊匹配（如匹配子域名或完全一致）。
  * 将站点划分为三类：
    1. **本地已配置**：可一键同步更新 Cookie。
    2. **未配置但可内置匹配**：在 PT Mate 内置站点列表（`SiteConfigService` 中有对应模板）中找到匹配，支持**零配置一键直接导入建站**。
    3. **未匹配的未知站点**：允许用户自定义指定模板导入。

---

### 4. 极佳视觉交互界面 (UI)
#### [NEW] [cookie_cloud_page.dart](file:///home/lee/projectSpace/m-team-flutter/flutter_application_m_team/lib/pages/cookie_cloud_page.dart)
设计一个高颜值、极具质感且带微动动画的同步管理页面：
* **表单卡片**：服务器地址、UUID、密码（支持明文切换），采用流畅过渡边框。
* **测试与同步按钮**：配有旋转 Loading 动画，使用 `Toastification` 抛出反馈。
* **同步数据预览确认列表（核心卡片）**：
  * 使用分栏 Tab 或分段列表展示：
    * **站点覆盖更新区**：列出本地已配置的站点，展示原 Cookie 是否过期，勾选一键覆盖。
    * **推荐一键添加区**：列出云端有但本地没有，且 PT Mate 内置模版支持的站点。展示精美的站点图标（从 `assets/sites_icon/` 获取），点击 `+` 即可直接生成站点。
    * **自定义导入区**：非内置站点域名，点击可快捷弹窗指派模版。
  * **一键同步/确认更新**按钮：置于底部，动画弹出。

#### [MODIFY] [settings_page.dart](file:///home/lee/projectSpace/m-team-flutter/flutter_application_m_team/lib/pages/settings_page.dart)
* 在“数据管理”或“网络设置”模块中，添加一个极富现代感的 `ListTile` 入口：“Cookie Cloud 同步”。支持动态小标红点（若从未同步过）。

---

## 验证计划

### 自动化与静态分析
* 执行 `flutter analyze` 确保无 Lint 错误和警告。
* 编写单元测试 `test/services/cookie_cloud_service_test.dart`：
  * 测试标准的加密数据用例，验证 `EVP_BytesToKey` 派生与解密模块是否能够稳定解密出标准的 JSON。
  * 测试 Host 匹配算法的边界条件。

### 手动验证
1. 在电脑端部署本地 Cookie Cloud 服务器并同步部分测试站点。
2. 在 PT Mate 模拟器/实机输入配置信息，测试连通性。
3. 检查解密出的列表是否完全匹配内置模版与本地已配置站点。
4. 勾选数个站点进行同步，验证本地 `SiteConfig` 更新后，网络请求是否使用了最新的 Cookie（以健康检查结果为依据）。
5. 验证添加新站点时，其功能配置、默认分类是否全部继承了内置模板对应的字段值，确保无损建站。
