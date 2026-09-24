import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // 横向滚动条只在桌面平台绘制：移动端（iPad 等）可横滚的 TabBar 紧凑，
    // 滚动条拇指会叠在文字上；触摸/触控板拖动本身即可滚动。
    final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (isDesktop &&
        (details.direction == AxisDirection.left ||
            details.direction == AxisDirection.right)) {
      if (details.controller == null) return child;
      return Scrollbar(
        controller: details.controller,
        interactive: true,
        child: child,
      );
    }
    return super.buildScrollbar(context, child, details);
  }
}
