import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../../core/platform_paths.dart';

class JsonStore {
  // 静态序号兜底：同一实例同一微秒内的两次并发写也不会得到相同临时文件名。
  static var _writeSequence = 0;

  Future<Map<String, dynamic>> read(String fileName) async {
    try {
      final file = await _file(fileName);
      if (!await file.exists()) return {};
      final value = jsonDecode(await file.readAsString());
      return value is Map<String, dynamic> ? value : {};
    } catch (error) {
      // 损坏时回退空数据避免崩溃，但保留痕迹便于排查。
      debugPrint('Failed to read $fileName: $error');
      return {};
    }
  }

  Future<void> write(String fileName, Map<String, dynamic> value) async {
    final file = await _file(fileName);
    // 先写临时文件再改名：崩溃/断电不会留下半截 JSON。临时文件名带唯一后缀——
    // 并发写同一文件时会共用 tmp 路径，先完成者把文件 rename 走，后者 ENOENT。
    final unique = '${DateTime.now().microsecondsSinceEpoch}.${_writeSequence++}#${identityHashCode(this)}';
    final temporary = File('${file.path}.$unique.tmp');
    try {
      await temporary.writeAsString(jsonEncode(value), flush: true);
      await temporary.rename(file.path);
    } catch (_) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<File> _file(String fileName) async {
    final directory = await appStorageDirectory();
    return File(path.join(directory.path, fileName));
  }
}
