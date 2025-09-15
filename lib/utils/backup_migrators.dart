/// 数据迁移器接口
abstract class BackupMigrator {
  String get fromVersion;
  String get toVersion;
  
  /// 迁移备份数据
  Map<String, dynamic> migrate(Map<String, dynamic> backupData);
}

/// 从 1.0.0 迁移到 1.1.0
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
    
    // 迁移用户偏好设置 - 添加新的主题设置字段
    if (migratedData.containsKey('userPreferences')) {
      final prefs = Map<String, dynamic>.from(migratedData['userPreferences']);
      
      // 添加动态颜色设置（默认开启）
      if (!prefs.containsKey('useDynamicColor')) {
        prefs['useDynamicColor'] = true;
      }
      
      // 添加种子颜色设置（默认蓝色）
      if (!prefs.containsKey('seedColor')) {
        prefs['seedColor'] = 0xFF2196F3; // Material Blue
      }
      
      migratedData['userPreferences'] = prefs;
    }
    
    // 迁移站点配置 - 添加功能配置字段
    if (migratedData.containsKey('siteConfigs')) {
      final configs = List<Map<String, dynamic>>.from(migratedData['siteConfigs']);
      
      for (var config in configs) {
        // 为旧的站点配置添加默认功能配置
        if (!config.containsKey('features')) {
          config['features'] = {
            'userProfile': true,
            'torrentSearch': true,
            'torrentDetail': true,
            'download': true,
            'favorites': false,
            'downloadHistory': false,
            'categorySearch': true,
            'advancedSearch': true,
          };
        }
      }
      
      migratedData['siteConfigs'] = configs;
    }
    
    return migratedData;
  }
}

/// 从 1.1.0 迁移到 1.2.0
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
    
    // 迁移 QB 客户端配置 - 重构配置结构
    if (migratedData.containsKey('qbClients')) {
      final clients = List<Map<String, dynamic>>.from(migratedData['qbClients']);
      
      for (var client in clients) {
        // 将旧的 host/port 格式迁移到新的 baseUrl 格式
        if (client.containsKey('host') && client.containsKey('port')) {
          final host = client['host'] as String;
          final port = client['port'] as int;
          
          // 构建新的 baseUrl
          String baseUrl;
          if (host.startsWith('http://') || host.startsWith('https://')) {
            baseUrl = '$host:$port';
          } else {
            baseUrl = 'http://$host:$port';
          }
          
          client['baseUrl'] = baseUrl;
          
          // 移除旧字段
          client.remove('host');
          client.remove('port');
        }
        
        // 添加新的配置字段
        if (!client.containsKey('timeout')) {
          client['timeout'] = 30; // 默认30秒超时
        }
        
        if (!client.containsKey('retryCount')) {
          client['retryCount'] = 3; // 默认重试3次
        }
      }
      
      migratedData['qbClients'] = clients;
    }
    
    // 添加新的缓存配置
    if (!migratedData.containsKey('cacheSettings')) {
      migratedData['cacheSettings'] = {
        'maxCacheSize': 100 * 1024 * 1024, // 100MB
        'cacheExpiry': 24 * 60 * 60 * 1000, // 24小时
        'enableImageCache': true,
        'enableDataCache': true,
      };
    }
    
    return migratedData;
  }
}

/// 备份迁移管理器
class BackupMigrationManager {
  static final List<BackupMigrator> _migrators = [
    BackupMigratorV100To110(),
    BackupMigratorV110To120(),
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