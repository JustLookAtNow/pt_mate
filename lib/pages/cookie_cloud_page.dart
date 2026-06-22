import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../services/network/cookie_cloud_service.dart';
import '../services/storage/storage_service.dart';
import '../utils/notification_helper.dart';

class CookieCloudPage extends StatefulWidget {
  const CookieCloudPage({super.key});

  @override
  State<CookieCloudPage> createState() => _CookieCloudPageState();
}

class _CookieCloudPageState extends State<CookieCloudPage> {
  final _urlController = TextEditingController();
  final _uuidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _busy = false;
  bool _showPassword = false;
  bool _autoSyncEnabled = false;
  int _syncIntervalMinutes = 360;
  DateTime? _lastSyncAt;
  String _lastSyncSummary = '';
  CookieCloudSyncPlan? _plan;
  final Set<CookieCloudCandidate> _selectedUpdates = {};
  final Set<CookieCloudCandidate> _selectedAdditions = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _uuidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await StorageService.instance.loadCookieCloudConfig();
    if (!mounted) return;
    setState(() {
      _urlController.text = config.url;
      _uuidController.text = config.uuid;
      _passwordController.text = config.password;
      _autoSyncEnabled = config.autoSyncEnabled;
      _syncIntervalMinutes = config.syncIntervalMinutes;
      _lastSyncAt = config.lastSyncAt;
      _lastSyncSummary = config.lastSyncSummary;
      _loading = false;
    });
  }

  CookieCloudConfig _currentConfig() => CookieCloudConfig(
    url: _urlController.text,
    uuid: _uuidController.text,
    password: _passwordController.text,
    autoSyncEnabled: _autoSyncEnabled,
    syncIntervalMinutes: _syncIntervalMinutes,
    lastSyncAt: _lastSyncAt,
    lastSyncSummary: _lastSyncSummary,
  );

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;
    await StorageService.instance.saveCookieCloudConfig(_currentConfig());
    if (!mounted) return;
    NotificationHelper.showInfo(context, 'Cookie Cloud 配置已保存');
  }

  Future<void> _clearConfig() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空 Cookie Cloud 配置'),
        content: const Text('将清空服务器地址、UUID、密码和同步状态，已同步到站点里的 Cookie 不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              side: BorderSide(
                color: Theme.of(context).colorScheme.outline,
                width: 1.0,
              ),
            ),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    const clearedConfig = CookieCloudConfig(
      autoSyncEnabled: false,
      lastSyncSummary: '',
    );
    await StorageService.instance.saveCookieCloudConfig(clearedConfig);
    if (!mounted) return;

    setState(() {
      _urlController.clear();
      _uuidController.clear();
      _passwordController.clear();
      _autoSyncEnabled = false;
      _lastSyncAt = null;
      _lastSyncSummary = '';
      _plan = null;
      _selectedUpdates.clear();
      _selectedAdditions.clear();
    });
    NotificationHelper.showInfo(context, 'Cookie Cloud 配置已清空');
  }

  Future<void> _fetchPlan() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _plan = null;
      _selectedUpdates.clear();
      _selectedAdditions.clear();
    });
    try {
      final config = _currentConfig();
      await StorageService.instance.saveCookieCloudConfig(config);
      final plan = await CookieCloudService().fetchSyncPlan(config);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _selectedUpdates.addAll(plan.updates);
        _selectedAdditions.addAll(plan.additions);
      });
      if (plan.totalCandidates == 0) {
        NotificationHelper.showInfo(context, '未找到可同步的 Cookie');
      } else {
        NotificationHelper.showInfo(context, '已拉取同步预览');
      }
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '同步失败：$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _applyPlan() async {
    final plan = _plan;
    if (plan == null) return;
    if (_selectedUpdates.isEmpty && _selectedAdditions.isEmpty) {
      NotificationHelper.showInfo(context, '请选择要同步的站点');
      return;
    }
    setState(() => _busy = true);
    try {
      final appState = context.read<AppState>();
      final activeSiteId =
          appState.site?.id ?? await StorageService.instance.getActiveSiteId();
      final shouldReloadActiveSite =
          activeSiteId != null &&
          _selectedUpdates.any(
            (candidate) => candidate.site?.id == activeSiteId,
          );
      final result = await CookieCloudService().applyPlan(
        plan,
        selectedUpdates: _selectedUpdates,
        selectedAdditions: _selectedAdditions,
      );
      if (shouldReloadActiveSite) {
        await appState.reloadActiveSite();
      }
      final latest = await StorageService.instance.loadCookieCloudConfig();
      if (!mounted) return;
      setState(() {
        _plan = null;
        _lastSyncAt = latest.lastSyncAt;
        _lastSyncSummary = latest.lastSyncSummary;
      });
      NotificationHelper.showInfo(
        context,
        '同步完成：更新 ${result.updatedCount} 个，新增 ${result.addedCount} 个',
      );
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '写入失败：$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Cookie Cloud 同步')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildConfigCard(context),
            const SizedBox(height: 16),
            if (_lastSyncAt != null || _lastSyncSummary.isNotEmpty)
              _buildStatusCard(context),
            if (_plan != null) ...[
              const SizedBox(height: 16),
              _buildPlanSection(context, _plan!),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _clearConfig,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('清空配置'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _saveConfig,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('保存配置'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : (_plan == null ? _fetchPlan : _applyPlan),
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_plan == null ? Icons.cloud_sync : Icons.done),
                      label: Text(_plan == null ? '拉取预览' : '确认同步'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'https://cookiecloud.example.com',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.dns_outlined),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入服务器地址' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _uuidController,
              decoration: const InputDecoration(
                labelText: 'UUID',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入 UUID' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: '密码',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? '隐藏密码' : '显示密码',
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入密码' : null,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自动静默同步'),
              subtitle: const Text('应用启动或回到前台时按间隔同步已有站点 Cookie'),
              value: _autoSyncEnabled,
              onChanged: (value) => setState(() => _autoSyncEnabled = value),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('同步间隔'),
              subtitle: Text('${_syncIntervalMinutes ~/ 60} 小时'),
              trailing: SizedBox(
                width: 160,
                child: Slider(
                  min: 60,
                  max: 1440,
                  divisions: 23,
                  value: _syncIntervalMinutes.toDouble().clamp(60, 1440),
                  label: '${_syncIntervalMinutes ~/ 60} 小时',
                  onChanged: (value) =>
                      setState(() => _syncIntervalMinutes = value.round()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.history),
        title: Text(
          _lastSyncAt == null
              ? '尚未同步'
              : '上次同步：${_lastSyncAt!.toLocal().toString().substring(0, 16)}',
        ),
        subtitle: _lastSyncSummary.isEmpty ? null : Text(_lastSyncSummary),
      ),
    );
  }

  Widget _buildPlanSection(BuildContext context, CookieCloudSyncPlan plan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCandidateCard(
          context,
          title: '更新已有站点',
          icon: Icons.update,
          candidates: plan.updates,
          selected: _selectedUpdates,
          selectable: true,
        ),
        const SizedBox(height: 12),
        _buildCandidateCard(
          context,
          title: '推荐添加站点',
          icon: Icons.add_circle_outline,
          candidates: plan.additions,
          selected: _selectedAdditions,
          selectable: true,
        ),
        const SizedBox(height: 12),
        _buildCandidateCard(
          context,
          title: '未知站点',
          icon: Icons.help_outline,
          candidates: plan.unknown,
          selected: <CookieCloudCandidate>{},
          selectable: false,
        ),
      ],
    );
  }

  Widget _buildCandidateCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<CookieCloudCandidate> candidates,
    required Set<CookieCloudCandidate> selected,
    required bool selectable,
  }) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text('${candidates.length} 个站点'),
          ),
          if (candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(alignment: Alignment.centerLeft, child: Text('暂无')),
            )
          else
            ...candidates.map(
              (candidate) => CheckboxListTile(
                value: selectable ? selected.contains(candidate) : false,
                onChanged: selectable
                    ? (value) {
                        setState(() {
                          if (value == true) {
                            selected.add(candidate);
                          } else {
                            selected.remove(candidate);
                          }
                        });
                      }
                    : null,
                title: Text(candidate.title),
                subtitle: Text(candidate.host),
                secondary: const Icon(Icons.cookie_outlined),
              ),
            ),
        ],
      ),
    );
  }
}
