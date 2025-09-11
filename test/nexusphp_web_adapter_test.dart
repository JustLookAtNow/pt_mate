// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'dart:io';

import 'package:pt_mate/services/api/api_client.dart';

void main() {
  group('NexusPHP Web Adapter Tests', () {
    late List<File> htmlFiles;
    late Map<String, String> htmlContents;
    late Map<String, BeautifulSoup> soups;

    setUpAll(() async {
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
        final soup = soups[fileName]!;
        print('\nProcessing file: $fileName');
        if (!fileName.startsWith('torrents')) {
          continue;
        }
        int totalPage = 0;
        final pagination = soup.find('div', id: 'footer')!.find('script')?.text;
        if (pagination != null) {
          print('  Found pagination');
          final pageMatch = RegExp(
            r'var\s+maxpage\s*=\s*(\d+);',
          ).firstMatch(pagination);
          if (pageMatch != null) {
            totalPage = int.parse(pageMatch.group(1) ?? '0');
            print('  Found total page: $totalPage');
          }
        }

        final table = soup.find('table', class_: 'torrents');
        if (table != null) {
          print('  Found torrent table');
          final rows = table.children[0].children;
          print('  Found ${rows.length} torrent rows');

          // 跳过表头行，从第二行开始处理种子数据
          for (int i = 1; i < rows.length; i++) {
            final row = rows[i];
            final tds = row.children;

            if (tds.length > 6) {
            //收藏信息
            final starTd = tds[1].findAll('td')[3];
            final starImg = starTd.find('img', class_: 'delbookmark');
            final collection = starImg == null;
            print('  Found collection: $collection');

              final titleTd = tds[1].findAll('td')[1];

              // 提取种子ID（从详情链接中）
              final detailLink = titleTd.find('a[href*="details.php"]');
              String torrentId = '';
              if (detailLink != null) {
                final href = detailLink.attributes['href'] ?? '';
                final idMatch = RegExp(r'id=(\d+)').firstMatch(href);
                if (idMatch != null) {
                  torrentId = idMatch.group(1) ?? '';
                }
              }

              // 提取主标题（去除换行）
              final titleElement = titleTd.find('a[href*="details.php"] b');
              String title = '';
              if (titleElement != null) {
                title = titleElement.text
                    .replaceAll('\n', ' ')
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim();
              }

              // 提取描述：从tds[1].findAll('td')[1].innerHtml中提取纯文本
              final fullText = titleTd.innerHtml;
              String description = fullText
                  .replaceAll(RegExp(r'<[^>]+>.*?</[^>]+>'), '')
                  .replaceAll(RegExp(r'<[^>]+>'), '')
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .trim();
              // 提取下载记录
              DownloadStatus status = DownloadStatus.none;
              final downloadDiv = titleTd.find('div', attrs: {'title': true});
              if (downloadDiv != null) {
                final downloadTitle = downloadDiv.getAttrValue('title');
                RegExp regExp = RegExp(r'(\d+)\%');
                final match = regExp.firstMatch(downloadTitle!);
                if (match != null) {
                  final percent = match.group(1);
                  if (percent != null) {
                    int percentInt = int.parse(percent);
                    if (percentInt == 100) {
                      status = DownloadStatus.completed;
                    }else{
                      status = DownloadStatus.downloading;
                    }
                  }
                }
              }
              // 提取大小（第5列，索引4）
              String size = tds[4].text.replaceAll('\n', ' ').trim();

              // 提取做种数（第6列，索引5）
              String seeders = '';
              final seedersElement = tds[5].find('a');
              if (seedersElement != null) {
                seeders = seedersElement.text.trim();
              } else {
                final boldElement = tds[5].find('b');
                if (boldElement != null) {
                  seeders = boldElement.text.trim();
                } else {
                  seeders = tds[5].text.trim();
                }
              }

              // 提取下载数（第7列，索引6）
              String leechers = '';
              final leechersElement = tds[6].find('a');
              if (leechersElement != null) {
                leechers = leechersElement.text.trim();
              } else {
                final boldElement = tds[6].find('b');
                if (boldElement != null) {
                  leechers = boldElement.text.trim();
                } else {
                  leechers = tds[6].text.trim();
                }
              }

              // 提取优惠信息
              String promoType = '';
              String remainingTime = '';
              final promoImg = tds[1].find('img[onmouseover]');
              if (promoImg != null) {
                promoType = promoImg.attributes['alt'] ?? '';

                // 提取剩余时间：使用正则表达式匹配"剩余时间：<span title="...">...</span>"
                final timeRegex = RegExp(r'剩余时间：<span[^>]*>([^<]+)</span>');
                final timeMatch = timeRegex.firstMatch(fullText);
                if (timeMatch != null) {
                  remainingTime = timeMatch.group(1)?.trim() ?? '';
                }
              }

              // 输出提取的信息
              if (torrentId.isNotEmpty) {
                print('Torrent ID: $torrentId');
                print('Title: $title');
                print('Description: $description');
                print('Size: $size');
                print('Seeders: $seeders');
                print('Leechers: $leechers');
                if (promoType.isNotEmpty) {
                  print('Promo: $promoType');
                  if (remainingTime.isNotEmpty) {
                    print('Remaining Time: $remainingTime');
                  }
                }
                print('Download Status: $status');
                print('---');

                //只输出前5个种子以避免输出过长
                if (i >= 5) break;
              }
            }
          }
        } else {
          print('  No torrent table found in this file');
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
          final uploadMatch = RegExp(r'上传量:\s*([^\s]+)').firstMatch(textInfo);
          final upload = uploadMatch?.group(1)?.trim();
          final downloadMatch = RegExp(r'下载量:\s*([^\s]+)').firstMatch(textInfo);
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
