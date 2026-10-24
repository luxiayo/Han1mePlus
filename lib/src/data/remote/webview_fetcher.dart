import 'dart:async';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'han1me_api.dart';

class WebviewFetchResponse {
  const WebviewFetchResponse({required this.status, required this.url, required this.body});

  final int status;
  final String url;
  final String body;
}

/// 无头 webview fetch 通道：站点 Cloudflare 收紧后会按 TLS 指纹挑战原生
/// dio 请求（cf_clearance 绑定浏览器指纹，原生携带也 403）。HTML/表单类
/// 请求在原生被挑战时改走无头 webview 的同源 fetch——浏览器指纹 + 浏览器
/// cookie，CF 放行。请求串行执行，避免并发触发限流。
class WebviewFetcher {
  WebviewFetcher(this._loadEnvironment);

  final Future<WebViewEnvironment?> Function() _loadEnvironment;
  Future<HeadlessInAppWebView>? _starting;
  Future<void> _queue = Future.value();
  String? _currentOrigin;
  Completer<void>? _navCompleter;

  static const _fetchFunctionBody = r"""
var out = {status: -1, url: '', body: ''};
try {
  var res = await fetch(url, {credentials: 'include', redirect: 'follow', referrer: referer === '' ? undefined : referer});
  out.status = res.status;
  out.url = res.url;
  out.body = await res.text();
} catch (e) {
  out.body = 'FETCH_ERROR: ' + e;
}
return JSON.stringify(out);
""";

  static const _postFunctionBody = r"""
var out = {status: -1, body: ''};
try {
  var form = new URLSearchParams();
  for (var key in data) form.append(key, data[key]);
  var res = await fetch(url, {
    method: 'POST',
    credentials: 'include',
    redirect: 'follow',
    referrer: referer === '' ? undefined : referer,
    headers: {'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8', 'X-CSRF-TOKEN': token},
    body: form.toString(),
  });
  out.status = res.status;
  out.body = await res.text();
} catch (e) {
  out.body = 'FETCH_ERROR: ' + e;
}
return JSON.stringify(out);
""";

  /// GET：返回最终状态码/最终 URL/响应体文本（fetch 自动跟随重定向）。
  Future<WebviewFetchResponse> fetch(String url, {String? referer}) {
    final task = _queue.then((_) => _fetchOne(url, referer));
    _queue = task.then((_) {}, onError: (_) {});
    return task;
  }

  /// POST：表单编码 + CSRF 头，经由同一无头 webview（浏览器 cookie）。
  Future<WebviewFetchResponse> post(String url, {required Map<String, String> data, String? token, String? referer}) {
    final task = _queue.then((_) => _postOne(url, data, token, referer));
    _queue = task.then((_) {}, onError: (_) {});
    return task;
  }

  Future<Map?> _call(String functionBody, Map<String, Object?> args) async {
    final controller = (await _ensure()).webViewController!;
    final result = await controller
        .callAsyncJavaScript(functionBody: functionBody, arguments: args)
        .timeout(const Duration(seconds: 60));
    final value = result?.value;
    if (value == null) return null;
    final decoded = jsonDecode('$value');
    return decoded is Map ? decoded : null;
  }

  Future<WebviewFetchResponse> _fetchOne(String url, String? referer) async {
    await _navigateToOriginOf(url);
    final decoded = await _call(_fetchFunctionBody, {'url': url, 'referer': referer ?? ''});
    if (decoded == null) throw StateError('webview fetch returned no payload');
    final status = decoded['status'] is int ? decoded['status'] as int : int.tryParse('${decoded['status']}') ?? -1;
    final body = '${decoded['body'] ?? ''}';
    // status=-1 是 JS fetch 自身抛错（如 CORS/网络），把真实原因抛给上层展示。
    if (status == -1) throw StateError(body);
    return WebviewFetchResponse(status: status, url: '${decoded['url'] ?? ''}', body: body);
  }

  Future<WebviewFetchResponse> _postOne(String url, Map<String, String> data, String? token, String? referer) async {
    await _navigateToOriginOf(url);
    final decoded = await _call(_postFunctionBody, {'url': url, 'data': data, 'token': token ?? '', 'referer': referer ?? ''});
    if (decoded == null) throw StateError('webview post returned no payload');
    final status = int.tryParse('${decoded['status']}') ?? -1;
    final body = '${decoded['body'] ?? ''}';
    if (status == -1) throw StateError(body);
    return WebviewFetchResponse(status: status, url: '', body: body);
  }

  /// fetch 必须与当前页面同源：无头 webview 停在 about:blank 时发起的
  /// 站点请求是跨域的，会被 CORS 拦截。导航到目标源后再 fetch。
  Future<void> _navigateToOriginOf(String url) async {
    final uri = Uri.parse(url);
    final origin = '${uri.scheme}://${uri.authority}/';
    if (_currentOrigin == origin) return;
    final controller = (await _ensure()).webViewController!;
    final completer = Completer<void>();
    _navCompleter = completer;
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(origin)));
    await completer.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    // 给站点的自动跳转/挑战留一点时间
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _currentOrigin = origin;
  }

  Future<HeadlessInAppWebView> _ensure() {
    _starting ??= _start();
    return _starting!;
  }

  Future<HeadlessInAppWebView> _start() async {
    final environment = await _loadEnvironment();
    final headless = HeadlessInAppWebView(
      webViewEnvironment: environment,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        userAgent: Han1meApi.userAgent,
      ),
      onLoadStop: (controller, url) {
        final completer = _navCompleter;
        if (completer != null && !completer.isCompleted) completer.complete();
      },
    );
    await headless.run();
    return headless;
  }
}
