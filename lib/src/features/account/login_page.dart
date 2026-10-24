import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/app_log.dart';
import '../../core/site_hosts.dart';
import '../../data/han1me_repository.dart';
import '../../data/remote/han1me_api.dart';
import '../../data/remote/webview_environment.dart';
import '../settings/settings_controller.dart';
import 'account_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  static const _pollInterval = Duration(milliseconds: 700);
  static const _captureCooldown = Duration(seconds: 2);

  // 页面里出现用户入口且指向 /user/，说明登录态已建立（上游 v1.2.0 同款标记）。
  static const _loginMarkerScript = r"""
(function () {
  var trigger = document.querySelector('#user-modal-trigger');
  if (trigger) {
    if (/\/user\/\d+/.test(trigger.getAttribute('href') || '')) return true;
    if (trigger.querySelector('a[href*="/user/"]')) return true;
  }
  return document.querySelector('.profile-sub-stats-id') !== null;
})()
""";

  InAppWebViewController? _controller;
  Timer? _timer;
  DateTime? _lastAttempt;
  var _saving = false;
  var _lastLoggedIn = false;
  Object? _error;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _capture({bool manual = false}) async {
    if (_saving || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _saving = true;
      if (manual) _error = null;
    });
    var popped = false;
    unawaited(appLog('capture begin (manual=$manual)'));
    try {
      final settings = await ref.read(settingsProvider.future);
      final current = await _controller?.getUrl();
      if (!mounted) return;
      unawaited(appLog('capture webview url: $current'));
      // 跨站点收集 cookie：当前页 + 站点系所有域合并，避免会话写在他域。
      final cookie = await ref.read(han1meHttpClientProvider).webViewCookiesFor(_candidates(current, settings.resolvedBaseUrl));
      if (!mounted) return;
      unawaited(appLog('capture cookies ${cookie.length} chars, clearance=${cookie.contains('cf_clearance')}'));
      // 只有 cf_clearance 不算登录成功。
      if (_withoutClearance(cookie).isEmpty) {
        unawaited(appLog('capture aborted: session cookies empty'));
        if (manual) setState(() => _error = l10n.failed);
        return;
      }
      // 资料由 webview 同源 fetch 提供：cf_clearance 绑定浏览器 TLS 指纹，
      // 原生资料请求会被 Cloudflare 挑战（日志实测每次 403），故零原生请求。
      final profile = _controller == null ? null : await _captureProfile(_controller!);
      unawaited(appLog('capture profile id=${profile?['id']}, csrf=${(profile?['csrf'] ?? '').isNotEmpty}, name=${profile?['name'] != null}'));
      await ref.read(accountProvider.notifier).saveCookie(cookie, userId: profile?['id'], profile: profile);
      if (!mounted) return;
      unawaited(appLog('capture cookie saved (webview-only flow) → pop'));
      if (!mounted) return;
      _timer?.cancel();
      _timer = null;
      if (_pop()) {
        unawaited(appLog('capture done → pop login page'));
        popped = true;
        return;
      }
      _startPolling();
      unawaited(appLog('capture done → pop failed, restart polling'));
    } catch (error) {
      unawaited(appLog('capture failed: $error'));
      if (mounted && manual) setState(() => _error = error);
    } finally {
      if (mounted && !popped) setState(() => _saving = false);
    }
  }

  bool _pop() {
    try {
      context.pop();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) {
      if (mounted && !_saving) unawaited(_poll());
    });
  }

  Future<void> _poll() async {
    final last = _lastAttempt;
    if (last != null && DateTime.now().difference(last) < _captureCooldown) return;
    final controller = _controller;
    if (controller == null || !mounted) return;
    final loggedIn = await _loggedIn(controller);
    if (!mounted) return;
    if (loggedIn != _lastLoggedIn) unawaited(appLog('poll marker loggedIn=$loggedIn'));
    _lastLoggedIn = loggedIn;
    // 自动捕获必须匹配到登录标记：仅"离开 /login"会在匿名首页/CF 拦截页上
    // 误存仅含 cookie 的账号（账号页 @null 的根因）。
    if (!loggedIn) return;
    if (!mounted) return;
    _lastAttempt = DateTime.now();
    await _capture();
  }

  // 用户 id 与资料由登录 webview 同源抓取：cf_clearance 绑定浏览器 TLS
  // 指纹，原生请求携带也会被 Cloudflare 挑战（站点已收紧），故登录链路
  // 不发任何原生请求。callAsyncJavaScript 会等待 Promise 完成。
  static const _profileFunctionBody = r"""
var out = {id: null, csrf: null, name: null, email: null, avatar: null};
try {
  var trigger = document.querySelector('#user-modal-trigger');
  var id = null;
  if (trigger) {
    var direct = /\/user\/(\d+)/.exec(trigger.getAttribute('href') || '');
    if (!direct) {
      var inner = trigger.querySelector('a[href*="/user/"]');
      direct = inner ? /\/user\/(\d+)/.exec(inner.getAttribute('href') || '') : null;
    }
    if (direct) id = direct[1];
  }
  if (!id) {
    var stats = document.querySelector('.profile-sub-stats-id');
    var numeric = stats ? /\d+/.exec(stats.textContent || stats.innerText || '') : null;
    if (numeric) id = numeric[0];
  }
  out.id = id;
  if (id) {
    var res = await fetch('/user/' + id + '/edit', {credentials: 'same-origin'});
    var doc = new DOMParser().parseFromString(await res.text(), 'text/html');
    var meta = doc.querySelector('meta[name="csrf-token"]');
    var token = doc.querySelector('input[name="_token"]');
    out.csrf = (meta && meta.content) || (token && token.value) || null;
    var nameInput = doc.querySelector('input[name="name"]');
    out.name = nameInput ? nameInput.value : null;
    var emailInput = doc.querySelector('input[name="email"]');
    out.email = emailInput ? emailInput.value : null;
    var avatar = doc.querySelector('img#playlist-avatar, #user-modal-dp-wrapper img, .profile-avatar-wrapper img');
    out.avatar = avatar ? avatar.getAttribute('src') : null;
  }
  if (!out.csrf) {
    var meta = document.querySelector('meta[name="csrf-token"]');
    var token = document.querySelector('input[name="_token"]');
    out.csrf = (meta && meta.content) || (token && token.value) || null;
  }
} catch (e) {}
return JSON.stringify(out);
""";

  Future<Map<String, String?>?> _captureProfile(InAppWebViewController controller) async {
    try {
      final result = await controller.callAsyncJavaScript(functionBody: _profileFunctionBody);
      final value = result?.value;
      if (value == null) return null;
      final decoded = jsonDecode('$value');
      if (decoded is! Map) return null;
      return decoded.map((key, value) => MapEntry('$key', value?.toString()));
    } catch (error) {
      unawaited(appLog('profile capture failed: $error'));
      return null;
    }
  }

  Future<bool> _loggedIn(InAppWebViewController controller) async {
    try {
      final result = await controller.evaluateJavascript(source: _loginMarkerScript);
      return result == true || result == 'true';
    } catch (_) {
      return false;
    }
  }

  Iterable<String> _candidates(Uri? current, String baseUrl) {
    final urls = <String>{};
    if (current != null && current.host.isNotEmpty) urls.add('${current.scheme}://${current.authority}/');
    final base = Uri.tryParse(baseUrl);
    if (base != null && base.host.isNotEmpty) urls.add('${base.scheme}://${base.authority}/');
    for (final host in hanimeSiteHosts) {
      urls.add('https://$host/');
    }
    return urls;
  }

  String _withoutClearance(String cookies) => cookies.split(';').where((cookie) => cookie.trim().toLowerCase().split('=').first != 'cf_clearance').join(';').trim();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final baseUrl = ref.watch(settingsProvider).valueOrNull?.resolvedBaseUrl ?? 'https://hanime1.com';
    final webViewEnvironment = ref.watch(webViewEnvironmentProvider).valueOrNull;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(l10n.login),
        actions: [
          TextButton(
            onPressed: () => unawaited(_capture(manual: true)),
            child: Text(l10n.finishLogin),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.manualCookieLogin,
        onPressed: () => context.push('/login/cookies'),
        child: const Icon(Icons.cookie_outlined),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          InAppWebView(
            webViewEnvironment: webViewEnvironment,
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              thirdPartyCookiesEnabled: true,
              userAgent: Han1meApi.userAgent,
            ),
            onWebViewCreated: (controller) async {
              _controller = controller;
              await ref.read(han1meHttpClientProvider).clearWebViewCookies();
              if (!mounted) return;
              await controller.loadUrl(urlRequest: URLRequest(url: WebUri('$baseUrl/login')));
              if (!mounted) return;
              _startPolling();
            },
          ),
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: MaterialBanner(
                content: Text('$_error'),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _error = null),
                    child: Text(AppLocalizations.of(context)!.close),
                  ),
                ],
              ),
            ),
          if (_saving) const Align(alignment: Alignment.topCenter, child: LinearProgressIndicator()),
        ],
      ),
    );
  }
}
