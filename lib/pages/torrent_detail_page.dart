import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import '../services/api/api_client.dart';
import '../services/api/api_service.dart';
import '../services/image_http_client.dart';
import '../services/storage/storage_service.dart';

class TorrentDetailPage extends StatefulWidget {
  final String torrentId;
  final String torrentName;

  const TorrentDetailPage({
    super.key,
    required this.torrentId,
    required this.torrentName,
  });

  @override
  State<TorrentDetailPage> createState() => _TorrentDetailPageState();
}

class _TorrentDetailPageState extends State<TorrentDetailPage> {
  bool _loading = true;
  String? _error;
  TorrentDetail? _detail;
  bool _showImages = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
    _loadAutoLoadImagesSetting();
  }

  Future<void> _loadAutoLoadImagesSetting() async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final autoLoad = await storage.loadAutoLoadImages();
    setState(() {
      _showImages = autoLoad;
    });
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final detail = await ApiService.instance.fetchTorrentDetail(widget.torrentId);
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Widget _buildBBCodeContent(String content) {
    List<Widget> widgets = [];
    List<String> parts = [];
    List<String> imageUrls = [];
    
    // 提取BBCode格式的图片URL
    final imgRegex = RegExp(r'\[img\](.*?)\[\/img\]', caseSensitive: false);
    final imgMatches = imgRegex.allMatches(content);
    
    for (final match in imgMatches) {
      imageUrls.add(match.group(1)!);
    }
    
    // 提取Markdown格式的图片URL
    final markdownImgRegex = RegExp(r'!\[.*?\]\((.*?)\)', caseSensitive: false);
    final markdownImgMatches = markdownImgRegex.allMatches(content);
    
    for (final match in markdownImgMatches) {
      imageUrls.add(match.group(1)!);
    }
    
    // 分割内容，将图片标签替换为占位符
    String processedContent = content;
    int imageIndex = 0;
    
    // 替换BBCode格式的图片
    processedContent = processedContent.replaceAllMapped(imgRegex, (match) {
      return '<<IMAGE_PLACEHOLDER_${imageIndex++}>>';
    });
    
    // 替换Markdown格式的图片
    processedContent = processedContent.replaceAllMapped(markdownImgRegex, (match) {
      return '<<IMAGE_PLACEHOLDER_${imageIndex++}>>';
    });
    
    // 处理其他BBCode标签
    processedContent = processedContent.replaceAll(RegExp(r'\[b\](.*?)\[\/b\]', caseSensitive: false), '**\$1**');
    processedContent = processedContent.replaceAll(RegExp(r'\[i\](.*?)\[\/i\]', caseSensitive: false), '*\$1*');
    processedContent = processedContent.replaceAll(RegExp(r'\[u\](.*?)\[\/u\]', caseSensitive: false), '__\$1__');
    processedContent = processedContent.replaceAll(RegExp(r'\[url=(.*?)\](.*?)\[\/url\]', caseSensitive: false), '[\$2](\$1)');
    processedContent = processedContent.replaceAll(RegExp(r'\[url\](.*?)\[\/url\]', caseSensitive: false), '[\$1](\$1)');
    processedContent = processedContent.replaceAll(RegExp(r'\[color=(.*?)\](.*?)\[\/color\]', caseSensitive: false), '\$2');
    processedContent = processedContent.replaceAll(RegExp(r'\[size=(.*?)\](.*?)\[\/size\]', caseSensitive: false), '\$2');
    
    // 按图片占位符分割文本
    parts = processedContent.split(RegExp(r'<<IMAGE_PLACEHOLDER_\d+>>'));
    
    // 构建Widget列表
    for (int i = 0; i < parts.length; i++) {
      // 添加文本部分
      if (parts[i].trim().isNotEmpty) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SelectableText(
              parts[i].trim(),
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ),
        );
      }
      
      // 添加图片部分
      if (i < imageUrls.length) {
        if (_showImages) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _buildImageWidget(imageUrls[i]),
            ),
          );
        } else {
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
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
                      '图片已隐藏',
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
          );
        }
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
  
  Widget _buildImageWidget(String imageUrl) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 400),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FutureBuilder<Response<List<int>>>(
          future: ImageHttpClient.instance.fetchImage(imageUrl),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text('加载中...'),
                    ],
                  ),
                ),
              );
            }
            
            if (snapshot.hasError) {
              debugPrint('图片加载失败: $imageUrl');
              debugPrint('错误信息: ${snapshot.error}');
              
              return Container(
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: Colors.grey),
                      SizedBox(height: 4),
                      Text('图片加载失败', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              );
            }
            
            if (snapshot.hasData && snapshot.data!.data != null) {
              final imageData = Uint8List.fromList(snapshot.data!.data!);
              final isDarkMode = Theme.of(context).brightness == Brightness.dark;
              
              return GestureDetector(
                onTap: () {
                  _showFullScreenImage(context, imageData);
                },
                child: Stack(
                  children: [
                    Image.memory(
                      imageData,
                      fit: BoxFit.contain,
                    ),
                    // 夜间模式下添加覆盖层
                    if (isDarkMode)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }
            
            return Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Icon(Icons.image, color: Colors.grey),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, Uint8List imageData) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (BuildContext context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  panEnabled: true,
                  scaleEnabled: true,
                  boundaryMargin: EdgeInsets.zero,
                  constrained: true,
                  clipBehavior: Clip.none,
                  minScale: 0.1,
                  maxScale: 4.0,
                  child: Image.memory(
                    imageData,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SelectableText(
          widget.torrentName,
          style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
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
                              _buildBBCodeContent(_detail?.descr ?? '暂无描述'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}