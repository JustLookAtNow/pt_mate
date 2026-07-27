# Android 安全存储真机验收

## 两阶段发布开关

第一阶段止血包不得传入事务开关；默认构建会保持
`ENABLE_SECURE_STORAGE_TRANSACTIONS=false`，只执行“敏感值写入并读回后再提交普通配置”的
顺序保护，不创建 revision manifest。

第二阶段候选包在第一阶段完成生产验证后，才使用以下参数构建：

```bash
flutter build apk --release --build-number=<candidate-build> \
  --dart-define=ENABLE_SECURE_STORAGE_TRANSACTIONS=true
```

GitHub 的 `v*` tag 推送**固定发布第一阶段**：工作流会强制
`ENABLE_SECURE_STORAGE_TRANSACTIONS=false`，并直接使用 tag 指向源码中已提交的 `pubspec.yaml`
versionCode；不能通过 tag 名或重跑把它变成第二阶段。

第二阶段只能使用 `workflow_dispatch` 创建一个**全新的手动候选**，并显式填写：

- `source_ref`：已完成审查和真机隔离验收的分支、commit SHA 或候选 ref；
- `tag`：此前不存在的新 `v*` release tag。工作流会在全部构建通过后将它指向 `source_ref`；不要先
  push 这个 tag，否则 tag 触发器会先发布第一阶段；
- `android_build_number`：本次候选的明确 Android versionCode，必须是大于 `183` 的整数；
- `secure_storage_transactions=true`。

手动工作流会拒绝已存在的 tag，并校验 APK 的 versionCode 与输入值完全一致。因此第二阶段不得
对已经自动发布过第一阶段的同一个 tag 重跑；需要新 source 候选、新 tag 和新的验收记录。手动
第一阶段候选同样遵循这套输入和“新 tag”约束。无论自动或手动发布，工作流都会拒绝
`pubspec.yaml` 中的 `version` 与 `tag`/候选 build number 不完全一致的源码。

一旦某设备已经建立 revision manifest，即使随后安装未带开关的兼容构建，也会继续读取并维护现有
manifest，禁止退回直接逻辑键读写。GitHub Release body 与构建摘要会明确记录当前阶段、事务开关、
Android versionCode 和 source commit。

第二阶段在每次 manifest 切换前还会调用 Android 原生落盘屏障。原因是
`flutter_secure_storage` 的密文及首次包装密钥使用异步 `SharedPreferences.apply()`；Dart 读回只能
证明进程内存中的值正确，不能证明强杀时已经落盘。屏障会对算法配置、包装密钥和密文四个专用
SharedPreferences 执行同步 no-op `commit()`，成功后才允许写 companion pending 与 manifest。
屏障失败必须保持旧 manifest 并进入阻断状态，不能继续提交或回退为逐键写入。

本机制只用于验证 OAEP/GCM、PKCS1/GCM 和 PKCS1/CBC 三类历史数据。测试包拥有独立
applicationId，不会读取或修改生产包数据。

> **禁止在生产包上进行故障注入。** 不得删除、替换或篡改
> `com.github.justlookatnow.ptmate` 的安全存储文件或 Android Keystore 密钥。测试开始前仍应
> 确认生产数据已有可用备份。

## 构建并安装隔离测试包

先确定唯一的 `<candidate-build>`（例如 `184`）。同一轮三种算法、第一/第二阶段覆盖安装与最终
生产候选必须使用同一个值；本轮候选源码已统一为 `+184`，不要用旧的 `+159` 去验证手机上的
`+183`。在仓库根目录执行正式串行构建脚本。Flutter 原生输出路径固定为同一个
`build/app/outputs/flutter-apk/app-debug.apk`；因此禁止再手工并发执行三条构建命令或在所有构建
结束后才读取该共享文件。脚本会取得仓库锁、逐个构建、在每次构建后用 `apkanalyzer` 校验
applicationId 与 versionCode，并立刻保存为独立 APK：

```bash
tool/build_secure_storage_test_apks.sh --build-number=<candidate-build> --phase=phase1
```

默认产物目录为
`build/secure-storage-test-apks/phase1/<candidate-build>/`，文件名包含 profile；可用重复的
`--profile=oaepGcm` 只构建一个 profile，也可以用 `--output-dir=<directory>` 保存到指定位置。脚本
只接受三个固定的隔离 profile，任何生成生产 applicationId 或错误 versionCode 的 APK 都会失败且
不会保存。若脚本异常退出，持有的锁会自动释放。

必须通过 Flutter CLI 构建，不能直接调用 `android/gradlew`；后者可能继续使用本机
`android/local.properties` 中的旧版本号，而不是 `pubspec.yaml` 当前构建号。

三个 profile 分别生成以下 applicationId：

| profile | applicationId |
| --- | --- |
| `oaepGcm` | `com.github.justlookatnow.ptmate.securestoragetest.oaepgcm` |
| `pkcs1Gcm` | `com.github.justlookatnow.ptmate.securestoragetest.pkcs1gcm` |
| `pkcs1Cbc` | `com.github.justlookatnow.ptmate.securestoragetest.pkcs1cbc` |

从脚本保存的 profile 专属 APK 安装前，仍要先确认包名不是生产 applicationId：

```bash
test_package=com.github.justlookatnow.ptmate.securestoragetest.oaepgcm
test_apk=build/secure-storage-test-apks/phase1/<candidate-build>/ptmate-secure-storage-oaepGcm-debug-<candidate-build>.apk
apkanalyzer manifest application-id "$test_apk"
apkanalyzer manifest version-code "$test_apk"
adb install -r "$test_apk"
adb shell dumpsys package "$test_package" | grep -E 'versionCode=|versionName='
```

安装前还要把 APK 和安装后 PackageInfo 的 `version-code` 与 `<candidate-build>` 逐字核对；任一项
不一致都停止。生产候选发布前，源码中的 `pubspec.yaml` 也必须提交为相同 build number，不能让
真机验收包、仓库版本和发布 APK 分别使用不同的构建号。

未传 `secureStorageTestProfile` 时，debug 包维持原 applicationId 和正常 OAEP/GCM 新设备
行为。非法 profile 会在 Gradle 配置阶段失败。release 构建始终使用生产 applicationId，测试
profile 和测试后缀常量均为空；即使误传该属性也不能启用覆盖。

## 首次初始化与算法确认

1. 卸载对应测试 applicationId，确保该隔离包处于真正的 fresh 状态；不要卸载生产包。
2. 安装测试 APK 并冷启动。OAEP/GCM 走与生产包一致的 guarded fresh 初始化：原生侧必须再次
   确认没有密文、包装密钥和算法 marker，才使用同步 `commit()` 一次写入 OAEP/GCM 两个非敏感
   marker；Dart 随后重新 probe 并精确确认 profile 后，才允许 `flutter_secure_storage` 创建包装
   密钥。全新 OAEP/GCM 包首启不得先进入阻断页再依赖用户重试。
3. PKCS1/GCM 与 PKCS1/CBC 只在 `DEBUG + 独立测试后缀 + fresh` 同时满足时执行测试 bootstrap，
   在 Flutter 插件首次初始化前用同步 `commit()` 写入对应 marker 并精确复查；release 构建不能
   进入这条路径。三个 profile 的全新测试包首启都不得先进入阻断页，也不得依赖用户重试。生产
   新设备不存在历史 bootstrap，只允许 OAEP/GCM guarded 初始化。
4. 在测试包中新增一个专用测试站点及 Cookie/API Key，然后完全退出应用。
5. 仅查看非敏感算法标记，确认 profile。不要输出 `FlutterSecureStorage.xml` 的内容：

```bash
test_package=com.github.justlookatnow.ptmate.securestoragetest.oaepgcm
adb shell run-as "$test_package" grep FlutterSecureSAlgorithm shared_prefs/FlutterSecureStorageConfiguration:FlutterSecureStorage.xml
```

首次初始化完成后，真实探测不再是 fresh，历史 profile bootstrap 会自动失效；后续启动必须依赖刚创建的
真实算法标记和包装密钥。

## 冷启动、强杀与重启

对每个 profile 分别执行：

```bash
adb shell am force-stop "$test_package"
adb shell monkey -p "$test_package" -c android.intent.category.LAUNCHER 1
```

确认测试站点的 Cookie/API Key 仍可读取。重复两次后，再重启手机并复查。测试过程中检查日志中
没有 `BadPaddingException`、`InvalidKeyException`、`missing_wrapped_key`、迁移或清库提示；不得
记录 Cookie、API Key、站点 ID 或加密条目键名。

## 升级验收

1. 用一个已经包含本隔离 harness 的基线候选和目标 profile 构建、安装测试包并写入专用测试数据。
2. 切换到待验收候选，使用**相同 profile**重新构建；相同 profile 会保持相同 applicationId。
3. 使用 `adb install -r` 覆盖安装，不清除应用数据。
4. 连续执行两次冷启动，再强杀并启动一次；验证 profile 不变且测试 Cookie/API Key 完整。
5. 分别完成三个 profile。不同 profile 使用不同 applicationId，禁止相互覆盖安装。

第二阶段必须在同一个隔离 applicationId 上做“第一阶段写入 → 第二阶段覆盖安装”，不能只验证全新
第二阶段安装。以 OAEP/GCM 为例（另外两个 profile 替换最后一个参数）：

```bash
# 第一步：安装未开启事务的第一阶段包并写入测试站点/Cookie/API Key。
tool/build_secure_storage_test_apks.sh --build-number=<candidate-build> --phase=phase1
adb install -r build/secure-storage-test-apks/phase1/<candidate-build>/ptmate-secure-storage-oaepGcm-debug-<candidate-build>.apk

# 第二步：保持 applicationId 与 build number 一致，覆盖安装事务候选。
tool/build_secure_storage_test_apks.sh --build-number=<candidate-build> --phase=phase2
adb install -r build/secure-storage-test-apks/phase2/<candidate-build>/ptmate-secure-storage-oaepGcm-debug-<candidate-build>.apk
```

覆盖后先核对 `dumpsys package` 的 versionCode/versionName，再执行两次冷启动、一次强杀重启，并
确认敏感值完整。事务暂存/校验/manifest 提交/普通偏好重放/旧密文清理的精确中断点由自动化测试
注入；真机只做非破坏性的随机强杀与升级验证。

不得直接 checkout 一个不含本 Gradle suffix 与原生 fresh/bootstrap 机制的旧提交后执行上述命令：属性会
被忽略，产物可能退回生产 applicationId。确需验证更早代码时，必须先把隔离 harness 单独移植到
基线工作树，并在每一次安装前重新校验 applicationId 与 version-code。

如需模拟配置缺失、包装密钥缺失或迁移中断，只能操作上述 `.securestoragetest.*` 包，并应先复制
其测试数据。验收结束后可卸载三个测试 applicationId；生产包不受影响。

## 生产手机升级验收门禁

当前生产手机安装的是 `+183`，本轮候选源码是 `+184`。旧的 `+159` 不能覆盖安装到该手机，
也不能与 `+183` 的观察结果混作同一次正式验收。发布候选必须使用明确且高于手机现有版本的统一构建号；
APK、安装后 PackageInfo 与验收记录三处构建号必须一致。

确认 WebDAV 备份可用后，生产升级只做非破坏性验证，连续两次冷启动后逐项核对：

- 33 个站点；
- 20 个 Cookie；
- 13 个 API Key；
- Cookie Cloud URL、UUID、password 三项完整；
- WebDAV 明文 fallback 已迁入安全存储并在读回验证后删除；
- 日志没有算法迁移、清库、BadPadding、InvalidKey 或包装密钥缺失。
