import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/image_http_client.dart';

/// 带缓存和请求头的网络图片组件
class CachedNetworkImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget Function(
    BuildContext context,
    Widget child,
    ImageChunkEvent? loadingProgress,
  )?
  loadingBuilder;
  final Widget Function(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  )?
  errorBuilder;

  const CachedNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.loadingBuilder,
    this.errorBuilder,
  });

  @override
  State<CachedNetworkImage> createState() => _CachedNetworkImageState();
}

class _CachedNetworkImageState extends State<CachedNetworkImage> {
  Uint8List? _imageData;
  bool _isLoading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(CachedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (widget.imageUrl.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'Empty URL';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _imageData = null;
    });

    try {
      final response = await ImageHttpClient.instance.fetchImage(
        widget.imageUrl,
      );
      if (response.data != null && mounted) {
        setState(() {
          _imageData = Uint8List.fromList(response.data!);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(context, _error!, null) ??
          _buildDefaultError(context);
    }

    if (_isLoading) {
      return widget.loadingBuilder?.call(context, Container(), null) ??
          _buildDefaultLoading(context);
    }

    if (_imageData != null) {
      final image = Image.memory(
        _imageData!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
      );

      return widget.loadingBuilder?.call(context, image, null) ?? image;
    }

    return widget.errorBuilder?.call(context, 'No image data', null) ??
        _buildDefaultError(context);
  }

  Widget _buildDefaultLoading(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '加载中',
            style: TextStyle(
              fontSize: 8,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultError(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_outlined,
            size: 24,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 4),
          Text(
            '加载失败',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
