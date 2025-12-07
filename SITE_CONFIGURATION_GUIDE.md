# 网站配置文件编写指南

本指南将帮助您为 PT 站点创建配置文件，以便在应用中支持更多网站。

## 目录结构

网站配置文件位于以下目录：

- `assets/sites/` - 存放具体网站的配置文件
- `assets/site_configs.json` - 存放默认模板配置
- `assets/sites_manifest.json` - 网站清单文件（此文件不需要手动改动，增加配置文件后运行根目录下的generate_sites_manifest.sh即可自动生成也可以自行配置githook，详见[readme.md](./README.md)）

## 配置文件类型

### 1. 独立网站配置文件

位于 `assets/sites/` 目录下，每个网站一个 JSON 文件。

#### 基本结构

```json
{
  "id": "网站唯一标识符",
  "name": "网站显示名称",
  "isShow": true,
  "baseUrls": ["https://example.com/"],
  "primaryUrl": "https://example.com/",
  "siteType": "网站类型",
  "searchCategories": [],
  "features": {},
  "discountMapping": {},
  "infoFinder": {},
  "request": {}
}
```

#### 字段说明

| 字段               | 类型    | 必填 | 说明                                                |
| ------------------ | ------- | ---- | --------------------------------------------------- |
| `id`               | string  | ✅   | 网站唯一标识符，建议使用网站域名简写                |
| `name`             | string  | ✅   | 网站显示名称                                        |
| `isShow`           | boolean | ❌   | 是否在下拉列表中显示，默认 `true`                   |
| `baseUrls`         | array   | ✅   | 网站基础 URL 列表                                   |
| `primaryUrl`       | string  | ✅   | 主要 URL                                            |
| `siteType`         | string  | ✅   | 网站类型，支持：`M-Team`、`NexusPHP`、`NexusPHPWeb` |
| `searchCategories` | array   | ❌   | 搜索分类配置  如果这里有配置会直接根据这里配置返回，
适用于api权限没开或者dom比较难适配的网站                                                    |
| `features`         | object  | ✅   | 功能支持配置                                        |
| `discountMapping`  | object  | ❌   | 折扣映射配置                                        |
| `infoFinder`       | object  | ❌   | 信息提取配置（仅 NexusPHPWeb 类型需要）             |
| `request`          | object  | ❌   | 自定义请求配置（暂不完善有具体需求可以提issue）     |

### 2. 功能配置 (features)

```json
{
  "features": {
    "userProfile": true, // 用户资料
    "torrentSearch": true, // 种子搜索
    "torrentDetail": true, // 种子详情
    "download": true, // 下载功能
    "favorites": true, // 收藏功能
    "downloadHistory": true, // 下载历史
    "categorySearch": true, // 分类搜索
    "advancedSearch": true // 高级搜索
  }
}
```

### 3. 折扣映射 (discountMapping)

```json
{
  "discountMapping": {
    "Free": "FREE",
    "2X Free": "2xFREE",
    "50%": "PERCENT_50",
    "Normal": "NORMAL"
  }
}
```

### 4. 自定义请求配置 (request)

用于配置特殊的 HTTP 请求，如收藏功能：

```json
{
  "request": {
    "collect": {
      "path": "/api.php",
      "method": "POST",
      "headers": {
        "Content-Type": "application/x-www-form-urlencoded"
      },
      "params": {
        "action": "bookmark",
        "tid": "{torrentId}"
      }
    }
  }
}
```

#### 请求配置字段说明

| 字段      | 类型   | 必填 | 说明                                      |
| --------- | ------ | ---- | ----------------------------------------- |
| `path`    | string | ✅   | 请求路径，可以是相对路径或绝对 URL        |
| `method`  | string | ❌   | HTTP 方法，默认 `GET`，支持 `GET`、`POST` |
| `headers` | object | ❌   | 请求头配置                                |
| `params`  | object | ❌   | 请求参数                                  |

#### 参数占位符

在 `path` 和 `params` 中可以使用以下占位符：

- `{torrentId}` - 种子 ID
- `{baseUrl}` - 网站基础 URL
- `{passKey}` - 用户密钥

### 5. 信息提取配置 (infoFinder)

仅适用于 `NexusPHPWeb` 类型网站，用于配置如何从网页中提取信息。

#### 主要构成
- `userInfo`: 用户信息提取配置。
- `passKey`: 用户密钥提取配置。
- `search`: 种子列表提取配置。
- `categories`: 网站分类提取配置。

#### 配置示例
里面的具体内容都大同小异，下面以`userInfo`为例：

```json
{
  "infoFinder": {
    "userInfo": {
      "path": "usercp.php",
      "rows": {
        "selector": "table#info_block > span.medium"
      },
      "fields": {
        "userId": {
          "selector": "a[href^=\"userdetails.php?id=\"]",
          "attribute": "href",
          "filter": {
            "name": "regexp",
            "args": "id=(\\d+)",
            "index": 1
          }
        }
      }
    }
  }
}
```
#### 字段说明

##### `selector` 选择器的说明

目前支持两种选择器：

- `css selector`：基于 CSS 选择器的选择器，这会严格按照 CSS 选择器的规则进行匹配，内容请以`@@`开头后面跟着具体的选择器，比如：
`@@table#info_block > span.medium`。CSS 选择器有一些局限性，比如不能跨层级选择、不能过滤属性等，
并且网站一旦dom发生变动，越精细的选择器越容易失效。
- `ptm selector`：其实整体上也类似与CSS 选择器，但是更加强大，支持更多的操作，具体有以下不同：
  - 内容**无需**以`@@`开头，直接写具体的选择器即可，比如：`table#info_block > span.medium`。
  - 默认就是跨层级选择，`>`会从所有子孙元素中进行匹配，而不是只匹配直接子元素。如果只想要子元素请使用`nth-child`,
    `nth-child(1)`表示第一个子元素，`nth-child(2)`表示第二个子元素，以此类推。也可以直接不跟数字比如：`tr:nth-child`
    表示所有子元素中的`tr`元素。
  - 支持属性过滤，比如：`[href^=\"userdetails.php?id=\"]`表示提取所有`href`属性以`userdetails.php?id=`开头的元素。
    同时支持三种符号表达式：
    - `^=`：表示以...开头
    - `~=`：表示以正则表达式匹配
    - `==`：表示相等
  - 一些特殊用法：
    - `img[data-src]` 表示提取所有`img`元素中`data-src`属性不为空的元素。
    - `next`：表示提取当前元素的下一个兄弟元素。
    - `prev`：表示提取当前元素的上一个兄弟元素。
    - `nextParsed`：表示提取当前元素的下一个兄弟元素(包括非标签)。
    - `prevParsed`：表示提取当前元素的上一个兄弟元素(包括非标签)。
    - `parent`：表示提取当前元素的父元素。

##### 其它字段说明

- `path`：提取用户信息的页面路径
- `rows`：
  - `selector`：包含提取目标的大区域，方便提取fields时进一步在此基础上筛选。可以匹配到多个，比如种子列表就需要匹配多个。
- `fields`：从上面的区域中提取具体的字段。
  - `userId`：要提取的字段id，这是固定的，具体请参考[默认配置文件site_configs.json](/assets/site_configs.json)。
    - `selector`：进一步的选择器，在这里进一步定位到目标数据所在dom节点。
    - `attribute`：提取属性，比如`href`、`src`等，其中有一个比较特殊的`text`，效果类似于innerHTML，提取节点的纯文本（去除所有的html标签）内容。
    - `filter`：如果需要对提取到的数据进行进一步处理，这里可以配置相应的过滤器。
      - `name`：过滤器名称，目前只支持`regexp`（正则表达式）。
      - `args`：过滤器参数，根据名称不同有不同的格式。
        - `regexp`：正则表达式字符串，用于提取匹配的部分。
      - `index`：如果正则表达式有捕获组，这里可以指定提取哪个组的内容。

##### search模块下的一下特殊字段说明
- `fields`
  - `downloadUrl.value`: 下载地址，默认的策略为：`download.php?downhash={userId}.{jwt}`,如果符合默认策略本字段则可以不用配置。
   可以自定义成别的格式，比如：`{baseUrl}/download.php?id={torrentId}&passkey={passKey}&https=1`。有五个变量可以被自动解析：
    - `{baseUrl}`：网站基础 URL
    - `{torrentId}`：种子 ID
    - `{passKey}`：用户密钥
    - `{userId}`：用户 ID
    - `{jwt}`：下载令牌
  
    特别注意：这里的地址都是带鉴权的，一般位于种子详情页的'种子链接'条目中，是可以作为独立地址去下载的。
    
    最后，如果逻辑比较复杂无法用这些变量拼接出来可以使用`##`开头强制启用本网站本地中转下载，强制启用后将覆盖用户的手动配置，
    比如：`##{baseUrl}/download.php?id={torrentId}`。本地中转模式下会启用cookie先将torrent下载到本地然后推送到下载器。


## 网站类型说明

### M-Team 类型

- 使用 M-Team 官方 API
- 无需配置 `infoFinder`
- 不能代替网页浏览，但是可以提醒长时间未浏览

### NexusPHP 类型

- 使用 NexusPHP 框架的 API 接口
- 无需配置 `infoFinder`
- 不能代替网页浏览，但是可以提醒长时间未浏览
- 最好的兼容性与性能

### NexusPHPWeb 类型

- 通过网页爬虫方式获取信息
- 需要详细配置 `infoFinder`
- 兼容性完全依赖于页面布局，可能需要大量适配工作

## 添加新网站步骤

### 步骤 1：创建配置文件

在 `assets/sites/` 目录下创建新的 JSON 文件，文件名建议使用网站域名：

```bash
assets/sites/newsite.json
```

### 步骤 2：编写配置内容

根据网站类型选择合适的模板：

#### 使用 NexusPHP 类型

目前 api 对 1.9+兼容性良好，此类型只需配置`id`、`name`、`isShow`、`baseUrls`、`primaryUrl`、`siteType`等基础信息即可。

#### 使用 NexusPHPWeb 类型（用于不兼容 api 的 NexusPHP 站点）

```json
{
  "id": "newsite",
  "name": "新站点",
  "isShow": true,
  "baseUrls": ["https://newsite.com/"],
  "primaryUrl": "https://newsite.com/",
  "siteType": "NexusPHPWeb",
  "searchCategories": [],
  "features": {
    "userProfile": true,
    "torrentSearch": true,
    "torrentDetail": true,
    "download": true,
    "favorites": true,
    "downloadHistory": true,
    "categorySearch": true,
    "advancedSearch": true
  },
  "discountMapping": {
    "Free": "FREE",
    "Normal": "NORMAL"
  },
  "infoFinder": {
    // 需要根据具体网站配置
  }
}
```

### 步骤 3：更新网站清单

在 `assets/sites_manifest.json` 中添加新网站：

```json
{
  "sites": ["mteam.json", "newsite.json"]
}
```

### 步骤 4：测试配置

1. 重启应用
2. 在服务器设置中添加新网站
3. 测试各项功能是否正常

## 配置示例

### 示例 1：简单的 NexusPHPWeb 站点

```json
{
  "id": "example",
  "name": "示例站点",
  "isShow": true,
  "baseUrls": ["https://example.com/"],
  "primaryUrl": "https://example.com/",
  "siteType": "NexusPHPWeb",
  "features": {
    "userProfile": true,
    "torrentSearch": true,
    "torrentDetail": true,
    "download": true,
    "favorites": false,
    "downloadHistory": false,
    "categorySearch": true,
    "advancedSearch": true
  },
  "discountMapping": {
    "Free": "FREE",
    "50%": "PERCENT_50",
    "Normal": "NORMAL"
  }
}
```

### 示例 2：带自定义收藏请求的站点

```json
{
  "id": "example2",
  "name": "示例站点2",
  "isShow": true,
  "baseUrls": ["https://example2.com/"],
  "primaryUrl": "https://example2.com/",
  "siteType": "NexusPHPWeb",
  "features": {
    "userProfile": true,
    "torrentSearch": true,
    "torrentDetail": true,
    "download": true,
    "favorites": true,
    "downloadHistory": true,
    "categorySearch": true,
    "advancedSearch": true
  },
  "request": {
    "collect": {
      "path": "/bookmark.php",
      "method": "GET",
      "params": {
        "torrentid": "{torrentId}"
      }
    }
  }
}
```

## 常见问题

### Q: 如何隐藏某个网站不在下拉列表中显示？

A: 设置 `"isShow": false`

### Q: 网站支持哪些功能？

A: 在 `features` 字段中配置，根据网站实际支持情况设置为 `true` 或 `false`

### Q: 如何配置自定义的收藏功能？

A: 在 `request.collect` 中配置请求路径、方法、参数等

### Q: 折扣映射如何配置？

A: 在 `discountMapping` 中将网站的折扣文本映射到应用内部的折扣类型

### Q: 如何调试配置文件？

A:

1. 检查 JSON 格式是否正确
2. 确认所有必填字段都已填写
3. 在应用中测试各项功能
4. 查看应用日志获取错误信息

#### 使用 Web 调试（仅 NexusPHPWeb）

当你为 NexusPHP Web 类型站点编写或修改 `infoFinder`/`discountMapping` 等配置时，可通过内置 Web 调试快速验证：

- 打开应用：`设置 → 日志与诊断 → Web 调试` 开关
- 记录提示的访问地址（例如 `http://<设备IP>:8833/`），在同一局域网浏览器访问
- 页面输入：
  - 站点地址：目标站点 `baseUrl`（如 `https://example.com`）
  - Cookie：登录后的认证 Cookie（`uid=...; pass=...`）
  - 详细配置：在这里编写你的完整网站提取配置。
- 点击“测试”，返回：
  - `profile`：用户资料（包含 `userId`、`bonus` 等）
  - `categories`：分类列表（`id`、`name`）
  - `torrentsTop3`：前三条搜索结果（包含 `id`、`title`、`discount`、`sizeBytes`、`seeders`、`leechers` 等）

注意：页面粘贴的模板优先于预置模板，不受缓存影响；Web 构建无法启动本地服务，请在移动或桌面环境调试。

## 贡献指南

如果您成功适配了新的网站，欢迎提交 Pull Request 分享给其他用户：

1. Fork 项目
2. 创建配置文件
3. 测试功能完整性
4. 提交 Pull Request

## 技术支持

如果在配置过程中遇到问题，可以：

1. 查看现有配置文件作为参考
2. 在 GitHub Issues 中提问
3. 参考应用日志进行调试

---
