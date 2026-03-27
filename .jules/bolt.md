## 2024-05-24 - [Dart RegExp Performance]
**Learning:** Compiling `RegExp` instances dynamically on hot paths in Dart (such as in `build` methods or frequent string processing like BBCode parsing) bottlenecks UI performance.
**Action:** Always cache `RegExp` instances using `static final` variables or static Maps when working with Flutter/Dart to prevent unnecessary recompilations.

## 2024-05-24 - [NexusPHPWebAdapter Parallel Parsing]
**Learning:** Sequential `await` in loops during HTML parsing in `NexusPHPWebAdapter` causes significant performance bottlenecks when extracting fields from multiple rows.
**Action:** Use `Future.wait` to parallelize independent asynchronous field extraction calls in `NexusPHPWebAdapter._staticParseTotalPages`, `_staticParseTorrentList`, and `_parseCategories`.
