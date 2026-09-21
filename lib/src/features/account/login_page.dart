import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
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
  var _saving = false;
  Object? _error;

  Future<void> _saveCookies() async {
    if (_saving || !mounted) return;
    setState(() => _saving = true);
    try {
      final settings = await ref.read(settingsProvider.future);
      final cookie = await ref.read(han1meHttpClientProvider).webViewCookies(settings.resolvedBaseUrl);
      if (cookie.isEmpty) {
        if (mounted) setState(() => _saving = false);
        return;
      }
      await ref.read(accountProvider.notifier).saveCookie(cookie);
      if (!mounted) return;
      // 录入 cookie 后先探测一次：原生请求被 Cloudflare 拦截（webview 里没拿到 cf_clearance）
      // 时直接带去验证页，而不是回到内容页后才报 403。
      try {
        await ref.read(han1meRepositoryProvider).home(settings.resolvedBaseUrl);
      } on CloudflareChallengeException {
        if (!mounted) return;
        await context.push<bool>('/cloudflare', extra: settings.resolvedBaseUrl);
      } on DioException catch (error) {
        if (error.response?.statusCode == 403 && mounted) {
          await context.push<bool>('/cloudflare', extra: settings.resolvedBaseUrl);
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = ref.watch(settingsProvider).valueOrNull?.resolvedBaseUrl ?? 'https://hanime1.com';
    final loginUrl = Uri.parse('$baseUrl/login');
    final webViewEnvironment = ref.watch(webViewEnvironmentProvider).valueOrNull;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.login)),
      floatingActionButton: FloatingActionButton(
        tooltip: AppLocalizations.of(context)!.manualCookieLogin,
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
              await ref.read(han1meHttpClientProvider).clearWebViewCookies();
              if (!mounted) return;
              await controller.loadUrl(urlRequest: URLRequest(url: WebUri(loginUrl.toString())));
            },
            onLoadStop: (_, url) {
              if (url != null && url.host == loginUrl.host && url.path != loginUrl.path) _saveCookies();
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
