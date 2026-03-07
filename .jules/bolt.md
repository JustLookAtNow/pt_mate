
## 2023-11-20 - [Performance] Cache Dynamic RegExps Safely
**Learning:** Dart `RegExp` objects are expensive to compile, especially inside parsing loops like `BaseWebAdapterMixin` parsing HTML DOM trees. Creating static finals helps, but dynamically constructed `RegExp(variable)` also needs a cache. However, an unbounded Map cache is dangerous and can cause memory leaks if user inputs continually generate novel regexes.
**Action:** Always place an upper bound (e.g., `_maxCacheSize = 100`) on dynamic runtime caches like `Map<String, RegExp>`, calling `clear()` or employing an LRU strategy when exceeded.
