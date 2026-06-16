import 'dart:typed_data';

import 'package:flutter/material.dart';

// 图片查看器（叠加层模式）
class FullScreenImageViewer extends StatefulWidget {
  final Uint8List imageData;

  const FullScreenImageViewer.memory({super.key, required this.imageData});

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

  Widget _buildImage() {
    return Image.memory(
      widget.imageData,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) => const Center(
        child: Text('图片加载失败', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
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
      ),
    );
  }
}
