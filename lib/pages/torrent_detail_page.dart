import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bbcode/flutter_bbcode.dart';
import '../services/api/api_service.dart';
import '../services/storage/storage_service.dart';
import '../services/image_http_client.dart';
import '../models/app_models.dart';
import '../services/qbittorrent/qb_client.dart';
import '../widgets/torrent_download_dialog.dart';

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
      future: ImageHttpClient.instance.fetchImage(imageUrl).then((response) => response.data!),
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
          child: GestureDetector(
            onTap: renderer.peekTapAction(),
            child: image,
          )
        )
      ];
    }

    return [
      WidgetSpan(
        child: image,
      )
    ];
  }
  
  // 显示全屏图片查看器
  void _showFullScreenImage(BuildContext context, List<int> imageData) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FullScreenImageViewer(
          imageData: Uint8List.fromList(imageData),
        ),
        fullscreenDialog: true,
      ),
    );
  }
}

// 全屏图片查看器
class FullScreenImageViewer extends StatefulWidget {
  final Uint8List imageData;
  
  const FullScreenImageViewer({
    super.key,
    required this.imageData,
  });
  
  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  final TransformationController _transformationController = TransformationController();
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
                child: Text(
                  '图片加载失败',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}



class TorrentDetailPage extends StatefulWidget {
  final TorrentItem torrentItem;
  final SiteFeatures siteFeatures;
  final List<QbClientConfig> qbClients;

  const TorrentDetailPage({
    super.key,
    required this.torrentItem,
    required this.siteFeatures,
    required this.qbClients,
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
  late TorrentItem _currentItem;

  @override
  void initState() {
    super.initState();
    _currentItem = widget.torrentItem;
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
      final detail = await ApiService.instance.fetchTorrentDetail(widget.torrentItem.id);
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
      final url = await ApiService.instance.genDlToken(id: _currentItem.id, url: _currentItem.downloadUrl);

      // 2. 弹出对话框让用户选择下载器设置
      if (!mounted) return;
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => TorrentDownloadDialog(
          torrentName: _currentItem.name,
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
          SnackBar(content: Text('已成功发送"${_currentItem.name}"到 ${clientConfig.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败：$e')),
        );
      }
    }
  }

  Future<void> _onToggleCollection() async {
    final newCollectionState = !_currentItem.collection;
    
    // 立即更新UI状态
    if (mounted) {
      setState(() {
        _currentItem = TorrentItem(
          id: _currentItem.id,
          name: _currentItem.name,
          smallDescr: _currentItem.smallDescr,
          discount: _currentItem.discount,
          discountEndTime: _currentItem.discountEndTime,
          downloadUrl: _currentItem.downloadUrl,
          seeders: _currentItem.seeders,
          leechers: _currentItem.leechers,
          sizeBytes: _currentItem.sizeBytes,
          imageList: _currentItem.imageList,
          downloadStatus: _currentItem.downloadStatus,
          collection: newCollectionState,
        );
      });
    }

    // 异步后台请求
    try {
      await ApiService.instance.toggleCollection(
        id: _currentItem.id,
        make: newCollectionState,
      );
    } catch (e) {
      // 请求失败，恢复原状态
      if (mounted) {
        setState(() {
          _currentItem = TorrentItem(
            id: _currentItem.id,
            name: _currentItem.name,
            smallDescr: _currentItem.smallDescr,
            discount: _currentItem.discount,
            discountEndTime: _currentItem.discountEndTime,
            downloadUrl: _currentItem.downloadUrl,
            seeders: _currentItem.seeders,
            leechers: _currentItem.leechers,
            sizeBytes: _currentItem.sizeBytes,
            imageList: _currentItem.imageList,
            downloadStatus: _currentItem.downloadStatus,
            collection: !newCollectionState,
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('收藏操作失败：$e')),
        );
      }
    }
  }



  String preprocessColorTags(String content) {
    // 常见颜色名称到十六进制代码的映射
    final Map<String, String> colorMap = {
      'red': 'FF0000',
      'blue': '0000FF',
      'green': '008000',
      'yellow': 'FFFF00',
      'orange': 'FFA500',
      'purple': '800080',
      'pink': 'FFC0CB',
      'brown': 'A52A2A',
      'black': '000000',
      'white': 'FFFFFF',
      'gray': '808080',
      'grey': '808080',
      'cyan': '00FFFF',
      'magenta': 'FF00FF',
      'lime': '00FF00',
      'navy': '000080',
      'maroon': '800000',
      'olive': '808000',
      'teal': '008080',
      'silver': 'C0C0C0',
      'royalblue': '4169E1',
    };

    // 处理[color=colorname]标签
    return content.replaceAllMapped(
      RegExp(r'\[color=([a-zA-Z]+)\]', caseSensitive: false),
      (match) {
        final colorName = match.group(1)!.toLowerCase();
        final hexColor = colorMap[colorName];
        if (hexColor != null) {
          return '[color=#$hexColor]';
        }
        // 如果找不到对应的颜色，保持原样
        return match.group(0)!;
      },
    );
  }



  Widget buildBBCodeContent(String content) {
    String processedContent = content;
    
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
    
    // 如果显示图片，添加自定义IMG标签处理器
    if (_showImages) {
      stylesheet.tags['img'] = CustomImgTag();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BBCodeText(
          data: processedContent,
          stylesheet: stylesheet,
        ),
        if (!_showImages && _imageUrls.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.image, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
  }
  


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SelectableText(
          widget.torrentItem.name,
          style: TextStyle(
            fontSize: 16, 
            color: Theme.of(context).brightness == Brightness.light 
                ? Theme.of(context).colorScheme.onPrimary 
                : Theme.of(context).colorScheme.onSurface,
          ),
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
                              buildBBCodeContent(_detail?.descr?.toString() ?? '暂无描述'),
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
            backgroundColor: _currentItem.collection ? Colors.red : null,
            tooltip: _currentItem.collection ? '取消收藏' : '收藏',
            child: Icon(
              _currentItem.collection ? Icons.favorite : Icons.favorite_border,
              color: _currentItem.collection ? Colors.white : null,
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