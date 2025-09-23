import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:flutter_bbcode/flutter_bbcode.dart';
import 'package:bbob_dart/bbob_dart.dart' as bbob;
import '../services/api/api_service.dart';
import '../services/storage/storage_service.dart';
import '../services/image_http_client.dart';
import '../models/app_models.dart';
import '../services/qbittorrent/qb_client.dart';
import '../widgets/torrent_download_dialog.dart';

// 自定义Quote标签处理器
class CustomQuoteTag extends WrappedStyleTag {
  final TextStyle headerTextStyle;

  CustomQuoteTag({this.headerTextStyle = const TextStyle()}) : super("quote");

  @override
  List<InlineSpan> wrap(
    FlutterRenderer renderer,
    bbob.Element element,
    List<InlineSpan> spans,
  ) {
    String? author = element.attributes.isNotEmpty
        ? element.attributes.values.first
        : null;

    return [
      WidgetSpan(
        child: CustomQuoteDisplay(
          author: author,
          headerTextStyle: headerTextStyle,
          content: spans,
        ),
      ),
    ];
  }
}

class CustomQuoteDisplay extends StatelessWidget {
  final String? author;
  final TextStyle headerTextStyle;
  final List<InlineSpan> content;

  const CustomQuoteDisplay({
    super.key,
    required this.content,
    this.author,
    this.headerTextStyle = const TextStyle(),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 引用标识头部
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.format_quote,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  author != null ? '$author 说:' : '引用',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.primary,
                  ).merge(headerTextStyle),
                ),
              ],
            ),
          ),
          // 引用内容
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            child: RichText(
              text: TextSpan(
                children: content,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 自定义IMG标签处理器
class CustomImgTag extends AdvancedTag {
  CustomImgTag() : super("img");

  @override
  List<InlineSpan> parse(FlutterRenderer renderer, element) {
    if (element.children.isEmpty) {
      return [TextSpan(text: "[$tag]")];
    }

    // 图片URL是第一个子节点的文本内容
    String imageUrl = element.children.first.textContent;

    final image = FutureBuilder<List<int>>(
      future: ImageHttpClient.instance
          .fetchImage(imageUrl)
          .then((response) => response.data!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 200,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Text("[$tag]");
        }

        final imageWidget = Image.memory(
          Uint8List.fromList(snapshot.data!),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => Text("[$tag]"),
        );

        // 添加点击全屏查看功能
        return GestureDetector(
          onTap: () {
            _showFullScreenImage(context, snapshot.data!);
          },
          child: imageWidget,
        );
      },
    );

    if (renderer.peekTapAction() != null) {
      return [
        WidgetSpan(
          child: GestureDetector(onTap: renderer.peekTapAction(), child: image),
        ),
      ];
    }

    return [WidgetSpan(child: image)];
  }

  // 显示全屏图片查看器
  void _showFullScreenImage(BuildContext context, List<int> imageData) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            FullScreenImageViewer(imageData: Uint8List.fromList(imageData)),
        fullscreenDialog: true,
      ),
    );
  }
}

// 全屏图片查看器
class FullScreenImageViewer extends StatefulWidget {
  final Uint8List imageData;

  const FullScreenImageViewer({super.key, required this.imageData});

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  final TransformationController _transformationController =
      TransformationController();
  bool _isZoomed = false;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
    setState(() {
      _isZoomed = false;
    });
  }

  void _onDoubleTapAt(Offset position) {
    if (_isZoomed) {
      // 如果已经放大，则重置
      _transformationController.value = Matrix4.identity();
      setState(() {
        _isZoomed = false;
      });
    } else {
      // 双击放大到2倍，以双击点为中心
      final double scale = 2.0;

      // 创建以点击位置为中心的缩放变换矩阵
      // 使用组合变换：平移 -> 缩放 -> 平移回去
      final Matrix4 matrix = Matrix4.identity();

      // 先平移使点击点到原点
      matrix.setEntry(0, 3, -position.dx);
      matrix.setEntry(1, 3, -position.dy);

      // 然后缩放
      final Matrix4 scaleMatrix = Matrix4.identity();
      scaleMatrix.setEntry(0, 0, scale);
      scaleMatrix.setEntry(1, 1, scale);

      // 再平移回去
      final Matrix4 translateBack = Matrix4.identity();
      translateBack.setEntry(0, 3, position.dx);
      translateBack.setEntry(1, 3, position.dy);

      // 组合变换：translateBack * scaleMatrix * matrix
      final Matrix4 finalMatrix = translateBack * scaleMatrix * matrix;

      _transformationController.value = finalMatrix;
      setState(() {
        _isZoomed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _resetZoom,
            tooltip: '重置缩放',
          ),
        ],
      ),
      body: Center(
        child: GestureDetector(
          onDoubleTapDown: (details) => _onDoubleTapAt(details.localPosition),
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 0.5,
            maxScale: 5.0,
            constrained: true,
            clipBehavior: Clip.none,
            child: Image.memory(
              widget.imageData,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => const Center(
                child: Text('图片加载失败', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 自定义Hide标签处理器
class CustomHideTag extends WrappedStyleTag {
  CustomHideTag() : super("hide");

  @override
  List<InlineSpan> wrap(
    FlutterRenderer renderer,
    bbob.Element element,
    List<InlineSpan> spans,
  ) {
    return [
      WidgetSpan(
        child: CustomHideDisplay(
          content: spans,
        ),
      ),
    ];
  }
}

class CustomHideDisplay extends StatefulWidget {
  final List<InlineSpan> content;

  const CustomHideDisplay({
    super.key,
    required this.content,
  });

  @override
  State<CustomHideDisplay> createState() => _CustomHideDisplayState();
}

class _CustomHideDisplayState extends State<CustomHideDisplay> {
  bool _isVisible = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isVisible = !_isVisible;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            // 内容层
            Container(
              padding: const EdgeInsets.all(8),
              child: RichText(
                text: TextSpan(
                  children: widget.content,
                  style: DefaultTextStyle.of(context).style,
                ),
              ),
            ),
            // 毛玻璃遮罩层
            if (!_isVisible)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.visibility,
                              size: 16,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '点击显示隐藏内容',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// 自定义Size标签处理器
class CustomSizeTag extends WrappedStyleTag {
  CustomSizeTag() : super("size");

  @override
  List<InlineSpan> wrap(
    FlutterRenderer renderer,
    bbob.Element element,
    List<InlineSpan> spans,
  ) {
    // 获取size属性值
    String? sizeValue = element.attributes['size'];
    if (sizeValue == null || sizeValue.isEmpty) {
      // 如果没有size属性，尝试从第一个属性值中获取
      if (element.attributes.isNotEmpty) {
        sizeValue = element.attributes.values.first;
      } else {
        sizeValue = '14';
      }
    }

    // 解析size值并确定字体大小
    double fontSize = _parseSizeValue(sizeValue);

    // 应用字体大小样式到所有子span
    return spans.map((span) {
      if (span is TextSpan) {
        return TextSpan(
          text: span.text,
          style: (span.style ?? const TextStyle()).copyWith(fontSize: fontSize),
          children: span.children,
        );
      }
      return span;
    }).toList();
  }

  // 解析size值并返回对应的字体大小
  double _parseSizeValue(String sizeValue) {
    // 移除可能的等号和空格
    sizeValue = sizeValue.replaceAll('=', '').trim();

    // 尝试解析为数字
    final double? numValue = double.tryParse(sizeValue);
    if (numValue == null) {
      return 12.8; // 默认字体大小 (14.0 * 0.8)
    }

    if (numValue < 10) {
      // 值在10以下：按照HTML <font> 标签 size 属性映射，统一缩小到80%
      // Font=1:8px, Font=2:10.4px, Font=3:12.8px, Font=4:14.4px, Font=5:19.2px, Font=6:25.6px, Font=7:38.4px
      switch (numValue.toInt()) {
        case 1: return 8.0;   // 10.0 * 0.8
        case 2: return 10.4;  // 13.0 * 0.8
        case 3: return 12.8;  // 16.0 * 0.8
        case 4: return 14.4;  // 18.0 * 0.8
        case 5: return 19.2;  // 24.0 * 0.8
        case 6: return 25.6;  // 32.0 * 0.8
        case 7: return 38.4;  // 48.0 * 0.8
        default: return 12.8; // 默认为 size=3 的大小 (16.0 * 0.8)
      }
    } else if (numValue <= 100) {
      // 值在10-100：作为px绝对值，缩小到80%
      return numValue * 0.8;
    } else {
      // 值大于100：作为百分比倍数（除以100后乘以基础字体大小），缩小到80%
      return 12.8 * (numValue / 100); // 11.2 = 14.0 * 0.8
    }
  }
}

class TorrentDetailPage extends StatefulWidget {
  final TorrentItem torrentItem;
  final SiteFeatures siteFeatures;
  final List<QbClientConfig> qbClients;
  final SiteConfig? siteConfig; // 可选的站点配置，用于聚合搜索

  const TorrentDetailPage({
    super.key,
    required this.torrentItem,
    required this.siteFeatures,
    required this.qbClients,
    this.siteConfig, // 可选参数
  });

  @override
  State<TorrentDetailPage> createState() => _TorrentDetailPageState();
}

class _TorrentDetailPageState extends State<TorrentDetailPage> {
  bool _loading = true;
  String? _error;
  dynamic _detail;
  bool _showImages = false;
  final List<String> _imageUrls = [];
  late bool _isCollected; // 分离收藏状态为独立变量
  
  // BBCode渲染缓存
  String? _cachedRawContent;
  Widget? _cachedBBCodeWidget;

  @override
  void initState() {
    super.initState();
    _isCollected = widget.torrentItem.collection;
    _loadDetail();
    _loadAutoLoadImagesSetting();
  }

  Future<void> _loadAutoLoadImagesSetting() async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final autoLoad = await storage.loadAutoLoadImages();
    if (mounted) {
      setState(() {
        _showImages = autoLoad;
      });
    }
  }

  Future<void> _loadDetail() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final detail = await ApiService.instance.fetchTorrentDetail(
        widget.torrentItem.id,
        siteConfig: widget.siteConfig, // 传入站点配置
      );
      if (mounted) {
        setState(() {
          _detail = detail;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _onDownload() async {
    try {
      // 1. 获取下载 URL
      final url = await ApiService.instance.genDlToken(
        id: widget.torrentItem.id,
        url: widget.torrentItem.downloadUrl,
        siteConfig: widget.siteConfig, // 传入站点配置
      );

      // 2. 弹出对话框让用户选择下载器设置
      if (!mounted) return;
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => TorrentDownloadDialog(
          torrentName: widget.torrentItem.name,
          downloadUrl: url,
        ),
      );

      if (result == null) return; // 用户取消了

      // 3. 从对话框结果中获取设置
      final clientConfig = result['clientConfig'] as QbClientConfig;
      final password = result['password'] as String;
      final category = result['category'] as String?;
      final tags = result['tags'] as List<String>?;
      final savePath = result['savePath'] as String?;
      final autoTMM = result['autoTMM'] as bool?;

      // 4. 发送到 qBittorrent
      await QbService.instance.addTorrentByUrl(
        config: clientConfig,
        password: password,
        url: url,
        category: category,
        tags: tags,
        savePath: savePath,
        autoTMM: autoTMM,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已成功发送"${widget.torrentItem.name}"到 ${clientConfig.name}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              '下载失败：$e',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _onToggleCollection() async {
    final newCollectionState = !_isCollected;

    // 立即更新UI状态 - 只更新收藏状态变量
    if (mounted) {
      setState(() {
        _isCollected = newCollectionState;
      });
    }

    // 异步后台请求
    try {
      await ApiService.instance.toggleCollection(
        id: widget.torrentItem.id,
        make: newCollectionState,
      );
      
      // 请求成功，直接更新传入的torrentItem对象
      widget.torrentItem.collection = newCollectionState;
    } catch (e) {
      // 请求失败，恢复原状态 - 只恢复收藏状态变量
      if (mounted) {
        setState(() {
          _isCollected = !newCollectionState;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              '收藏操作失败：$e',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
          ),
        );
      }
    }
  }

  String preprocessColorTags(String content) {
    // 常见颜色名称到十六进制代码的映射
    final Map<String, String> colorMap = {
      'red': '#FF0000',
      'blue': '#0000FF',
      'green': '#008000',
      'yellow': '#FFFF00',
      'orange': '#FFA500',
      'purple': '#800080',
      'pink': '#FFC0CB',
      'brown': '#A52A2A',
      'black': '#000000',
      'white': '#FFFFFF',
      'gray': '#808080',
      'grey': '#808080',
      'cyan': '#00FFFF',
      'magenta': '#FF00FF',
      'lime': '#00FF00',
      'navy': '#000080',
      'maroon': '#800000',
      'olive': '#808000',
      'teal': '#008080',
      'silver': '#C0C0C0',
      'royalblue': '#4169E1',
    };

    // 处理[color=colorname]标签
    return content.replaceAllMapped(
      RegExp(r'\[color=([a-zA-Z]+)\]', caseSensitive: false),
      (match) {
        final colorName = match.group(1)!.toLowerCase();
        final hexColor = colorMap[colorName];
        if (hexColor != null) {
          return '[color=$hexColor]';
        }
        // 如果找不到对应的颜色，使用黑色
        return '[color=#000000]';
      },
    );
  }

  String _fixBBCodeErrors(String content) {
    String fixed = content;

    // 第一步：修复大小写问题（保持IMG标签，因为BBCode解析器支持）
    // 不需要强制转换为小写，解析器本身支持大小写

    // 第二步：清理无效的标签结构
    fixed = _cleanInvalidTags(fixed);

    // 第三步：修复未闭合的标签
    fixed = _fixUnclosedTags(fixed);

    return fixed;
  }

  String _cleanInvalidTags(String content) {
    final tagStack = <String>[];
    final result = StringBuffer();
    final allMatches = RegExp(r'\[(/?)(\w+)(?:=[^\]]+)?\]').allMatches(content);

    // 定义自闭合标签（不需要结束标签的标签）
    // 注意：BBCode中的img标签实际上需要闭合标签，所以不应该放在这里
    final selfClosingTags = {'br', 'hr'};

    int lastEnd = 0;

    for (final match in allMatches) {
      // 添加标签之前的文本
      result.write(content.substring(lastEnd, match.start));

      final isClosing = match.group(1) == '/';
      final tagName = match.group(2)!.toLowerCase();
      final fullMatch = match.group(0)!;

      if (isClosing) {
        // 处理结束标签
        if (tagStack.contains(tagName)) {
          // 找到对应的开始标签
          final index = tagStack.lastIndexOf(tagName);

          // 如果不是最后一个标签（存在嵌套错误）
          if (index != tagStack.length - 1) {
            // 只删除非自闭合的嵌套错误标签
            final tagsToRemove = <String>[];
            for (int i = index + 1; i < tagStack.length; i++) {
              final tag = tagStack[i];
              if (!selfClosingTags.contains(tag)) {
                tagsToRemove.add(tag);
              }
            }
            if (tagsToRemove.isNotEmpty) {
              debugPrint('删除嵌套错误的标签: $tagsToRemove');
            }
            // 从栈中移除这些标签
            tagStack.removeWhere((tag) => tagsToRemove.contains(tag));
          }

          // 输出当前结束标签
          result.write(fullMatch);

          // 从栈中移除当前标签
          final currentIndex = tagStack.lastIndexOf(tagName);
          if (currentIndex >= 0) {
            tagStack.removeAt(currentIndex);
          }
        } else {
          // 没有对应的开始标签，删除这个结束标签
          debugPrint('删除无效的结束标签: $fullMatch');
          // 不输出这个标签
        }
      } else {
        // 处理开始标签
        if (selfClosingTags.contains(tagName)) {
          // 自闭合标签，直接输出，不加入栈
          result.write(fullMatch);
        } else {
          // 普通标签，添加到栈和结果中
          tagStack.add(tagName);
          result.write(fullMatch);
        }
      }

      lastEnd = match.end;
    }

    // 添加剩余的文本
    result.write(content.substring(lastEnd));

    // 对于未闭合的标签，我们在_fixUnclosedTags中处理

    return result.toString();
  }

  String _fixUnclosedTags(String content) {
    final tagStack = <Map<String, dynamic>>[];
    final allMatches = RegExp(r'\[(/?)(\w+)(?:=[^\]]+)?\]').allMatches(content);
    final result = StringBuffer();

    // 定义自闭合标签（不需要结束标签的标签）
    final selfClosingTags = {'br', 'hr'};

    int lastEnd = 0;

    for (final match in allMatches) {
      // 添加标签之前的文本
      result.write(content.substring(lastEnd, match.start));

      final isClosing = match.group(1) == '/';
      final tagName = match.group(2)!.toLowerCase();
      final fullMatch = match.group(0)!;

      if (isClosing) {
        // 遇到结束标签时，需要先闭合所有在它之前未闭合的标签
        final tagsToClose = <String>[];
        bool foundMatchingTag = false;

        // 从栈顶开始查找匹配的开始标签
        for (int i = tagStack.length - 1; i >= 0; i--) {
          final stackTag = tagStack[i];
          if (stackTag['name'] == tagName) {
            foundMatchingTag = true;
            // 移除找到的标签
            tagStack.removeAt(i);
            break;
          } else {
            // 记录需要先闭合的标签
            tagsToClose.add(stackTag['name']);
          }
        }

        if (foundMatchingTag) {
          // 先闭合所有嵌套在内部的标签
          for (final tagToClose in tagsToClose) {
            result.write('[/$tagToClose]');
            debugPrint('自动闭合嵌套标签: [/$tagToClose]');
            // 从栈中移除这些标签
            tagStack.removeWhere((tag) => tag['name'] == tagToClose);
          }

          // 然后添加当前的结束标签
          result.write(fullMatch);
        } else {
          // 没有找到匹配的开始标签，这个结束标签是无效的
          // 在_cleanInvalidTags中应该已经处理过了，但为了安全起见还是输出
          result.write(fullMatch);
        }
      } else {
        // 开始标签
        if (!selfClosingTags.contains(tagName)) {
          tagStack.add({
            'name': tagName,
            'fullTag': fullMatch,
            'position': match.start,
          });
        }
        result.write(fullMatch);
      }

      lastEnd = match.end;
    }

    // 添加剩余的文本
    result.write(content.substring(lastEnd));

    // 为栈中剩余的标签（未闭合的标签）按照正确的嵌套顺序添加结束标签
    // 最后打开的标签应该最先闭合（LIFO - Last In, First Out）
    for (int i = tagStack.length - 1; i >= 0; i--) {
      final tag = tagStack[i];
      final tagName = tag['name'];
      result.write('[/$tagName]');
      debugPrint('为文档末尾未闭合的标签添加结束标签: [/$tagName] (原标签: ${tag['fullTag']})');
    }

    return result.toString();
  }

  void _analyzeTagStructure(String content) {
    debugPrint('--- 标签结构分析 ---');

    final allMatches = RegExp(r'\[(/?)(\w+)(?:=[^\]]+)?\]').allMatches(content);
    final tagStack = <String>[];
    final errors = <String>[];

    int lineNumber = 1;
    int columnNumber = 1;
    int lastIndex = 0;

    for (final match in allMatches) {
      // 计算行号和列号
      final beforeMatch = content.substring(lastIndex, match.start);
      final lines = beforeMatch.split('\n');
      if (lines.length > 1) {
        lineNumber += lines.length - 1;
        columnNumber = lines.last.length + 1;
      } else {
        columnNumber += beforeMatch.length;
      }

      final isClosing = match.group(1) == '/';
      final tagName = match.group(2)!.toLowerCase();
      final fullMatch = match.group(0)!;

      debugPrint('第$lineNumber行第$columnNumber列: $fullMatch');

      if (isClosing) {
        if (tagStack.contains(tagName)) {
          final index = tagStack.lastIndexOf(tagName);
          if (index != tagStack.length - 1) {
            // 标签顺序错误
            final expectedTag = tagStack.last;
            errors.add(
              '第$lineNumber行第$columnNumber列: 标签顺序错误，遇到[/$tagName]但期望[/$expectedTag]',
            );
          }
          tagStack.removeRange(index, tagStack.length);
        } else {
          errors.add('第$lineNumber行第$columnNumber列: 找不到对应的开始标签[$tagName]');
        }
      } else {
        tagStack.add(tagName);
      }

      lastIndex = match.end;
      columnNumber += match.group(0)!.length;
    }

    // 检查未闭合的标签
    for (final tag in tagStack) {
      errors.add('标签[$tag]没有闭合');
    }

    if (errors.isNotEmpty) {
      debugPrint('发现的错误:');
      for (final error in errors) {
        debugPrint('  • $error');
      }
    } else {
      debugPrint('标签结构正常');
    }

    debugPrint('当前标签栈: $tagStack');
  }

  Widget buildBBCodeContent(String content) {
    // 检查缓存是否有效
    final cacheKey = '$content|$_showImages'; // 包含显示图片状态的缓存键
    if (_cachedRawContent == cacheKey && _cachedBBCodeWidget != null) {
      return _cachedBBCodeWidget!;
    }

    String processedContent = content;

    // 修复常见的BBCode格式错误
    processedContent = _fixBBCodeErrors(processedContent);

    // 预处理Markdown格式的图片，转换为BBCode格式
    processedContent = processedContent.replaceAllMapped(
      RegExp(r'!\[.*?\]\(([^)]+)\)'),
      (match) => '[img]${match.group(1)}[/img]',
    );

    // 预处理Markdown格式的粗体，转换为BBCode格式
    processedContent = processedContent.replaceAllMapped(
      RegExp(r'\*\*([^*]+)\*\*'),
      (match) => '[b]${match.group(1)}[/b]',
    );

    // 预处理[*]标签，转换为BBCode粗体格式
    processedContent = processedContent.replaceAllMapped(
      RegExp(r'\[\*\]([^\[]*?)(?=\[|\s*$)', dotAll: true),
      (match) => '[b]${match.group(1)?.trim() ?? ''}[/b]',
    );

    // 预处理[url][img][/img][/url]嵌套标签，提取图片URL
    processedContent = processedContent.replaceAllMapped(
      RegExp(
        r'\[url\=[^\]]*\](.*?)\[/url\]',
        caseSensitive: false,
        dotAll: true,
      ),
      (match) => match.group(1)!,
    );

    // 预处理[code]标签，转换为等宽字体显示
    processedContent = processedContent.replaceAllMapped(
      RegExp(
        r'\[code\]\s*(.*?)\s*\[/code\]',
        caseSensitive: false,
        dotAll: true,
      ),
      (match) =>
          '[font=monospace][color=#666666]${match.group(1)}[/color][/font]',
    );
    // 提取图片URL用于统计
    _imageUrls.clear();
    final imgRegex = RegExp(r'\[img\]([^\]]+)\[/img\]', caseSensitive: false);
    for (final match in imgRegex.allMatches(processedContent)) {
      _imageUrls.add(match.group(1)!);
    }

    // 预处理颜色标签
    processedContent = preprocessColorTags(processedContent);

    // 如果不显示图片，替换图片标签为占位符
    if (!_showImages && _imageUrls.isNotEmpty) {
      processedContent = processedContent.replaceAllMapped(imgRegex, (match) {
        return '[图片已隐藏]';
      });
    }

    // 创建自定义样式表
    final stylesheet = defaultBBStylesheet(
      textStyle: const TextStyle(fontSize: 14, height: 1.5),
    ).copyWith(selectableText: true);

    // 添加自定义Quote标签处理器
    stylesheet.tags['quote'] = CustomQuoteTag();
    stylesheet.tags['QUOTE'] = CustomQuoteTag();

    // 如果显示图片，添加自定义IMG标签处理器
    if (_showImages) {
      stylesheet.tags['img'] = CustomImgTag();
      stylesheet.tags['IMG'] = CustomImgTag();
    }
    // 添加自定义size标签处理逻辑
    stylesheet.tags['size'] = CustomSizeTag();
    stylesheet.tags['SIZE'] = CustomSizeTag();
    
    // 添加自定义hide标签处理逻辑
    stylesheet.tags['hide'] = CustomHideTag();
    stylesheet.tags['HIDE'] = CustomHideTag();

    // 构建最终的Widget
    final widget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 添加调试信息
        if (kDebugMode) ...[
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.yellow.withValues(alpha: 0.3),
              border: Border.all(color: Colors.orange),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BBCode调试信息:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('原始内容长度: ${(_detail?.descr?.length ?? 0)}'),
                Text('处理后内容长度: ${processedContent.length}'),
                Text('是否包含BBCode标签: ${processedContent.contains('[')}'),
                Text(
                  '是否包含图片标签: ${processedContent.toLowerCase().contains('[img]')}',
                ),
                Text(
                  '是否包含引用标签: ${processedContent.toLowerCase().contains('[quote]')}',
                ),
                Text('图片URL数量: ${_imageUrls.length}'),
                Text('样式表标签数量: ${stylesheet.tags.length}'),

                // 显示所有支持的BBCode标签
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '支持的标签: ${stylesheet.tags.keys.join(', ')}',
                    style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),

                // 检测BBCode标签模式和错误
                Builder(
                  builder: (context) {
                    // 检测所有开始标签
                    final openTags = RegExp(
                      r'\[(\w+)(?:=[^\]]+)?\]',
                    ).allMatches(processedContent);
                    final foundOpenTags = openTags
                        .map((match) => match.group(1))
                        .toList();

                    // 检测所有结束标签
                    final closeTags = RegExp(
                      r'\[/(\w+)\]',
                    ).allMatches(processedContent);
                    final foundCloseTags = closeTags
                        .map((match) => match.group(1))
                        .toList();

                    // 检查标签匹配
                    final tagCounts = <String, int>{};
                    for (final tag in foundOpenTags) {
                      tagCounts[tag!] = (tagCounts[tag] ?? 0) + 1;
                    }
                    for (final tag in foundCloseTags) {
                      tagCounts[tag!] = (tagCounts[tag] ?? 0) - 1;
                    }

                    final unmatchedTags = tagCounts.entries
                        .where((e) => e.value != 0)
                        .toList();
                    final hasErrors = unmatchedTags.isNotEmpty;

                    // 检测嵌套错误
                    final nestingErrors = <String>[];

                    // 检测常见的嵌套错误模式
                    if (RegExp(
                      r'\[quote\][^\[]*\[b\][^\[]*\[color[^\]]*\][^\[]*\[size[^\]]*\][^\[]*\[/quote\]',
                    ).hasMatch(processedContent)) {
                      nestingErrors.add('quote标签内嵌套了b/color/size标签但没有正确闭合');
                    }

                    if (RegExp(r'\[IMG\]').hasMatch(processedContent)) {
                      nestingErrors.add('发现大写IMG标签，应该使用小写img');
                    }

                    if (RegExp(
                      r'\[size\][^\[]*\[/size\]',
                    ).hasMatch(processedContent)) {
                      nestingErrors.add('发现空的size标签');
                    }

                    // 检测标签顺序错误
                    final orderErrors = <String>[];
                    final tagStack = <String>[];
                    final allMatches = RegExp(
                      r'\[/?\w+(?:=[^\]]+)?\]',
                    ).allMatches(processedContent);

                    for (final match in allMatches) {
                      final fullTag = match.group(0)!;
                      if (fullTag.startsWith('[/')) {
                        // 结束标签
                        final tagName = fullTag
                            .substring(2, fullTag.length - 1)
                            .toLowerCase();
                        if (tagStack.isNotEmpty &&
                            tagStack.last.toLowerCase() == tagName) {
                          tagStack.removeLast();
                        } else {
                          orderErrors.add(
                            '标签顺序错误：遇到$fullTag但期望的是${tagStack.isNotEmpty ? "[/${tagStack.last}]" : "无开始标签"}',
                          );
                        }
                      } else {
                        // 开始标签
                        final tagName = fullTag.substring(
                          1,
                          fullTag.contains('=')
                              ? fullTag.indexOf('=')
                              : fullTag.length - 1,
                        );
                        tagStack.add(tagName);
                      }
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: foundOpenTags.isEmpty
                                ? Colors.red.withValues(alpha: 0.1)
                                : Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '检测到的开始标签: ${foundOpenTags.isEmpty ? "无" : foundOpenTags.toSet().join(', ')}',
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: foundCloseTags.isEmpty
                                ? Colors.red.withValues(alpha: 0.1)
                                : Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '检测到的结束标签: ${foundCloseTags.isEmpty ? "无" : foundCloseTags.toSet().join(', ')}',
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        if (hasErrors)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.red),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '⚠️ 标签匹配错误:',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                                ...unmatchedTags.map(
                                  (entry) => Text(
                                    '${entry.key}: ${entry.value > 0 ? "缺少${entry.value}个结束标签" : "多了${-entry.value}个结束标签"}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (nestingErrors.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.orange),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '⚠️ 嵌套问题:',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                  ),
                                ),
                                ...nestingErrors.map(
                                  (error) => Text(
                                    '• $error',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      color: Colors.orange[700],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (orderErrors.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.purple),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '⚠️ 标签顺序错误:',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple,
                                  ),
                                ),
                                ...orderErrors
                                    .take(3)
                                    .map(
                                      (error) => Text(
                                        '• $error',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontFamily: 'monospace',
                                          color: Colors.purple[700],
                                        ),
                                      ),
                                    ),
                                if (orderErrors.length > 3)
                                  Text(
                                    '• ... 还有${orderErrors.length - 3}个错误',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      color: Colors.purple[700],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),

                if (processedContent.length < 500)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '内容预览:\n$processedContent',
                      style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                if (processedContent.isEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '⚠️ 内容为空！原始数据: ${_detail?.descr ?? "null"}',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),

                // 添加控制台日志输出按钮
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        debugPrint('=== BBCode Debug Info ===');
                        debugPrint('原始内容长度: ${_detail?.descr?.length ?? 0}');
                        debugPrint('处理后内容长度: ${processedContent.length}');
                        debugPrint('图片URLs数量: ${_imageUrls.length}');
                        debugPrint('样式表标签: ${stylesheet.tags.keys.toList()}');

                        // 输出内容的前500个字符用于调试
                        final originalContent =
                            _detail?.descr?.toString() ?? '';
                        debugPrint('--- 原始内容预览 ---');
                        debugPrint(
                          originalContent.length > 500
                              ? '${originalContent.substring(0, 500)}...'
                              : originalContent,
                        );

                        debugPrint('--- 处理后内容预览 ---');
                        debugPrint(
                          processedContent.length > 500
                              ? '${processedContent.substring(0, 500)}...'
                              : processedContent,
                        );

                        // 调用详细的标签结构分析
                        _analyzeTagStructure(processedContent);

                        debugPrint('========================');
                      },
                      child: Text('输出到控制台', style: TextStyle(fontSize: 12)),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        debugPrint('=== BBCode 修复功能测试 ===');

                        // 测试1: 图像标签测试（包括大小写）
                        final imgTest =
                            '[img]https://example.com/test1.jpg[/img] [IMG]https://example.com/test2.jpg[/IMG]';
                        debugPrint('图像标签测试:');
                        debugPrint('原始: $imgTest');
                        final processedImg = _fixBBCodeErrors(imgTest);
                        debugPrint('处理后: $processedImg');
                        _analyzeTagStructure(processedImg);

                        debugPrint('---');

                        // 测试2: 标签嵌套错误测试
                        final nestingTest = '[b][color=red]文本[/b][/color]';
                        debugPrint('标签嵌套错误测试:');
                        debugPrint('原始: $nestingTest');
                        final processedNesting = _fixBBCodeErrors(nestingTest);
                        debugPrint('处理后: $processedNesting');
                        _analyzeTagStructure(processedNesting);

                        debugPrint('---');

                        // 测试3: 无效结束标签测试
                        final invalidEndTest = '文本[/color]更多文本[/size]';
                        debugPrint('无效结束标签测试:');
                        debugPrint('原始: $invalidEndTest');
                        final processedInvalid = _fixBBCodeErrors(
                          invalidEndTest,
                        );
                        debugPrint('处理后: $processedInvalid');
                        _analyzeTagStructure(processedInvalid);

                        debugPrint('---');

                        // 测试4: 未闭合标签测试
                        final unclosedTest = '[b]粗体文本[color=red]红色文本';
                        debugPrint('未闭合标签测试:');
                        debugPrint('原始: $unclosedTest');
                        final processedUnclosed = _fixBBCodeErrors(
                          unclosedTest,
                        );
                        debugPrint('处理后: $processedUnclosed');
                        _analyzeTagStructure(processedUnclosed);

                        debugPrint('---');

                        // 测试5: 用户报告的具体案例
                        final userCaseTest =
                            '[URL=https://imgbox.com/uWAzQP5s][IMG]https://thumbs2.imgbox.com/61/46/uWAzQP5s_t.jpg[/IMG][/URL]';
                        debugPrint('用户报告案例测试:');
                        debugPrint('原始: $userCaseTest');
                        final processedUserCase = _fixBBCodeErrors(
                          userCaseTest,
                        );
                        debugPrint('处理后: $processedUserCase');
                        _analyzeTagStructure(processedUserCase);

                        debugPrint('---');

                        // 测试6: 智能标签闭合测试（用户真实案例）
                        final smartClosingTest =
                            '[quote][b][color=Red][size=6] XXXHD original works,XXXHD and XXXHD exclusive! Please do not upload outside here! [/quote]';
                        debugPrint('智能标签闭合测试:');
                        debugPrint('原始: $smartClosingTest');
                        final processedSmart = _fixBBCodeErrors(
                          smartClosingTest,
                        );
                        debugPrint('处理后: $processedSmart');
                        _analyzeTagStructure(processedSmart);

                        debugPrint('---');

                        // 测试7: 复杂嵌套标签测试
                        final complexTest =
                            '[quote] [b][color=#cc33ff][size=6]XXXHD独占发布，禁止转载！[/b] [/quote]';
                        debugPrint('复杂嵌套标签测试:');
                        debugPrint('原始: $complexTest');
                        final processedComplex = _fixBBCodeErrors(complexTest);
                        debugPrint('处理后: $processedComplex');
                        _analyzeTagStructure(processedComplex);

                        // 测试8: Size标签测试（倍数、px、百分比）
                        final sizeTest1 = '[size=2]这是2倍大小的文字[/size]';
                        final sizeTest2 = '[size=16]这是16px大小的文字[/size]';
                        final sizeTest3 = '[size=150]这是150%大小的文字[/size]';
                        final sizeTest4 = '[size=0.5]这是0.5倍大小的文字[/size]';
                        debugPrint('Size标签测试:');
                        debugPrint('倍数测试: $sizeTest1');
                        debugPrint('px测试: $sizeTest2');
                        debugPrint('百分比测试: $sizeTest3');
                        debugPrint('小数倍数测试: $sizeTest4');

                        // 测试9: Size标签嵌套测试
                        final sizeNestedTest =
                            '[size=3][b]粗体大字[/b][/size] 普通文字 [size=0.8][i]斜体小字[/i][/size]';
                        debugPrint('Size嵌套测试: $sizeNestedTest');

                        debugPrint('=== 测试完成 ===');
                      },
                      child: Text('测试BBCode', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        Container(
          // 添加边框来查看BBCodeText的实际占用空间
          decoration: kDebugMode
              ? BoxDecoration(border: Border.all(color: Colors.red, width: 1))
              : null,
          child: BBCodeText(data: processedContent, stylesheet: stylesheet),
        ),
        if (!_showImages && _imageUrls.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.image,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_imageUrls.length} 张图片已隐藏',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showImages = true;
                        // 清除缓存，因为图片显示状态改变了
                        _cachedRawContent = null;
                        _cachedBBCodeWidget = null;
                      });
                    },
                    child: const Text('显示'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    // 更新缓存并返回widget
    _cachedRawContent = cacheKey;
    _cachedBBCodeWidget = widget;
    return widget;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SelectableText(
          widget.torrentItem.name.length > 50 
              ? '${widget.torrentItem.name.substring(0, 50)}...'
              : widget.torrentItem.name,
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).brightness == Brightness.light
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurface,
            overflow: TextOverflow.ellipsis,
          ),
          maxLines: 2,
        ),
        backgroundColor: Theme.of(context).brightness == Brightness.light
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surface,
        iconTheme: IconThemeData(
          color: Theme.of(context).brightness == Brightness.light
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurface,
        ),
        titleTextStyle: TextStyle(
          color: Theme.of(context).brightness == Brightness.light
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('加载失败: $_error'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadDetail,
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info, color: Colors.blue),
                              const SizedBox(width: 8),
                              const Text(
                                '种子详情',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              if (!_showImages)
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _showImages = true;
                                    });
                                  },
                                  icon: const Icon(Icons.image),
                                  label: const Text('显示图片'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          buildBBCodeContent(
                            _detail?.descr?.toString() ?? '暂无描述',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // 收藏按钮
          FloatingActionButton(
            heroTag: "favorite",
            onPressed: _onToggleCollection,
            backgroundColor: _isCollected ? Colors.red : null,
            tooltip: _isCollected ? '取消收藏' : '收藏',
            child: Icon(
              _isCollected ? Icons.favorite : Icons.favorite_border,
              color: _isCollected ? Colors.white : null,
            ),
          ),
          const SizedBox(height: 16),
          // 下载按钮
          FloatingActionButton(
            heroTag: "download",
            onPressed: _onDownload,
            tooltip: '下载',
            child: const Icon(Icons.download_outlined),
          ),
        ],
      ),
    );
  }
}
