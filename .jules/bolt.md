## 2024-05-24 - [Dart RegExp Performance]
**Learning:** Compiling `RegExp` instances dynamically on hot paths in Dart (such as in `build` methods or frequent string processing like BBCode parsing) bottlenecks UI performance.
**Action:** Always cache `RegExp` instances using `static final` variables or static Maps when working with Flutter/Dart to prevent unnecessary recompilations.
