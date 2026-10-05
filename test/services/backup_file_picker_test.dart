import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/backup_service.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:pt_mate/utils/file_picker_utils.dart';

class _FilePicker extends FilePickerPlatform {
  PlatformFile? selectedFile;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => selectedFile;
}

final class _DocumentFile extends PlatformFile {
  final String content;

  _DocumentFile(this.content);

  @override
  String get name => '备份.json';

  @override
  Uri get uri => Uri.parse('content://documents/document/backup.json');

  @override
  Future<Uint8List> readAsBytes() async => utf8.encode(content);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FilePickerPlatform originalPicker;
  late _FilePicker picker;
  final service = BackupService(StorageService.instance);

  setUp(() {
    originalPicker = FilePickerPlatform.instance;
    picker = _FilePicker();
    FilePickerPlatform.instance = picker;
  });

  tearDown(() {
    FilePickerPlatform.instance = originalPicker;
  });

  test('imports a UTF-8 backup from a document without a local path', () async {
    picker.selectedFile = _DocumentFile(
      jsonEncode({
        'version': BackupVersion.current,
        'timestamp': '2026-09-30T12:00:00.000',
        'appVersion': '2.29.1',
        'data': {'name': '中文备份'},
      }),
    );
    expect(picker.selectedFile!.path, isNull);

    final backup = await service.importBackup();

    expect(backup!.version, BackupVersion.current);
    expect(backup.data['name'], '中文备份');
  });

  test('returns null when the user cancels backup selection', () async {
    expect(await service.importBackup(), isNull);
  });

  test('reports an invalid selected backup', () async {
    picker.selectedFile = _DocumentFile('invalid JSON');
    await expectLater(service.importBackup(), throwsA(isA<BackupException>()));
  });

  test('saved file locations retain spaces and Unicode in local paths', () {
    expect(
      filePickerLocation(Uri.file('/tmp/备份文件/my backup.json')),
      '/tmp/备份文件/my backup.json',
    );
  });

  test('saved Android document locations retain their URI', () {
    final uri = Uri.parse('content://documents/document/primary%3Abackup.json');
    expect(filePickerLocation(uri), uri.toString());
  });
}
