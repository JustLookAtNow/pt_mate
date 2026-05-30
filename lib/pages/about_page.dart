import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pt_mate/utils/notification_helper.dart';

import '../services/update_service.dart';
import '../utils/url_launcher_helper.dart';
import '../widgets/qb_speed_indicator.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/update_notification_dialog.dart';

const _repositoryUrl = 'https://github.com/JustLookAtNow/pt_mate';
const _releasesUrl = '$_repositoryUrl/releases';
const _issuesUrl = '$_repositoryUrl/issues';
const _telegramUrl = 'https://t.me/pt_mate';
const _userGuideUrl = '$_repositoryUrl/blob/master/docs/USER_GUIDE.md';
const _siteGuideUrl =
    '$_repositoryUrl/blob/master/docs/SITE_CONFIGURATION_GUIDE.md';
const _licenseUrl = '$_repositoryUrl/blob/master/LICENSE';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    // 进入关于页时自动检查一次更新（静默，无更新不提示）
    _checkUpdateOnEnter();
  }

  Future<void> _loadPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    final buildNumber = packageInfo.buildNumber.trim();
    setState(() {
      _version = buildNumber.isEmpty
          ? 'v${packageInfo.version}'
          : 'v${packageInfo.version}+$buildNumber';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      currentRoute: '/about',
      appBar: AppBar(
        title: const Text('关于'),
        actions: const [QbSpeedIndicator()],
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
      body: _AboutBody(
        version: _version.isEmpty ? '读取中...' : _version,
        onCheckUpdate: _onCheckUpdatePressed,
        onOpenUrl: _openUrl,
        onCopyVersion: _copyVersionInfo,
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    await UrlLauncherHelper.launchBrowser(context, url);
  }

  Future<void> _copyVersionInfo() async {
    final version = _version.isEmpty ? '未知版本' : _version;
    await Clipboard.setData(
      ClipboardData(text: 'PT Mate $version\n$_repositoryUrl'),
    );
    if (!mounted) return;
    NotificationHelper.showInfo(context, '版本信息已复制');
  }

  Future<void> _checkUpdateOnEnter() async {
    try {
      final result = await UpdateService.instance.manualCheckForUpdates();
      if (!mounted || result == null) return;
      final suppressed = await UpdateService.instance
          .isAutoUpdateDialogSuppressed();
      if (!mounted) return;
      if (result.hasUpdate && !suppressed) {
        await UpdateNotificationDialog.show(context, result);
      }
    } catch (e) {
      // 静默失败，不影响用户浏览关于页
    }
  }

  Future<void> _onCheckUpdatePressed() async {
    try {
      final result = await UpdateService.instance.manualCheckForUpdates();
      if (!mounted) return;
      if (result == null) {
        NotificationHelper.showError(context, '检查更新失败，请稍后重试');
        return;
      }
      if (result.hasUpdate) {
        await UpdateNotificationDialog.show(context, result);
      } else {
        NotificationHelper.showInfo(context, '当前已是最新版本');
      }
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '检查更新时发生错误：$e');
    }
  }
}

class _AboutBody extends StatelessWidget {
  const _AboutBody({
    required this.version,
    required this.onCheckUpdate,
    required this.onOpenUrl,
    required this.onCopyVersion,
  });

  final String version;
  final VoidCallback onCheckUpdate;
  final ValueChanged<String> onOpenUrl;
  final VoidCallback onCopyVersion;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _BrandHeader(version: version),
            const SizedBox(height: 16),
            _SectionTitle(
              icon: Icons.system_update_alt_outlined,
              title: '版本与更新',
            ),
            const SizedBox(height: 8),
            _UpdateCard(
              version: version,
              onCheckUpdate: onCheckUpdate,
              onOpenReleases: () => onOpenUrl(_releasesUrl),
            ),
            const SizedBox(height: 16),
            _SectionTitle(icon: Icons.explore_outlined, title: '快捷入口'),
            const SizedBox(height: 8),
            _LinkGrid(onOpenUrl: onOpenUrl),
            const SizedBox(height: 16),
            _SectionTitle(icon: Icons.widgets_outlined, title: '项目能力'),
            const SizedBox(height: 8),
            const _CapabilityGrid(),
            const SizedBox(height: 16),
            _SectionTitle(icon: Icons.info_outline, title: '开源信息'),
            const SizedBox(height: 8),
            _OpenSourceCard(onOpenUrl: onOpenUrl, onCopyVersion: onCopyVersion),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primaryContainer,
              colorScheme.secondaryContainer,
            ],
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Image.asset(
                'assets/logo/pt_mate_icon_opaque.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PT Mate（PT伴侣）',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '私有种子站点浏览、搜索与下载管理工具',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.82,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Chip(
                    avatar: const Icon(Icons.verified_outlined, size: 18),
                    label: Text('当前版本 $version'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({
    required this.version,
    required this.onCheckUpdate,
    required this.onOpenReleases,
  });

  final String version;
  final VoidCallback onCheckUpdate;
  final VoidCallback onOpenReleases;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useVerticalActions = constraints.maxWidth < 520;
            final actions = [
              FilledButton.icon(
                onPressed: onCheckUpdate,
                icon: const Icon(Icons.system_update),
                label: const Text('检查更新'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenReleases,
                icon: const Icon(Icons.open_in_new),
                label: const Text('查看 Releases'),
              ),
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.new_releases_outlined),
                  title: const Text('应用更新'),
                  subtitle: Text('当前安装版本：$version'),
                ),
                const SizedBox(height: 8),
                if (useVerticalActions)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      actions[0],
                      const SizedBox(height: 8),
                      actions[1],
                    ],
                  )
                else
                  Wrap(spacing: 12, runSpacing: 8, children: actions),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LinkGrid extends StatelessWidget {
  const _LinkGrid({required this.onOpenUrl});

  final ValueChanged<String> onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final links = [
      _LinkAction(
        icon: Icons.code,
        title: 'GitHub 仓库',
        subtitle: '查看源码与发布记录',
        url: _repositoryUrl,
      ),
      _LinkAction(
        icon: Icons.forum_outlined,
        title: 'Telegram 群',
        subtitle: '加入官方交流群',
        url: _telegramUrl,
      ),
      _LinkAction(
        icon: Icons.menu_book_outlined,
        title: '使用指南',
        subtitle: '查看功能说明',
        url: _userGuideUrl,
      ),
      _LinkAction(
        icon: Icons.tune_outlined,
        title: '网站配置指南',
        subtitle: '了解站点适配配置',
        url: _siteGuideUrl,
      ),
      _LinkAction(
        icon: Icons.bug_report_outlined,
        title: '反馈问题',
        subtitle: '提交 Issue 或建议',
        url: _issuesUrl,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 2 : 1;
        final itemWidth = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final link in links)
              SizedBox(
                width: itemWidth,
                child: _ActionTile(
                  icon: link.icon,
                  title: link.title,
                  subtitle: link.subtitle,
                  onTap: () => onOpenUrl(link.url),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CapabilityGrid extends StatelessWidget {
  const _CapabilityGrid();

  @override
  Widget build(BuildContext context) {
    const items = [
      _CapabilityItem(
        icon: Icons.travel_explore,
        title: '多站点浏览',
        subtitle: '支持多种 PT 架构',
      ),
      _CapabilityItem(
        icon: Icons.manage_search,
        title: '聚合搜索',
        subtitle: '跨站点快速检索',
      ),
      _CapabilityItem(
        icon: Icons.download_for_offline_outlined,
        title: '下载器集成',
        subtitle: 'qBittorrent / Transmission',
      ),
      _CapabilityItem(
        icon: Icons.cloud_sync_outlined,
        title: 'Cookie Cloud',
        subtitle: '批量同步登录状态',
      ),
      _CapabilityItem(
        icon: Icons.backup_outlined,
        title: '备份恢复',
        subtitle: '支持本地与 WebDAV',
      ),
      _CapabilityItem(
        icon: Icons.public_outlined,
        title: '内置站点配置',
        subtitle: '随应用持续维护',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760
            ? 3
            : constraints.maxWidth >= 520
            ? 2
            : 1;
        final itemWidth = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _CapabilityTile(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _OpenSourceCard extends StatelessWidget {
  const _OpenSourceCard({required this.onOpenUrl, required this.onCopyVersion});

  final ValueChanged<String> onOpenUrl;
  final VoidCallback onCopyVersion;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          _PlainActionTile(
            icon: Icons.balance_outlined,
            title: 'MIT License',
            subtitle: '查看开源许可证',
            onTap: () => onOpenUrl(_licenseUrl),
          ),
          const Divider(height: 1),
          _PlainActionTile(
            icon: Icons.person_outline,
            title: 'JustLookAtNow',
            subtitle: _repositoryUrl,
            onTap: () => onOpenUrl(_repositoryUrl),
          ),
          const Divider(height: 1),
          _PlainActionTile(
            icon: Icons.copy_outlined,
            title: '复制版本信息',
            subtitle: '反馈问题时可一并粘贴',
            onTap: onCopyVersion,
          ),
        ],
      ),
    );
  }
}

class _PlainActionTile extends StatelessWidget {
  const _PlainActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile({required this.item});

  final _CapabilityItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkAction {
  const _LinkAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String url;
}

class _CapabilityItem {
  const _CapabilityItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}
