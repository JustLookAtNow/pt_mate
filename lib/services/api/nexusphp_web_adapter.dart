import 'package:flutter/foundation.dart';

import '../../models/app_models.dart';
import 'site_adapter.dart';
import '../site_config_service.dart';
import 'package:dio/dio.dart';
import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

/// Cookie过期异常
class CookieExpiredException implements Exception {
  final String message;
  CookieExpiredException(this.message);

  @override
  String toString() => 'CookieExpiredException: $message';
}

/// NexusPHP Web站点适配器
/// 用于处理基于Web接口的NexusPHP站点
class NexusPHPWebAdapter extends SiteAdapter {
  late SiteConfig _siteConfig;
  late Dio _dio;
  Map<String, String>? _discountMapping;

  @override
  SiteConfig get siteConfig => _siteConfig;

  /// 将相对时间格式转换为绝对时间格式
  /// 例如："7时28分钟" -> "2025-08-27 21:16:48"
  String? _convertRelativeTimeToAbsolute(String? relativeTime) {
    if (relativeTime == null || relativeTime.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    int totalMinutes = 0;

    // 解析月数
    final monthMatch = RegExp(r'(\d+)月').firstMatch(relativeTime);
    if (monthMatch != null) {
      final months = int.tryParse(monthMatch.group(1) ?? '0') ?? 0;
      totalMinutes += months * 30 * 24 * 60;
    }

    // 解析天数
    final dayMatch = RegExp(r'(\d+)天').firstMatch(relativeTime);
    if (dayMatch != null) {
      final days = int.tryParse(dayMatch.group(1) ?? '0') ?? 0;
      totalMinutes += days * 24 * 60;
    }

    // 解析小时数
    final hourMatch = RegExp(r'(\d+)时').firstMatch(relativeTime);
    if (hourMatch != null) {
      final hours = int.tryParse(hourMatch.group(1) ?? '0') ?? 0;
      totalMinutes += hours * 60;
    }

    // 解析分钟数
    final minuteMatch = RegExp(r'(\d+)分').firstMatch(relativeTime);
    if (minuteMatch != null) {
      final minutes = int.tryParse(minuteMatch.group(1) ?? '0') ?? 0;
      totalMinutes += minutes;
    }

    // 计算绝对时间
    final absoluteTime = now.add(Duration(minutes: totalMinutes));

    // 使用DateFormat格式化为 "yyyy-MM-dd HH:mm:ss" 格式
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    return formatter.format(absoluteTime);
  }

  @override
  Future<void> init(SiteConfig config) async {
    _siteConfig = config;

    // 加载优惠类型映射配置
    await _loadDiscountMapping();

    _dio = Dio();
    _dio.options.baseUrl = _siteConfig.baseUrl;
    _dio.options.headers['User-Agent'] =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
    _dio.options.responseType = ResponseType.plain; // 设置为plain避免JSON解析警告

    // 设置Cookie
    if (_siteConfig.cookie != null && _siteConfig.cookie!.isNotEmpty) {
      _dio.options.headers['Cookie'] = _siteConfig.cookie;
    }

    // 添加响应拦截器处理302重定向
    _dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) {
          // 检查是否是302重定向到登录页面
          if (response.statusCode == 302) {
            final location = response.headers.value('location');
            if (location != null && location.contains('login')) {
              throw CookieExpiredException('Cookie已过期，请重新登录更新Cookie');
            }
          }
          handler.next(response);
        },
        onError: (error, handler) {
          // 检查DioException中的响应状态码
          if (error.response?.statusCode == 302) {
            final location = error.response?.headers.value('location');
            if (location != null && location.contains('login')) {
              throw CookieExpiredException('Cookie已过期，请重新登录更新Cookie');
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  /// 加载优惠类型映射配置
  Future<void> _loadDiscountMapping() async {
    try {
      final template = await SiteConfigService.getDefaultTemplate(
        'NexusPHPWeb',
      );
      if (template != null && template['discountMapping'] != null) {
        _discountMapping = Map<String, String>.from(
          template['discountMapping'],
        );
      }
      final specialMapping = await SiteConfigService.getDiscountMapping(
        _siteConfig.baseUrl,
      );
      if (specialMapping.isNotEmpty) {
        _discountMapping?.addAll(specialMapping);
      }
    } catch (e) {
      // 使用默认映射
      _discountMapping = {};
    }
  }

  /// 从字符串解析优惠类型
  DiscountType _parseDiscountType(String? str) {
    if (str == null || str.isEmpty) return DiscountType.normal;

    final mapping = _discountMapping ?? {};
    final enumValue = mapping[str];

    if (enumValue != null) {
      for (final type in DiscountType.values) {
        if (type.value == enumValue) {
          return type;
        }
      }
    }

    return DiscountType.normal;
  }

  @override
  Future<MemberProfile> fetchMemberProfile({String? apiKey}) async {
    try {
      final response = await _dio.get('/usercp.php');
      final soup = BeautifulSoup(response.data);

      // 查找用户信息块
      final infoBlock = soup.find('table', id: 'info_block');
      if (infoBlock == null) {
        throw Exception('未找到用户信息块');
      }

      final userInfo = infoBlock.find('span', class_: 'medium');
      if (userInfo == null) {
        throw Exception('未找到用户信息');
      }

      // 提取userId
      String? userId;
      final allLink = userInfo.findAll('a');
      // 过滤 href 中含有 "abc" 的
      for (var a in allLink) {
        final href = a.attributes['href'];
        if (href != null && href.contains('userdetails.php?id=')) {
          RegExp regExp = RegExp(r'userdetails.php\?id=(\d+)');
          final match = regExp.firstMatch(href);
          if (match != null) {
            userId = match.group(1);
          }
        }
      }

      // 提取用户名
      final usernameElement = userInfo.find('span')?.a?.b;
      if (usernameElement == null) {
        throw Exception('未找到用户名');
      }
      final username = usernameElement.text.trim();

      // 提取文本信息
      final textInfo = userInfo.text.trim();

      // 使用正则表达式提取各项数据
      final ratioMatch = RegExp(r'分享率:\s*([^\s]+)').firstMatch(textInfo);
      final ratio = ratioMatch?.group(1)?.trim() ?? '0';

      final uploadMatch = RegExp(r'上传量:\s*(.*?B)').firstMatch(textInfo);
      final uploadString = uploadMatch?.group(1)?.trim() ?? '0 B';

      final downloadMatch = RegExp(r'下载量:\s*(.*?B)').firstMatch(textInfo);
      final downloadString = downloadMatch?.group(1)?.trim() ?? '0 B';

      final bonusMatch = RegExp(r':\s*([^\s]+)\s*\[签到').firstMatch(textInfo);
      final bonus = bonusMatch?.group(1)?.trim() ?? '0';

      // 提取PassKey
      String? passKey;
      final outerTd = soup.find('td', id: 'outer');
      if (outerTd != null) {
        final tables = outerTd.children;
        var thisTable = false;
        var mainText = '';
        for (var table in tables) {
          if (thisTable) {
            mainText = table.text;
            break;
          }
          if (table.getAttrValue('class') == 'main') {
            thisTable = true;
          }
        }

        final passKeyMatch = RegExp(r'密钥\s*([^\s]{32})').firstMatch(mainText);
        if (passKeyMatch != null) {
          passKey = passKeyMatch.group(1)?.trim();
        }
      }
      // 提取userId

      // 将字符串格式的数据转换为数字（简单转换，实际可能需要更复杂的逻辑）
      double shareRate = double.tryParse(ratio) ?? 0.0;
      double bonusPoints = double.tryParse(bonus.replaceAll(',', '')) ?? 0.0;

      // 对于bytes，由于web版本直接提供格式化字符串，这里设置为0
      // 实际使用时应该使用uploadedBytesString和downloadedBytesString
      int uploadedBytes = 0;
      int downloadedBytes = 0;

      return MemberProfile(
        username: username,
        bonus: bonusPoints,
        shareRate: shareRate,
        uploadedBytes: uploadedBytes,
        downloadedBytes: downloadedBytes,
        uploadedBytesString: uploadString,
        downloadedBytesString: downloadString,
        userId: userId,
        passKey: passKey,
      );
    } catch (e) {
      throw Exception('获取用户资料失败: $e');
    }
  }

  @override
  Future<TorrentSearchResult> searchTorrents({
    String? keyword,
    int pageNumber = 1,
    int pageSize = 30,
    int? onlyFav,
    Map<String, dynamic>? additionalParams,
  }) async {
    try {
      // 构建查询参数
      final queryParams = <String, dynamic>{
        'page': pageNumber - 1, // 页面从0开始
        'pageSize': pageSize,
        'incldead': 1, // 添加默认参数
      };

      // 添加关键词搜索
      if (keyword != null && keyword.isNotEmpty) {
        queryParams['search'] = keyword;
      }

      // 添加收藏筛选
      if (onlyFav != null && onlyFav == 1) {
        queryParams['inclbookmarked'] = 1;
      }

      // 确定请求路径
      String requestPath = '/torrents.php';

      // 处理分类参数
      if (additionalParams != null &&
          additionalParams.containsKey('category')) {
        final categoryParam = additionalParams['category'] as String?;
        if (categoryParam != null) {
          // 解析category参数，格式为 {"category":"prefix#id"}
          try {
            final parts = categoryParam.split('#');
            if (parts.length == 2) {
              final categoryValue = parts[1];
              // 检查是否是special前缀
              if (categoryParam.startsWith('special')) {
                requestPath = '/special.php';
              }
              queryParams[categoryValue] = 1;
            }
          } catch (e) {
            // 解析失败时忽略分类参数
          }
        }
      }

      // 发送请求
      final response = await _dio.get(
        requestPath,
        queryParameters: queryParams,
      );
      final soup = BeautifulSoup(response.data);
      // 解析种子列表
      final torrents = parseTorrentList(soup);

      // 解析总页数（从JavaScript变量maxpage中提取）
      int totalPages = parseTotalPages(soup);

      return TorrentSearchResult(
        pageNumber: pageNumber,
        pageSize: pageSize,
        total: torrents.length * totalPages, // 估算值
        totalPages: totalPages,
        items: torrents,
      );
    } catch (e) {
      throw Exception('搜索种子失败: $e');
    }
  }

  int parseTotalPages(BeautifulSoup soup) {
    int totalPages = 1;
    final footerDiv = soup.find('div', id: 'footer');
    if (footerDiv != null) {
      final scriptElement = footerDiv.find('script');
      if (scriptElement != null) {
        final scriptText = scriptElement.text;
        final pageMatch = RegExp(
          r'var\s+maxpage\s*=\s*(\d+);',
        ).firstMatch(scriptText);
        if (pageMatch != null) {
          totalPages = int.tryParse(pageMatch.group(1) ?? '1') ?? 1;
        }
      }
    }
    return totalPages;
  }

  List<TorrentItem> parseTorrentList(BeautifulSoup soup) {
    // 解析种子列表
    final torrents = <TorrentItem>[];
    final torrentTable = soup.find('table', class_: 'torrents');

    if (torrentTable != null) {
      final rows = torrentTable.children.isNotEmpty
          ? torrentTable.children[0].children
          : [];

      // 跳过表头行，从第二行开始处理种子数据
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        final tds = row.children;

        if (tds.length <= 6) continue;
        try {
          final rowTds = tds[1].findAll('td');

          var cover = "";
          // 提取种子ID（从详情链接中）
          var titleTd = rowTds[1];
          var detailLink = titleTd.find('a[href*="details.php"]');
          var containsIcon = true;
          if (detailLink == null) {
            //有些网站没封面，可以从第一个td试试
            containsIcon = false;
            titleTd = rowTds[0];
            detailLink = titleTd.find('a[href*="details.php"]');
            if (detailLink == null) continue;
          } else {
            //有封面，提取封面
            var img = rowTds[0].find('img');
            if (img != null) {
              cover = img.getAttrValue('data-src') ?? '';
            }
          }

          final href = detailLink.attributes['href'] ?? '';
          final idMatch = RegExp(r'id=(\d+)').firstMatch(href);
          if (idMatch == null) continue;

          final torrentId = idMatch.group(1) ?? '';
          if (torrentId.isEmpty) continue;

          // 提取主标题（去除换行）
          final titleElement = titleTd.find('a[href*="details.php"] b');
          String title = '';
          if (titleElement != null) {
            title = titleElement.text
                .replaceAll('\n', ' ')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
          }

          // 提取描述：只要纯文本，把标题去掉。
          String description = titleTd.text
              .replaceAll('\n', ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim()
              .replaceAll(title, '')
              .replaceAll(RegExp(r'剩余时间：\d+.*?\d+[分钟|时]'), '');
          // 提取下载记录
          DownloadStatus status = DownloadStatus.none;
          final downloadDiv = titleTd.find('div', attrs: {'title': true});
          if (downloadDiv != null) {
            final downloadTitle = downloadDiv.getAttrValue('title');
            RegExp regExp = RegExp(r'(\d+)\%');
            final match = regExp.firstMatch(downloadTitle!);
            if (match != null) {
              final percent = match.group(1);
              if (percent != null) {
                int percentInt = int.parse(percent);
                if (percentInt == 100) {
                  status = DownloadStatus.completed;
                } else {
                  status = DownloadStatus.downloading;
                }
              }
            }
          }
          // 提取大小（第5列，索引4）
          final sizeText = tds[4].text.replaceAll('\n', ' ').trim();

          // 提取做种数（第6列，索引5）
          String seedersText = '';
          final seedersElement = tds[5].find('a');
          if (seedersElement != null) {
            seedersText = seedersElement.text.trim();
          } else {
            final boldElement = tds[5].find('b');
            if (boldElement != null) {
              seedersText = boldElement.text.trim();
            } else {
              seedersText = tds[5].text.trim();
            }
          }

          // 提取下载数（第7列，索引6）
          String leechersText = '';
          final leechersElement = tds[6].find('a');
          if (leechersElement != null) {
            leechersText = leechersElement.text.trim();
          } else {
            final boldElement = tds[6].find('b');
            if (boldElement != null) {
              leechersText = boldElement.text.trim();
            } else {
              leechersText = tds[6].text.trim();
            }
          }

          // 提取优惠信息
          String? promoType;
          String? remainingTime;
          var promoImg = tds[1].find('img[onmouseover]');
          promoImg ??= tds[1].find('img', class_: 'pro_free');
          if (promoImg != null) {
            promoType = promoImg.attributes['alt'] ?? '';

            // 提取剩余时间：使用正则表达式匹配"剩余时间：<span title=\"...\">...</span>"
            final titleCellHtml = tds[1].innerHtml;
            final timeRegex = RegExp(r'剩余时间：<span[^>]*>([^<]+)</span>');
            final timeMatch = timeRegex.firstMatch(titleCellHtml);
            if (timeMatch != null) {
              remainingTime = timeMatch.group(1)?.trim() ?? '';
            }
          }

          // 解析文件大小为字节数，因为有按大小排序，所以要处理单位
          int sizeInBytes = 0;
          final sizeMatch = RegExp(r'([\d.]+)\s*(\w+)').firstMatch(sizeText);
          if (sizeMatch != null) {
            final sizeValue = double.tryParse(sizeMatch.group(1) ?? '0') ?? 0;
            final unit = sizeMatch.group(2)?.toUpperCase() ?? 'B';

            switch (unit) {
              case 'KB':
                sizeInBytes = (sizeValue * 1024).round();
                break;
              case 'MB':
                sizeInBytes = (sizeValue * 1024 * 1024).round();
                break;
              case 'GB':
                sizeInBytes = (sizeValue * 1024 * 1024 * 1024).round();
                break;
              case 'TB':
                sizeInBytes = (sizeValue * 1024 * 1024 * 1024 * 1024).round();
                break;
              default:
                sizeInBytes = sizeValue.round();
            }
          }
          //收藏信息
          var starTd = rowTds[2];
          if (containsIcon && rowTds.length > 3) {
            starTd = rowTds[3];
          }
          final starImg = starTd.find('img', class_: 'delbookmark');
          final collection = starImg == null;
          torrents.add(
            TorrentItem(
              id: torrentId,
              name: title,
              smallDescr: description,
              discount: _parseDiscountType(
                promoType?.isNotEmpty == true ? promoType : null,
              ),
              discountEndTime: _convertRelativeTimeToAbsolute(remainingTime),
              downloadUrl: null, // 暂时不提供直接下载链接
              seeders: int.tryParse(seedersText) ?? 0,
              leechers: int.tryParse(leechersText) ?? 0,
              sizeBytes: sizeInBytes,
              downloadStatus: status,
              collection: collection,
              imageList: [], // 暂时不解析图片列表
              cover: cover
            ),
          );
        } catch (e) {
          debugPrint('解析种子行失败: $e');
          continue;
        }
      }
    }
    return torrents;
  }

  @override
  Future<TorrentDetail> fetchTorrentDetail(String id) async {
    // 构建种子详情页面URL
    final baseUrl = _siteConfig.baseUrl.endsWith('/')
        ? _siteConfig.baseUrl.substring(0, _siteConfig.baseUrl.length - 1)
        : _siteConfig.baseUrl;
    final detailUrl = '$baseUrl/details.php?id=$id&hit=1';
    if (defaultTargetPlatform == TargetPlatform.android) {
      // 设置Cookie到baseUrl域下，HTTPOnly避免带到图片请求
      final cookieManager = CookieManager.instance();
      final baseUri = Uri.parse(_siteConfig.baseUrl);

      if (_siteConfig.cookie != null && _siteConfig.cookie!.isNotEmpty) {
        // 解析cookie字符串并设置到域下
        final cookies = _siteConfig.cookie!.split(';');
        for (final cookieStr in cookies) {
          final parts = cookieStr.trim().split('=');
          if (parts.length == 2) {
            await cookieManager.setCookie(
              url: WebUri(_siteConfig.baseUrl),
              name: parts[0].trim(),
              value: parts[1].trim(),
              domain: baseUri.host,
              isHttpOnly: true,
            );
          }
        }
      }
    }

    // 返回包含webview URL的TorrentDetail对象，让页面组件来处理嵌入式显示
    return TorrentDetail(
      descr: '', // 空描述，因为内容将通过webview显示
      webviewUrl: detailUrl, // 传递URL给页面组件
    );
  }

  @override
  Future<String> genDlToken({required String id}) async {
    // 检查必要的配置参数
    if (_siteConfig.passKey == null || _siteConfig.passKey!.isEmpty) {
      throw Exception('站点配置缺少passKey，无法生成下载链接');
    }
    if (_siteConfig.userId == null || _siteConfig.userId!.isEmpty) {
      throw Exception('站点配置缺少userId，无法生成下载链接');
    }

    // https://www.ptskit.org/download.php?downhash={userId}.{jwt}
    final jwt = getDownLoadHash(_siteConfig.passKey!, id, _siteConfig.userId!);
    return '${_siteConfig.baseUrl}download.php?downhash=${_siteConfig.userId!}.$jwt';
  }

  /// 生成下载Hash令牌
  ///
  /// 参数:
  /// - [passkey] 站点passkey
  /// - [id] 种子ID
  /// - [userid] 用户ID
  ///
  /// 返回: JWT编码的下载令牌
  String getDownLoadHash(String passkey, String id, String userid) {
    // 生成MD5密钥: md5(passkey + 当前日期(Ymd) + userid)
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final keyString = passkey + dateStr + userid;
    final keyBytes = utf8.encode(keyString);
    final digest = md5.convert(keyBytes);
    final key = digest.toString();

    // 创建JWT payload
    final payload = {
      'id': id,
      'exp':
          (DateTime.now().millisecondsSinceEpoch / 1000).floor() +
          3600, // 1小时后过期
    };

    // 使用HS256算法生成JWT
    final jwt = JWT(payload);
    final token = jwt.sign(SecretKey(key), algorithm: JWTAlgorithm.HS256);

    return token;
  }

  @override
  Future<Map<String, dynamic>> queryHistory({
    required List<String> tids,
  }) async {
    // TODO: 实现查询下载历史
    //getusertorrentlistajax.php?userid=20148&type=seeding
    //getusertorrentlistajax.php?userid=20148&type=uploaded
    throw UnimplementedError('queryHistory not implemented');
  }

  @override
  Future<void> toggleCollection({
    required String id,
    required bool make,
  }) async {
    try {
      // 发送GET请求到bookmark.php，传入torrentid参数
      // 根据用户要求，不需要关注mark字段，直接请求即可自动切换收藏状态
      await _dio.get('/bookmark.php', queryParameters: {'torrentid': id});
    } catch (e) {
      throw Exception('切换收藏状态失败: $e');
    }
  }

  @override
  Future<bool> testConnection() async {
    // TODO: 实现测试连接
    throw UnimplementedError('testConnection not implemented');
  }

  @override
  Future<List<SearchCategoryConfig>> getSearchCategories() async {
    // 优先匹配baseUrl，然后类型
    final defaultCategories =
        await SiteConfigService.getDefaultSearchCategories(
          _siteConfig.siteType.id,
          baseUrl: _siteConfig.baseUrl,
        );

    // 如果获取到默认分类配置，则直接返回
    if (defaultCategories.isNotEmpty) {
      return defaultCategories;
    }

    final List<SearchCategoryConfig> categories = [];
    // 默认塞个综合进来
    categories.add(
      SearchCategoryConfig(id: 'all', displayName: '综合', parameters: '{}'),
    );

    try {
      final response = await _dio.get('/usercp.php?action=tracker');

      if (response.statusCode == 200) {
        final htmlContent = response.data as String;
        final soup = BeautifulSoup(htmlContent);

        // 解析HTML获取分类信息
        final parsedCategories = _parseCategories(soup);
        categories.addAll(parsedCategories);
      }

      return categories;
    } catch (e) {
      // 发生异常时，返回默认分类
      return categories;
    }
  }

  /// 解析HTML文档中的分类信息
  List<SearchCategoryConfig> _parseCategories(BeautifulSoup soup) {
    final List<SearchCategoryConfig> categories = [];

    final outerElement = soup.find('#outer');
    if (outerElement == null) return categories;

    var currentBatch = <Map<String, String>>[];

    final formElement = outerElement.find(
      'form',
      attrs: {'action': 'usercp.php'},
    );

    if (formElement == null) return categories;

    final table2 = formElement.find('table');
    List<Bs4Element> infoTables = [];
    if (table2 == null) {
      //<form method="post" action="usercp.php"></form>没闭合。
      for (var element in outerElement.children) {
        final checkboxes = element.findAll('input[type="checkbox"]');
        if (checkboxes.isNotEmpty) {
          for (var checkbox in checkboxes) {
            final categoryName = checkbox.attributes['name'] ?? '';
            final categoryId = checkbox.attributes['id'] ?? '';
            if (categoryName.isNotEmpty &&
                categoryName.startsWith("cat") &&
                categoryId.isNotEmpty &&
                categoryId.startsWith("cat")) {
              infoTables = element.findAll('table');
              if (infoTables.isNotEmpty) {
                break;
              }
            }
          }
        }
      }
    } else {
      infoTables = table2.findAll('table');
    }

    int batchIndex = 1;

    for (final infoTable in infoTables) {
      final rows = infoTable.findAll('tr');

      for (final row in rows) {
        final tds = row.findAll('td');
        var hasCategories = false;

        if (tds.isNotEmpty) {
          for (final td in tds) {
            final img = td.find('img');
            final checkbox = td.find('input[type="checkbox"]');

            if (img != null) {
              final alt = img.attributes['alt'] ?? '';
              final title = img.attributes['title'] ?? '';
              final categoryName = alt.isNotEmpty ? alt : title;
              final categoryId = checkbox?.attributes['id'] ?? '';

              if (categoryName.isNotEmpty && categoryId.isNotEmpty) {
                currentBatch.add({'name': categoryName, 'id': categoryId});
                hasCategories = true;
              }
            }
          }
        }

        // 如果当前行没有分类信息，处理当前批次（如果有内容）
        if (!hasCategories && currentBatch.isNotEmpty) {
          _processBatch(categories, currentBatch, batchIndex);
          batchIndex++;
          currentBatch.clear();
        }
      }
    }

    // 处理最后一个批次（如果还有未处理的分类）
    if (currentBatch.isNotEmpty) {
      _processBatch(categories, currentBatch, batchIndex);
    }

    return categories;
  }

  /// 处理分类批次，添加到分类列表中
  void _processBatch(
    List<SearchCategoryConfig> categories,
    List<Map<String, String>> batch,
    int batchIndex,
  ) {
    String prefix;
    if (batchIndex == 1) {
      prefix = 'normal#';
    } else if (batchIndex == 2) {
      prefix = 'special#';
    } else {
      prefix = 'batch$batchIndex#';
    }

    for (final category in batch) {
      final categoryName = category['name']!;
      final categoryId = category['id']!;

      categories.add(
        SearchCategoryConfig(
          id: categoryId,
          displayName: batchIndex > 1 ? 's_$categoryName' : categoryName,
          parameters: '{"category":"$prefix$categoryId"}',
        ),
      );
    }
  }
}
