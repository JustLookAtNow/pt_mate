import 'package:flutter/material.dart';

import '../services/backup_service.dart';
import '../services/storage/android_secure_storage_profile_resolver.dart';
import '../services/storage/storage_service.dart';

class LegacySecureStorageMigrationPage extends StatefulWidget {
  const LegacySecureStorageMigrationPage({
    super.key,
    required this.failureCode,
    required this.onOpenBackupRestore,
    required this.onMigrationCompleted,
    required this.onDiscardLegacyData,
    this.prepareMigration,
    this.performMigration,
  });

  final String failureCode;
  final VoidCallback onOpenBackupRestore;
  final Future<void> Function() onMigrationCompleted;
  final Future<void> Function() onDiscardLegacyData;
  final Future<LegacyMigrationPreparation?> Function(
    ValueChanged<String> onProgress,
  )?
  prepareMigration;
  final Future<void> Function(LegacyMigrationPreparation preparation)?
  performMigration;

  @override
  State<LegacySecureStorageMigrationPage> createState() =>
      _LegacySecureStorageMigrationPageState();
}

class _LegacySecureStorageMigrationPageState
    extends State<LegacySecureStorageMigrationPage> {
  final StorageService _storage = StorageService.instance;
  late final BackupService _backupService = BackupService(_storage);
  LegacyMigrationBackupExport? _exportedBackup;
  LegacyAndroidMigrationTarget? _target;
  bool _busy = false;
  String? _status;
  String? _error;

  bool get _isResume =>
      widget.failureCode == 'legacy_secure_storage_migration_resume_required' ||
      widget.failureCode == 'secure_storage_missing_requires_restore' ||
      widget.failureCode == 'secure_storage_data_missing_requires_restore';

  Future<void> _exportAndPrepare() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = '正在校验旧安全数据…';
    });
    try {
      void onProgress(String message) {
        if (mounted) setState(() => _status = message);
      }

      final preparation = await (widget.prepareMigration ?? _prepareMigration)(
        onProgress,
      );
      if (preparation == null) {
        if (mounted) setState(() => _status = '已取消导出，旧数据未做任何修改。');
        return;
      }
      if (!mounted) return;
      setState(() {
        _exportedBackup = preparation.exportedBackup;
        _target = preparation.target;
        _status = '备份已导出到：${preparation.exportedBackup.path}';
      });
    } catch (error) {
      if (mounted) setState(() => _error = '无法准备迁移：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<LegacyMigrationPreparation?> _prepareMigration(
    ValueChanged<String> onProgress,
  ) async {
    final snapshot = await _storage.readLegacyAndroidSnapshot();
    final exported = await _backupService.exportLegacyMigrationBackup(
      snapshot.values,
      onProgress: onProgress,
    );
    if (exported == null) return null;
    final target = await _storage.probeLegacyMigrationTarget();
    return LegacyMigrationPreparation(exportedBackup: exported, target: target);
  }

  Future<void> _migrate() async {
    final exported = _exportedBackup;
    final target = _target;
    if (exported == null || target == null) return;
    final plaintext = target == LegacyAndroidMigrationTarget.plaintext;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(plaintext ? '确认改用明文存储' : '确认升级安全存储'),
            content: Text(
              plaintext
                  ? '此设备不支持 OAEP+GCM。继续后，Cookie、API Key 和密码将以明文保存在仅限本应用访问的本地目录中。\n\n'
                        '请确认已经妥善保存刚导出的备份，且不会导出或共享应用数据。'
                  : '应用将清理旧版加密数据，并使用刚导出的备份恢复到 OAEP+GCM 安全存储。\n\n'
                        '迁移完成前请勿关闭应用。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('确认迁移'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() {
      _busy = true;
      _error = null;
      _status = '正在切换安全存储…';
    });
    try {
      final preparation = LegacyMigrationPreparation(
        exportedBackup: exported,
        target: target,
      );
      await (widget.performMigration ?? _performMigration)(preparation);
      if (mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('迁移完成'),
            content: Text(
              '数据已恢复成功。备份文件 ${exported.path} 包含 Cookie、API Key 和密码等明文敏感信息；'
              '确认应用可正常使用后，请从设备中删除该文件。',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('我会删除备份'),
              ),
            ],
          ),
        );
      }
      await widget.onMigrationCompleted();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '迁移未完成：$error';
        _status = '旧存储若已清理，请使用刚导出的备份继续恢复。';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _performMigration(LegacyMigrationPreparation preparation) async {
    await _storage.beginLegacyAndroidMigration(preparation.target);
    if (mounted) setState(() => _status = '正在恢复已校验的备份…');
    final restored = await _backupService.restoreBackup(
      preparation.exportedBackup.backup,
    );
    if (!restored.success) throw BackupException(restored.message);
    await _storage.completeLegacyAndroidMigration();
  }

  Future<void> _confirmDiscard() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('确认永久放弃旧数据'),
            content: const Text('这会永久删除无法读取或尚未备份的 Cookie、API Key 和密码，且无法恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                  foregroundColor: Theme.of(dialogContext).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('永久放弃'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await widget.onDiscardLegacyData();
    } catch (error) {
      if (mounted) setState(() => _error = '无法重置旧数据：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('迁移旧版安全数据')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.enhanced_encryption_outlined,
                        size: 64,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _isResume ? '需要从迁移备份继续恢复' : '检测到旧版加密数据',
                        style: theme.textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isResume
                            ? '旧安全存储已经进入迁移流程。请选择迁移前导出的本地备份，应用会继续初始化目标存储并恢复数据。'
                            : '当前版本不再日常使用旧加密算法。应用会先强制导出完整备份，再迁移到当前设备支持的存储方式。导出完成前不会修改旧数据。',
                        textAlign: TextAlign.center,
                      ),
                      if (_status != null) ...[
                        const SizedBox(height: 16),
                        SelectableText(_status!, textAlign: TextAlign.center),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        SelectableText(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (_isResume)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : widget.onOpenBackupRestore,
                            icon: const Icon(Icons.restore),
                            label: const Text('选择迁移备份并继续'),
                          ),
                        )
                      else ...[
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _exportAndPrepare,
                            icon: const Icon(Icons.save_alt),
                            label: Text(_busy ? '正在处理…' : '第一步：校验并导出本地备份'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy || _exportedBackup == null
                                ? null
                                : _migrate,
                            icon: const Icon(Icons.sync_lock),
                            label: Text(
                              _target == LegacyAndroidMigrationTarget.plaintext
                                  ? '第二步：确认并迁移到明文存储'
                                  : '第二步：确认并升级安全存储',
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _busy ? null : _confirmDiscard,
                        icon: const Icon(Icons.delete_forever_outlined),
                        label: const Text('没有备份，永久放弃旧数据'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LegacyMigrationPreparation {
  const LegacyMigrationPreparation({
    required this.exportedBackup,
    required this.target,
  });

  final LegacyMigrationBackupExport exportedBackup;
  final LegacyAndroidMigrationTarget target;
}
