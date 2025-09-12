import 'dart:async';
import 'package:flutter/material.dart';

import '../services/storage/storage_service.dart';
import '../services/qbittorrent/qb_client.dart';
import '../utils/format.dart';
import '../pages/downloader_settings_page.dart';

// 右上角全局：默认下载器传输信息，每5秒刷新
class QbSpeedIndicator extends StatefulWidget {
  const QbSpeedIndicator({super.key});

  @override
  State<QbSpeedIndicator> createState() => _QbSpeedIndicatorState();
}

class _QbSpeedIndicatorState extends State<QbSpeedIndicator> {
  Timer? _timer;
  QbTransferInfo? _info;
  QbServerState? _serverState;
  String? _err;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final defId = await StorageService.instance.loadDefaultQbId();
      if (defId == null) {
        setState(() {
          _err = '未设置默认下载器';
          _info = null;
          _serverState = null;
        });
        return;
      }
      final clients = await StorageService.instance.loadQbClients();
      final c = clients.firstWhere(
        (e) => e.id == defId,
        orElse: () =>
            clients.isNotEmpty ? clients.first : throw Exception('未找到默认下载器'),
      );
      final pwd = await StorageService.instance.loadQbPassword(c.id);
      if ((pwd ?? '').isEmpty) {
        setState(() {
          _err = '未保存密码';
          _info = null;
          _serverState = null;
        });
        return;
      }
      
      // 同时获取传输信息和服务器状态
      final futures = await Future.wait([
        QbService.instance.fetchTransferInfo(config: c, password: pwd!),
        QbService.instance.fetchServerState(config: c, password: pwd),
      ]);
      
      if (!mounted) return;
      setState(() {
        _info = futures[0] as QbTransferInfo;
        _serverState = futures[1] as QbServerState;
        _err = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = '获取失败';
        _info = null;
        _serverState = null;
      });
    }
  }

  void _openDownloader() {
    if (!mounted) return;
    
    // 检查当前是否已经在下载器设置页面
    final currentRoute = ModalRoute.of(context);
    if (currentRoute != null && currentRoute.settings.name == '/downloader_settings') {
      return; // 已经在下载器设置页面，不需要重复打开
    }
    
    Navigator.of(
      context,
    ).push(MaterialPageRoute(
      builder: (_) => const DownloaderSettingsPage(),
      settings: const RouteSettings(name: '/downloader_settings'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_err != null) {
      return IconButton(
        onPressed: _openDownloader,
        icon: Icon(
          Icons.error_outline,
          color: Theme.of(context).colorScheme.error,
        ),
        tooltip: _err,
      );
    }
    if (_info == null || _serverState == null) {
      return IconButton(
        onPressed: _openDownloader,
        icon: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        tooltip: '加载中...',
      );
    }
    final info = _info!;
    final serverState = _serverState!;
    return InkWell(
      onTap: _openDownloader,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_download,
                  size: 16,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
                const SizedBox(width: 4),
                Text(
                  '↑${Formatters.speedFromBytesPerSec(info.upSpeed)} ↓${Formatters.speedFromBytesPerSec(info.dlSpeed)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '剩余空间: ${Formatters.dataFromBytes(serverState.freeSpaceOnDisk)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}