// 统一条件导入接口，防止在 Web 编译目标上无条件导入 dart:io
export 'storage_permission_helper_stub.dart'
    if (dart.library.io) 'storage_permission_helper_io.dart';
