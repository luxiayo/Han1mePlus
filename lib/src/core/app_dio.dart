import 'package:dio/dio.dart';

/// 所有临时 Dio 实例统一从这里创建。receive/send 超时按"连续无进展"计而非总时长，
/// 因此不会中断大文件传输，只兜底服务端无响应的挂起。
Dio createDio({
  Duration connectTimeout = const Duration(seconds: 15),
  Duration receiveTimeout = const Duration(seconds: 60),
}) =>
    Dio(BaseOptions(
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: const Duration(seconds: 30),
    ));
