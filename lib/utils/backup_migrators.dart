/// 数据迁移器接口
abstract class BackupMigrator {
  String get fromVersion;
  String get toVersion;
  
  /// 迁移备份数据
  Map<String, dynamic> migrate(Map<String, dynamic> backupData);
}



/// 1.0.0 迁移到 1.1.0 - 下载器配置重构
class BackupMigratorV100To110 implements BackupMigrator {
  @override
  String get fromVersion => '1.0.0';
  
  @override
  String get toVersion => '1.1.0';
  
  @override
  Map<String, dynamic> migrate(Map<String, dynamic> backupData) {
    final migratedData = Map<String, dynamic>.from(backupData);
    
    // 更新版本号
    migratedData['version'] = toVersion;
    
    // 迁移 qbClientConfigs 到 downloaderConfigs
    if (backupData.containsKey('qbClientConfigs')) {
      final oldConfigs = backupData['qbClientConfigs'] as List<dynamic>?;
      if (oldConfigs != null) {
        final newConfigs = <Map<String, dynamic>>[];
        
        for (final oldConfig in oldConfigs) {
          if (oldConfig is Map<String, dynamic>) {
            // 转换为新的下载器配置格式
             final newConfig = {
               'id': oldConfig['id'] ?? '',
               'name': oldConfig['name'] ?? '',
               'type': 'qbittorrent', // 所有旧配置都是 qBittorrent
               'config': {
                 'host': oldConfig['host'] ?? '',
                 'port': oldConfig['port'] ?? 8080,
                 'username': oldConfig['username'] ?? '',
                 'useLocalRelay': oldConfig['useLocalRelay'] ?? false,
                 'version': oldConfig['version'] ?? '',
               },
             };
            newConfigs.add(newConfig);
          }
        }
        
        // 添加新的下载器配置
        migratedData['downloaderConfigs'] = newConfigs;
        
        // 删除旧配置
        migratedData.remove('qbClientConfigs');
      }
    }
    
    // 迁移 defaultQbId 到 defaultDownloaderId
    if (backupData.containsKey('defaultQbId')) {
      migratedData['defaultDownloaderId'] = backupData['defaultQbId'];
      // 删除旧字段
      migratedData.remove('defaultQbId');
    }
    
    // 迁移 qbPasswords 到 downloaderPasswords
    if (backupData.containsKey('qbPasswords')) {
      migratedData['downloaderPasswords'] = backupData['qbPasswords'];
      // 删除旧字段
      migratedData.remove('qbPasswords');
    }
    
    // 迁移 qbCategoriesCache 到 downloaderCategoriesCache
    if (backupData.containsKey('qbCategoriesCache')) {
      migratedData['downloaderCategoriesCache'] = backupData['qbCategoriesCache'];
      // 删除旧字段
      migratedData.remove('qbCategoriesCache');
    }
    
    // 迁移 qbTagsCache 到 downloaderTagsCache
    if (backupData.containsKey('qbTagsCache')) {
      migratedData['downloaderTagsCache'] = backupData['qbTagsCache'];
      // 删除旧字段
      migratedData.remove('qbTagsCache');
    }
    
    return migratedData;
  }
}

/// 1.1.0 迁移到 1.2.0 - 清理旧qBittorrent数据
class BackupMigratorV110To120 implements BackupMigrator {
  @override
  String get fromVersion => '1.1.0';
  
  @override
  String get toVersion => '1.2.0';
  
  @override
  Map<String, dynamic> migrate(Map<String, dynamic> backupData) {
    final migratedData = Map<String, dynamic>.from(backupData);
    
    // 更新版本号
    migratedData['version'] = toVersion;
    
    // 清理所有旧的qBittorrent相关数据
    final oldKeys = [
      'qbClientConfigs',
      'defaultQbId', 
      'qbPasswords',
      'qbCategoriesCache',
      'qbTagsCache'
    ];
    
    for (final key in oldKeys) {
      migratedData.remove(key);
    }
    
    return migratedData;
  }
}

/// 备份迁移管理器
class BackupMigrationManager {
  static final List<BackupMigrator> _migrators = [
    BackupMigratorV100To110(),
    BackupMigratorV110To120()
  ];
  
  /// 注册迁移器
  static void registerMigrator(BackupMigrator migrator) {
    _migrators.add(migrator);
  }
  
  /// 检查是否需要迁移
  static bool needsMigration(String currentVersion, String targetVersion) {
    return currentVersion != targetVersion && 
           _getMigrationPath(currentVersion, targetVersion).isNotEmpty;
  }
  
  /// 执行迁移
  static Map<String, dynamic> migrate(Map<String, dynamic> backupData, String targetVersion) {
    final currentVersion = backupData['version'] as String? ?? '1.0.0';
    
    if (currentVersion == targetVersion) {
      return backupData;
    }
    
    final migrationPath = _getMigrationPath(currentVersion, targetVersion);
    if (migrationPath.isEmpty) {
      throw Exception('无法找到从版本 $currentVersion 到 $targetVersion 的迁移路径');
    }
    
    var currentData = backupData;
    for (final migrator in migrationPath) {
      currentData = migrator.migrate(currentData);
    }
    
    return currentData;
  }
  
  /// 获取迁移路径
  static List<BackupMigrator> _getMigrationPath(String fromVersion, String toVersion) {
    final path = <BackupMigrator>[];
    var currentVersion = fromVersion;
    
    while (currentVersion != toVersion) {
      final migrator = _migrators.firstWhere(
        (m) => m.fromVersion == currentVersion,
        orElse: () => throw Exception('找不到从版本 $currentVersion 开始的迁移器'),
      );
      
      path.add(migrator);
      currentVersion = migrator.toVersion;
      
      // 防止无限循环
      if (path.length > 10) {
        throw Exception('迁移路径过长，可能存在循环依赖');
      }
    }
    
    return path;
  }
  
  /// 获取所有支持的版本
  static List<String> getSupportedVersions() {
    final versions = <String>{'1.0.0'}; // 基础版本
    
    for (final migrator in _migrators) {
      versions.add(migrator.fromVersion);
      versions.add(migrator.toVersion);
    }
    
    return versions.toList()..sort();
  }
}