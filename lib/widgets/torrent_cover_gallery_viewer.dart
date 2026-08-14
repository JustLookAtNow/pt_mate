import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 种子封面画廊查看器：支持左右翻页查看相邻种子封面。
///
/// 宿主通过 [loadCover] 提供指定位置的数据，通过 [onPageChanged]
/// 感知翻页（用于联动滚动背后的列表）。
class TorrentCoverGalleryViewer extends StatefulWidget {
  final int itemCount;
  final int initialIndex;

  /// 加载指定位置的封面数据；返回 null 表示无法加载（如条目已被移除）。
  final Future<Uint8List?> Function(int position) loadCover;

  /// 获取指定位置的种子标题（用于底部信息展示）。
  final String Function(int position) titleFor;

  /// 翻页回调（position 为新位置）。
  final ValueChanged<int>? onPageChanged;

  const TorrentCoverGalleryViewer({
    super.key,
    required this.itemCount,
    required this.initialIndex,
    required this.loadCover,
    required this.titleFor,
    this.onPageChanged,
  });

  @override
  State<TorrentCoverGalleryViewer> createState() =>
      _TorrentCoverGalleryViewerState();
}

class _TorrentCoverGalleryViewerState extends State<TorrentCoverGalleryViewer> {
  final TransformationController _transformationController =
      TransformationController();
  final FocusNode _focusNode = FocusNode();

  late int _position;
  Uint8List? _imageData;
  bool _isLoading = true;
  Object? _error;
  int _requestToken = 0;
  bool _neighborsPreloaded = false;

  @override
  void initState() {
    super.initState();
    _position = widget.initialIndex;
    _focusNode.requestFocus();
    _loadCurrent();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  Future<void> _fetch(int position, {required bool silent}) async {
    final token = ++_requestToken;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
        _imageData = null;
      });
    }
    try {
      final data = await widget.loadCover(position);
      if (!mounted || token != _requestToken) return;
      if (!silent) {
        setState(() {
          _imageData = data;
          _isLoading = false;
          _error = data == null ? 'missing' : null;
        });
      }
    } catch (e) {
      if (!mounted || token != _requestToken || silent) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }
  }

  void _preloadNeighbors() {
    if (_neighborsPreloaded) return;
    _neighborsPreloaded = true;
    // 前一张通常已在内存缓存（用户刚从列表点开），后一张预取即可
    if (_position + 1 < widget.itemCount) {
      widget.loadCover(_position + 1).then((_) {}, onError: (_) {});
    }
  }

  void _loadCurrent() {
    _fetch(_position, silent: false);
    _preloadNeighbors();
  }

  void _goTo(int position) {
    if (position < 0 || position >= widget.itemCount) return;
    if (position == _position) return;
    setState(() {
      _position = position;
    });
    _resetZoom();
    _loadCurrent();
    widget.onPageChanged?.call(position);
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.physicalKey == PhysicalKeyboardKey.arrowLeft) {
      if (_position > 0) _goTo(_position - 1);
    } else if (event.physicalKey == PhysicalKeyboardKey.arrowRight) {
      if (_position + 1 < widget.itemCount) _goTo(_position + 1);
    }
  }

  void _onDoubleTapAt(Offset position) {
    if (_transformationController.value != Matrix4.identity()) {
      _resetZoom();
    } else {
      const double scale = 2.0;
      final Matrix4 matrix = Matrix4.identity()
        ..setEntry(0, 3, -position.dx)
        ..setEntry(1, 3, -position.dy);
      final Matrix4 scaleMatrix = Matrix4.identity()
        ..setEntry(0, 0, scale)
        ..setEntry(1, 1, scale);
      final Matrix4 translateBack = Matrix4.identity()
        ..setEntry(0, 3, position.dx)
        ..setEntry(1, 3, position.dy);
      _transformationController.value = translateBack * scaleMatrix * matrix;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPrev = _position > 0;
    final canNext = _position + 1 < widget.itemCount;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // 半透明遮罩，点击任意空白处关闭
              const ColoredBox(color: Colors.black54),
              Center(
                child: GestureDetector(
                  onDoubleTapDown: (details) =>
                      _onDoubleTapAt(details.localPosition),
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 0.5,
                    maxScale: 5.0,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    constrained: true,
                    clipBehavior: Clip.none,
                    child: _buildImage(),
                  ),
                ),
              ),
              if (canPrev)
                Align(
                  alignment: Alignment.centerLeft,
                  child: _NavButton(
                    icon: Icons.chevron_left,
                    tooltip: '上一个',
                    onPressed: () => _goTo(_position - 1),
                  ),
                ),
              if (canNext)
                Align(
                  alignment: Alignment.centerRight,
                  child: _NavButton(
                    icon: Icons.chevron_right,
                    tooltip: '下一个',
                    onPressed: () => _goTo(_position + 1),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.7,
                        ),
                        child: Text(
                          '${widget.titleFor(_position)}  (${_position + 1} / ${widget.itemCount})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
    }
    if (_error != null || _imageData == null) {
      return const Center(
        child: Text('图片加载失败', style: TextStyle(color: Colors.white)),
      );
    }
    return Image.memory(
      _imageData!,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) => const Center(
        child: Text('图片加载失败', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.black.withValues(alpha: 0.4),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}
