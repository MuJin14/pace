import 'package:flutter/material.dart';

/// 可滚动的居中容器：让空态/错误态/加载态等非列表内容也能触发下拉刷新。
///
/// 包裹在 [RefreshIndicator] 内使用，通过 [AlwaysScrollableScrollPhysics]
/// 保证内容不足一屏时仍可下拉。
class ScrollableCenter extends StatelessWidget {
  const ScrollableCenter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}
