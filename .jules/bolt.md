## 2024-05-24 - [Dart RegExp Performance]
**Learning:** Compiling `RegExp` instances dynamically on hot paths in Dart (such as in `build` methods or frequent string processing like BBCode parsing) bottlenecks UI performance.
**Action:** Always cache `RegExp` instances using `static final` variables or static Maps when working with Flutter/Dart to prevent unnecessary recompilations.

## 2024-05-19 - [Test Execution Side Effects]
**Learning:** Running `flutter test` might automatically alter `pubspec.lock` by downgrading transitive dependencies.
**Action:** Always run `git checkout -- pubspec.lock` after tests if dependency changes were not requested to avoid unintended commits.

## 2024-05-19 - [Test Execution Artifacts]
**Learning:** Redirecting test output (e.g. `flutter test > test_output.json`) creates unneeded artifacts that should never be committed to git.
**Action:** Delete any such local text outputs before proceeding with git operations, and verify using `git status` to ensure working tree is clean except for intentional files.
