# 网站配置文件编写指南

本指南将帮助您为 PT 站点创建配置文件，以便在应用中支持更多网站。

## 目录结构

网站配置文件位于以下目录：

- `assets/sites/` - 存放具体网站的配置文件
- `assets/site_configs.json` - 存放默认模板配置
- `assets/sites_manifest.json` - 网站清单文件

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
| `searchCategories` | array   | ❌   | 搜索分类配置                                        |
| `features`         | object  | ✅   | 功能支持配置                                        |
| `discountMapping`  | object  | ❌   | 折扣映射配置                                        |
| `infoFinder`       | object  | ❌   | 信息提取配置（仅 NexusPHPWeb 类型需要）             |
| `request`          | object  | ❌   | 自定义请求配置                                      |

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

## 网站类型说明

### M-Team 类型

- 使用 M-Team 官方 API
- 无需配置 `infoFinder`
- 支持完整的搜索和用户功能

### NexusPHP 类型

- 使用 NexusPHP 框架的 API 接口
- 无需配置 `infoFinder`
- 功能相对有限

### NexusPHPWeb 类型

- 通过网页爬虫方式获取信息
- 需要详细配置 `infoFinder`
- 支持最完整的功能

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
