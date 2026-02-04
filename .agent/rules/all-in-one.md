---
trigger: always_on
---

不需要帮我启动预览展示，我会自己来启动后验证功能。
如果改了dart代码，修改完毕后使用 flutter analyze 来检查代码是否有问题。
修改包名时使用rename setBundleId --targets android,ios,linux,macos,windows --value "com.github.justlookatnow.ptmate"

"取消"按钮请加上边框线，          
style: TextButton.styleFrom(
            side: BorderSide(
              color: Theme.of(context).colorScheme.outline,
              width: 1.0,
            ),
          ),


不要用color.withOpacity(0.3)语法，因为它已过时，改为color.withValues(alpha: 0.3)

showSnackBar的样式
如果是info就
字体颜色使用： Theme.of(context).colorScheme.onPrimaryContainer,
背景使用: Theme.of(context).colorScheme.primaryContainer,
如果是error就：
字体颜色使用： Theme.of(context).colorScheme.onErrorContainer,
背景使用: Theme.of(context).colorScheme.errorContainer,

Flutter 3.32.0 之后 Radio 的 groupValue 和 onChanged 这种单独管理方式废弃了，官方推荐用 RadioGroup 组件 来统一管理一组单选框的值。

以前的写法（已废弃）：
int? _selected = 1;

Radio<int>(
  value: 1,
  groupValue: _selected,
  onChanged: (val) {
    setState(() {
      _selected = val;
    });
  },
)


在新版里要改成 RadioGroup：

import 'package:flutter/material.dart';

class MyRadioGroupDemo extends StatefulWidget {
  @override
  _MyRadioGroupDemoState createState() => _MyRadioGroupDemoState();
}

class _MyRadioGroupDemoState extends State<MyRadioGroupDemo> {
  int? _selected = 1;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<int>(
      value: _selected,
      onChanged: (val) {
        setState(() {
          _selected = val;
        });
      },
      child: Column(
        children: [
          Radio<int>(value: 1, child: Text('选项 1')),
          Radio<int>(value: 2, child: Text('选项 2')),
          Radio<int>(value: 3, child: Text('选项 3')),
        ],
      ),
    );
  }
}


⚠️ 关键点：

RadioGroup 作为父组件，提供 value 和 onChanged。

里面的每个 Radio 不再需要 groupValue，只需要 value 和 child。

统一的选择状态由 RadioGroup 管理。


当我让你发布release版本时需要做以下事情：
1. 把我要发布的版本号更新到pubspec.yaml文件中，如果用户没提供就用当前版本号加一位小版本。
2. 把这次改动提交成一个新的commit ，commit message 格式为："release: {版本号} 换行 {其它具体内容}"。
   下面的{其它具体内容}由上次release到这次release的所有commit message总结一个发布公告，只总结用户使用中能感知到的，架构层以及纯技术上的东西不用总结。注意有些commit message有多行数据不要只取第一行。
   {其它具体内容}的格式为：
   二级菜单（即markdown中的##），标题名带上emoji表情用于标识发布类型，没有的可以不写，然后下面 使用列表（即markdown中的-）详细描述具体项。
   ## 🎉Highlights（用户说有高亮功能的时候写到这里面，可选）
     - 条目1
     - 条目2
   ## ✨新增功能
   ## 🐛修复问题
   ## 🔧性能优化
   ## 📋其它
如何查找上次的release提交，执行 git log --oneline --grep="^release:" -n 1
特别注意：commit msg 不要使用\n换行，使用真实的换行。
3. 打标签，标签格式为：v版本号，例如：v1.0.0。
4. 带标签推送到github。
其中第二步提交commit前让我确认下消息内容。

## 数据结构变更和备份恢复规则

当修改应用的数据结构时（如 SiteConfig、QbClientConfig 等模型类），必须遵循以下原则：

### 数据迁移原则
- **支持向前兼容**：新版本必须能够读取旧版本的备份文件
- **渐进式迁移**：避免数据丢失，通过版本化迁移逐步升级数据结构
- **版本标识**：每个数据结构变更都应该有对应的版本号（schema version）

### 实现要求
1. **修改数据模型时**：
   - 在 fromJson 方法中添加对旧字段的兼容处理
   - 为新字段提供合理的默认值
   - 保持对未知字段的容错性（忽略而非报错）

2. **备份恢复功能**：
   - 备份文件必须包含版本信息
   - 实现数据迁移器处理版本间转换
   - 支持链式迁移（如 1.0→1.1→1.2）

3. **测试验证**：
   - 确保新版本能正确读取所有历史版本的备份
   - 验证数据迁移过程不会丢失用户数据

### 示例
```dart
// 在模型类中添加版本兼容处理
factory SiteConfig.fromJson(Map<String, dynamic> json) {
  // 处理旧版本字段名变更
  final apiKey = json['apiKey'] ?? json['api_key']; // 兼容旧字段名
  
  // 为新字段提供默认值
  final features = json['features'] != null 
    ? SiteFeatures.fromJson(json['features']) 
    : SiteFeatures.defaultFeatures; // 旧版本没有此字段时使用默认值
    
  return SiteConfig(/* ... */);
}
```