// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:pt_mate/models/app_models.dart';
import 'dart:io';

import 'package:pt_mate/services/api/nexusphp_web_adapter.dart';

void main() {
  group('NexusPHP Web Adapter Tests', () {
    late List<File> htmlFiles;
    late Map<String, String> htmlContents;
    late Map<String, BeautifulSoup> soups;
    late NexusPHPWebAdapter adapter;

    setUpAll(() async {
      adapter = NexusPHPWebAdapter();
      // 遍历html文件夹中的所有HTML文件
      final htmlDir = Directory('test/html');
      htmlFiles = htmlDir
          .listSync()
          .where((entity) => entity is File && entity.path.endsWith('.html'))
          .cast<File>()
          .toList();

      htmlContents = {};
      soups = {};

      for (final file in htmlFiles) {
        final fileName = file.path.split('/').last;
        final content = await file.readAsString();
        htmlContents[fileName] = content;
        soups[fileName] = BeautifulSoup(content);
      }

      print('Found ${htmlFiles.length} HTML files in test/html directory');
      for (final file in htmlFiles) {
        print('  - ${file.path.split('/').last}');
      }
    });

    test('should parse all HTML files successfully', () {
      expect(htmlFiles, isNotEmpty);
      expect(htmlContents, isNotEmpty);
      expect(soups, isNotEmpty);

      print('\n=== HTML Files Parsing Results ===');
      for (final fileName in htmlContents.keys) {
        final content = htmlContents[fileName]!;
        print('File: $fileName');
        print('  Content length: ${content.length} characters');
        print('  Soup created: ${soups[fileName] != null}');
      }
    });

    test('should extract torrent data from all applicable files', () {
      print('\n=== Torrent Data Extraction ===');

      for (final fileName in soups.keys) {
        print('\nProcessing file: $fileName');
        if (!fileName.startsWith('torrents')) {
          continue;
        }
        final soup = soups[fileName]!;
        List<TorrentItem> torrents = adapter.parseTorrentList(soup);
        print('  Found ${torrents.length} torrents');
        int totalPages = adapter.parseTotalPages(soup);
        print('  Total pages: $totalPages');
        for (var torrent in torrents.take(5)) {
          print('  ID: ${torrent.id}');
          print('  标题: ${torrent.name}');
          print('  副标题: ${torrent.smallDescr}');
          print('  优惠类型: ${torrent.discount}');
          print('  优惠结束时间: ${torrent.discountEndTime ?? "无"}');
          print('  下载链接: ${torrent.downloadUrl ?? "无"}');
          print('  做种数: ${torrent.seeders}');
          print('  下载数: ${torrent.leechers}');
          print('  大小(字节): ${torrent.sizeBytes}');
          print('  图片列表: ${torrent.imageList}');
          print('  下载状态: ${torrent.downloadStatus}');
          print('  是否收藏: ${torrent.collection}');
          print('  ---');
        }
      }
    });

    test('should extract user information from all applicable files', () {
      print('\n=== User Information Extraction ===');

      for (final fileName in soups.keys) {
        if (!fileName.startsWith('usercp2')) {
          continue;
        }
        final soup = soups[fileName]!;
        print('\nProcessing file: $fileName');

        var settingInfoTds = soup
            .find('td', id: 'outer')!
            .children[2]
            .findAll('td');
        var passkeyTd = false;
        var passKey = '';
        for (var td in settingInfoTds) {
          if (passkeyTd) {
            print(td.text);
            passKey = td.text.trim();
            break;
          }
          if (td.text.contains('密钥')) {
            passkeyTd = true;
          }
        }
        print('  Passkey: $passKey');
        var userInfo = soup
            .find('table', id: 'info_block')!
            .find('span', class_: 'medium');

        if (userInfo != null) {
          final allLink = userInfo.findAll('a');
          // 过滤 href 中含有 "abc" 的
          for (var a in allLink) {
            final href = a.attributes['href'];
            if (href != null && href.contains('userdetails.php?id=')) {
              RegExp regExp = RegExp(r'userdetails.php\?id=(\d+)');
              final match = regExp.firstMatch(href);
              if (match != null) {
                print('  User ID: ${match.group(1)}');
              }
            }
          }

          final username = userInfo.find('span')!.a!.b!.text.trim();
          final textInfo = userInfo.text.trim();
          print('  Username: $username');
          print('  Text Info: $textInfo');
          final ratioMatch = RegExp(r'分享率:\s*([^\s]+)').firstMatch(textInfo);
          final ratio = ratioMatch?.group(1)?.trim();
          final uploadMatch = RegExp(r'上传量:\s*(.*?B)').firstMatch(textInfo);
          final upload = uploadMatch?.group(1)?.trim();
          final downloadMatch = RegExp(r'下载量:\s*(.*?B)').firstMatch(textInfo);
          final download = downloadMatch?.group(1)?.trim();
          final bonusMatch = RegExp(
            r':\s*([^\s]+)\s*\[签到',
          ).firstMatch(textInfo);
          final bonus = bonusMatch?.group(1)?.trim();

          print('  Username: $username');
          print('  Ratio: $ratio');
          print('  Upload: $upload');
          print('  Download: $download');
          print('  Bonus: $bonus');
        } else {
          print('  No user information found in this file');
        }
      }
    });
    test('categories information', () {
      print('\n=== Categories Information Extraction ===');
      //#outer > table:nth-child(3) > tbody > tr:nth-child(2) > td.rowfollow > table:nth-child(1) > tbody > tr:nth-child(2)
      //#outer > table:nth-child(3) > tbody > tr:nth-child(2) > td.rowfollow > table:nth-child(3) > tbody > tr:nth-child(2)
      for (final fileName in soups.keys) {
        final soup = soups[fileName]!;
        print('\nProcessing file: $fileName');
        if (!fileName.startsWith('usercp')) {
          continue;
        }
        // 提取分类信息：按行分组存储，并提取分类ID
        final outerElement = soup.find('#outer');
        if (outerElement != null) {
          final tables = outerElement.findAll('table');

          if (tables.length >= 2) {
            final table2 = tables[1]; // 第2个table（索引1）
            final infoTables = table2.findAll('table');
            int batchIndex = 1;
            var currentBatch = <Map<String, String>>[];
            for (final tdinfoTable in infoTables) {
              final rows = tdinfoTable.findAll('tr');
              for (int i = 0; i < rows.length; i++) {
                final row = rows[i];
                final tds = row.findAll('td');
                var hasCategories = false;

                if (tds.isNotEmpty) {
                  for (final td in tds) {
                    final img = td.find('img');
                    final checkbox = td.find('input[type="checkbox"]');
                    hasCategories = false;
                    if (img != null) {
                      final alt = img.attributes['alt'] ?? '';
                      final title = img.attributes['title'] ?? '';
                      final categoryName = alt.isNotEmpty ? alt : title;
                      final categoryId = checkbox?.attributes['id'] ?? '';

                      if (categoryName.isNotEmpty && categoryId.isNotEmpty) {
                        currentBatch.add({
                          'name': categoryName,
                          'id': categoryId,
                        });
                        hasCategories = true;
                      }
                    }
                  }
                }

                // 如果当前行没有分类信息，输出当前批次（如果有内容）
                if (!hasCategories) {
                  if (currentBatch.isNotEmpty) {
                    print(
                      '  Batch $batchIndex (${currentBatch.length} categories):',
                    );
                    for (final category in currentBatch) {
                      print(
                        '    - ${category['name']} (ID: ${category['id']})',
                      );
                    }
                    batchIndex++;
                    currentBatch.clear();
                  }
                }
              }
            }

            // 处理最后一个批次（如果还有未输出的分类）
            if (currentBatch.isNotEmpty) {
              print('  Batch $batchIndex (${currentBatch.length} categories):');
              for (final category in currentBatch) {
                print('    - ${category['name']} (ID: ${category['id']})');
              }
            }
          }
        }
      }
    });
  });
}
