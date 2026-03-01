## 2024-03-21 - RegExp Compilation in Flutter Build Methods
**Learning:** Compiling `RegExp` instances dynamically inside Flutter `build` methods or frequently executed loops (like parsing multiple list items) creates significant CPU overhead and garbage collection pressure, leading to UI jank and dropped frames during scrolling.
**Action:** Always extract static regular expressions to `static final` class variables or top-level variables so they are compiled exactly once.
