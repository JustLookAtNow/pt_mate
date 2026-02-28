
## $(date +%Y-%m-%d) - [RegExp Recompilation in Hot Paths]
**Learning:** In Dart/Flutter, compiling `RegExp` objects inside frequently executed methods like `build` or loop iterations (e.g., `hasRating` inside `TorrentListItem` which renders repeatedly during list scrolling, or `matchTags` iterating over enum values) causes unnecessary CPU overhead and UI stutters.
**Action:** Extract `RegExp` instantiations to `static final` fields or cache them using a lazy mechanism like a `Map` cache for enum values to prevent repetitive recompilation on hot paths.
