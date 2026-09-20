import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../../core/platform_paths.dart';

class JsonStore {
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
    // 先写临时文件再改名：崩溃/断电不会留下半截 JSON 毁掉全部本地数据。
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(file.path);
  }

  Future<File> _file(String fileName) async {
    final directory = await appStorageDirectory();
    return File(path.join(directory.path, fileName));
  }
}
