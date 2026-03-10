import 'package:flutter/material.dart';

// 返回按钮组件
class ServerSettingsBackButton extends StatelessWidget {
  const ServerSettingsBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: '返回',
      onPressed: () {
        Navigator.of(context).pop();
      },
    );
  }
}
