import 'dart:io';

import 'package:flutter/foundation.dart';

import 'platform_paths.dart';

/// 最近一条动作日志：设置/探索页可实时显示「当前在做什么」。
final appStatusNotifier = ValueNotifier<String?>(null);

/// 轻量文件日志（appStorageDirectory/app_log.txt）：登录、Cloudflare 验证
/// 等无控制台可看的链路排障用。常开，超过 256KB 自动截断重写。
Future<void> appLog(String message) async {
  appStatusNotifier.value = message;
  try {
    final directory = await appStorageDirectory();
    final file = File('${directory.path}/app_log.txt');
    final stamp = DateTime.now().toIso8601String().substring(11, 23);
    var mode = FileMode.append;
    if (await file.exists() && await file.length() > 256 * 1024) mode = FileMode.write;
    await file.writeAsString('$stamp  $message\n', mode: mode, flush: true);
  } catch (_) {}
}
