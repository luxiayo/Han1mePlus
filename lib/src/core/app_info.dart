import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// pubspec version 的 Dart 侧镜像：Windows 的 Runner.rc 无版本资源，
/// PackageInfo.version 会返回空串（关于页/更新检查随之失效）。
const appFallbackVersion = '1.2.0';

final packageInfoProvider = FutureProvider<PackageInfo>((ref) async {
  final info = await PackageInfo.fromPlatform();
  if (info.version.isNotEmpty) return info;
  return PackageInfo(appName: 'Han1me+', packageName: 'com.liar.han1meplus', version: appFallbackVersion, buildNumber: '0');
});
