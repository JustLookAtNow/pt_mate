# 使用指南

## 移动设备左滑操作

在移动设备上，您可以通过左滑种子列表项来快速访问常用操作。

### 可用操作
- 收藏/取消收藏：左滑后点击心形图标可以收藏或取消收藏种子
- 下载：左滑后点击下载图标可以直接下载种子到配置的下载器

### 操作说明
1. 在种子列表中，向左滑动任意种子项
2. 滑动后会显示操作按钮（收藏和下载）
3. 点击对应按钮执行相应操作
4. 点击列表其他区域或向右滑动可以隐藏操作按钮

## 日志与诊断

为便于问题定位，应用支持将日志写入本地文件并通过系统分享导出。

### 开启日志记录
- 进入 `设置 → 日志与诊断`
- 打开 `记录日志到本地文件`
- 日志将按天写入应用私有目录（Android/iOS 无需额外存储权限）

### 导出日志
- 进入 `设置 → 日志与诊断 → 导出日志`
- 选择 `分享最新日志文件`，通过系统分享面板发送给开发者
- 如需查看路径，选择 `显示日志目录路径`

### 常见问题
- 未看到日志文件：请确认已开启 `记录日志到本地文件`，并在出现问题后停留片刻以便写入
- Web 不支持落盘：Web 端因浏览器限制不写入日志文件，可在控制台查看

### Web 调试（仅 NexusPHP Web）
- 作用：在局域网启动一个本地调试页面，用于快速验证 NexusPHP Web 站点的提取规则与搜索行为
- 开启方式：进入 `设置 → 日志与诊断 → Web 调试`，打开后会显示访问地址（例如：`http://<设备IP>:8833/`）
- 访问与输入：在浏览器打开该地址，页面包含 3 个输入框
  - 站点地址：目标站点的 `baseUrl`（例如 `https://example.com`）
  - Cookie：登录后的认证 Cookie（如 `uid=...; pass=...`）
  - 详细配置：在这里编写完整网站提取配置
- 测试内容：点击“测试”后会初始化 NexusPHP Web 实例，依次调用并返回结果
  - `fetchMemberProfile`（用户资料）
  - `getSearchCategories`（分类列表）
  - `searchTorrents`（仅展示前 3 条）
- 模板优先级：页面粘贴的模板优先于预置模板，不填时才使用默认提取规则
- 注意事项
  - 仅支持非 Web 构建（Android/iOS/桌面），Web 构建无法启动本地服务
  - 调试服务只用于局域网测试，不会写入 Cookie 到日志
  - 若下载链接需要 `passKey`/`userId`，会在 `fetchMemberProfile` 后临时填充
  - 端口占用会自动回退为系统分配端口，地址以设置页提示为准
  - 调试页面启用了基础 CORS 以便跨设备访问

## 动态查询条件配置

应用支持自定义搜索分类和查询参数，让您可以根据需要灵活配置搜索条件。

### 配置步骤
1. 进入应用设置页面
2. 找到“搜索分类配置”部分
3. 点击“获取”自动获取现有分类信息，或手动添加/编辑
4. 配置分类信息
   - 显示名称：在下拉框中显示的分类名称
   - 查询参数：搜索时使用的参数配置

### 参数格式

推荐 JSON 格式：

```json
{"mode":"normal","teams":["44","9","43"]}
```

兼容键值对格式（分号分隔）：

```text
mode:"normal";teams:["44","9","43"]
```

### 参数说明（M-Team）
- `mode`：搜索模式（如 `normal`、`movie`）
- `teams`：制作组 ID 数组
- `categories`：分类 ID 数组（如 `["407", "420"]`）
- `discount`：促销类型（如 `FREE`、`PERCENT_50`）

### 参数说明（NexusPHP API）
- 可参考外部接口文档：[NexusPHP API 文档](https://s.apifox.cn/43608c09-bab0-4e2e-9a56-77ffa629c8e0/api-87956324)

### 参数说明（NexusPHP Web）
- 在浏览器中过滤条件后，观察地址栏 URL，把查询参数转为 JSON
- 示例 URL：`https://nexusphp.org/torrents.php?cat=404&inclbookmarked=0&incldead=1&spstate=0&seeders_begin=1&seeders_end=1&page=0`
- `category` 参数格式为 `分区#分类id`
  - `torrents.php` 对应 `normal#catxxx`
  - `special.php` 对应 `special#catxxx`（无分类时可用 `special#`）
- 其余参数按键值对转为 JSON

示例转换结果：

```json
{"category":"normal#cat404","inclbookmarked":"0","incldead":"1","spstate":"0","seeders_begin":"1","seeders_end":"1"}
```

### 特别注意
- M-Team 的 `pageNumber`、`pageSize`、`keyword`、`onlyFav` 不能自定义
- NexusPHP 的 `page`、`pageSize`、`search`、`inclbookmarked` 不能自定义

### 使用示例（M-Team）

```json
{"mode":"movie"}
```

```json
{"mode":"normal","teams":["44","9"]}
```

```json
{"mode":"normal","discount":"FREE"}
```

## NexusPHP Web 类型站点登录

对于 NexusPHP Web 类型站点，应用会弹出内置登录界面完成认证。

### 登录流程
1. 选择 NexusPHP Web 类型站点后，应用自动弹出登录界面
2. 输入用户名和密码完成登录
3. 登录成功后自动获取必要 Cookie
4. 正常情况下登录界面会自动关闭

### 手动关闭
如果登录已完成但界面长时间未自动关闭，可点击右上角关闭按钮；这不会影响 Cookie 获取和保存。
