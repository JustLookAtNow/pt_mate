import '../../models/app_models.dart';
import 'downloader_models.dart';

/// 抽象下载器客户端接口
///
/// 所有下载器实现都必须实现这个接口，提供统一的API
abstract class DownloaderClient {
  /// 测试连接
  ///
  /// 验证下载器配置是否正确，能否成功连接
  Future<void> testConnection();

  /// 获取传输信息
  ///
  /// 返回当前的上传下载速度和总量信息
  Future<TransferInfo> getTransferInfo();

  /// 获取服务器状态
  ///
  /// 返回服务器的状态信息，如磁盘空间等
  Future<ServerState> getServerState();

  /// 获取下载任务列表
  ///
  /// [params] 查询参数，包括过滤条件、分页等
  Future<List<DownloadTask>> getTasks([GetTasksParams? params]);

  /// 添加下载任务
  ///
  /// [params] 添加任务的参数，包括URL、分类、标签等
  /// [siteConfig] 站点配置，用于需要Cookie鉴权的下载
  Future<void> addTask(AddTaskParams params, {SiteConfig? siteConfig});

  /// 暂停下载任务
  ///
  /// [hashes] 要暂停的任务哈希列表
  Future<void> pauseTasks(List<String> hashes);

  /// 恢复下载任务
  ///
  /// [hashes] 要恢复的任务哈希列表
  Future<void> resumeTasks(List<String> hashes);

  /// 删除下载任务
  ///
  /// [hashes] 要删除的任务哈希列表
  /// [deleteFiles] 是否同时删除文件
  Future<void> deleteTasks(List<String> hashes, {bool deleteFiles = false});

  /// 获取分类列表
  ///
  /// 返回下载器中配置的所有分类
  Future<List<String>> getCategories();

  /// 获取标签列表
  ///
  /// 返回下载器中配置的所有标签
  Future<List<String>> getTags();

  /// 获取版本信息
  ///
  /// 返回下载器的版本号
  Future<String> getVersion();

  /// 获取现有下载路径列表
  ///
  /// 返回下载器中已存在的下载路径
  Future<List<String>> getPaths();

  /// 暂停单个任务的便捷方法
  Future<void> pauseTask(String hash) async {
    await pauseTasks([hash]);
  }

  /// 恢复单个任务的便捷方法
  Future<void> resumeTask(String hash) async {
    await resumeTasks([hash]);
  }

  /// 删除单个任务的便捷方法
  Future<void> deleteTask(String hash, {bool deleteFiles = false}) async {
    await deleteTasks([hash], deleteFiles: deleteFiles);
  }
}
