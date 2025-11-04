import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceIdService {
  static const String _deviceIdKey = 'device_id';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static DeviceIdService? _instance;
  static DeviceIdService get instance => _instance ??= DeviceIdService._();

  DeviceIdService._();

  String? _cachedDeviceId;

  /// 获取设备ID，如果不存在则生成一个新的
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }

    try {
      // 尝试从安全存储中读取
      String? storedDeviceId = await _storage.read(key: _deviceIdKey);
      
      if (storedDeviceId != null && storedDeviceId.isNotEmpty) {
        _cachedDeviceId = storedDeviceId;
        return storedDeviceId;
      }

      // 如果没有存储的设备ID，生成一个新的
      String newDeviceId = await _generateDeviceId();
      
      // 保存到安全存储
      await _storage.write(key: _deviceIdKey, value: newDeviceId);
      
      _cachedDeviceId = newDeviceId;
      return newDeviceId;
    } catch (e) {
      // 如果安全存储失败，使用基于设备信息的ID
      return await _generateFallbackDeviceId();
    }
  }

  /// 生成新的设备ID
  Future<String> _generateDeviceId() async {
    const uuid = Uuid();
    String baseId = uuid.v4();
    
    // 添加平台前缀以便区分
    String platform = _getPlatformName();
    return '${platform}_$baseId';
  }

  /// 生成基于设备信息的备用ID（当安全存储不可用时）
  Future<String> _generateFallbackDeviceId() async {
    try {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      String deviceIdentifier = '';
      
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceIdentifier = '${androidInfo.model}_${androidInfo.id}_${androidInfo.fingerprint}'.hashCode.toString();
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceIdentifier = '${iosInfo.model}_${iosInfo.identifierForVendor}_${iosInfo.systemVersion}'.hashCode.toString();
      } else if (Platform.isLinux) {
        LinuxDeviceInfo linuxInfo = await deviceInfo.linuxInfo;
        deviceIdentifier = '${linuxInfo.machineId}_${linuxInfo.name}'.hashCode.toString();
      } else if (Platform.isMacOS) {
        MacOsDeviceInfo macInfo = await deviceInfo.macOsInfo;
        deviceIdentifier = '${macInfo.systemGUID}_${macInfo.computerName}'.hashCode.toString();
      } else if (Platform.isWindows) {
        WindowsDeviceInfo windowsInfo = await deviceInfo.windowsInfo;
        deviceIdentifier = '${windowsInfo.computerName}_${windowsInfo.userName}'.hashCode.toString();
      } else {
        // Web或其他平台
        const uuid = Uuid();
        deviceIdentifier = uuid.v4();
      }
      
      String platform = _getPlatformName();
      return '${platform}_fallback_$deviceIdentifier';
    } catch (e) {
      // 最后的备用方案
      const uuid = Uuid();
      String platform = _getPlatformName();
      return '${platform}_emergency_${uuid.v4()}';
    }
  }

  /// 获取平台名称
  String _getPlatformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }

  /// 获取平台名称（公共方法）
  String getPlatform() {
    return _getPlatformName();
  }

  /// 重置设备ID（用于测试或重置）
  Future<void> resetDeviceId() async {
    try {
      await _storage.delete(key: _deviceIdKey);
      _cachedDeviceId = null;
    } catch (e) {
      // 忽略删除错误
    }
  }

  /// 检查是否有存储的设备ID
  Future<bool> hasStoredDeviceId() async {
    try {
      String? storedDeviceId = await _storage.read(key: _deviceIdKey);
      return storedDeviceId != null && storedDeviceId.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}