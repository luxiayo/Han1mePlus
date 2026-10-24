import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';

import '../../data/han1me_repository.dart';
import '../../core/app_log.dart';
import '../../core/site_hosts.dart';
import '../../data/remote/han1me_api.dart';
import '../../data/remote/webview_environment.dart';
import '../account/account_controller.dart';
import 'settings_controller.dart';

class CloudflarePage extends ConsumerStatefulWidget {
  const CloudflarePage({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  ConsumerState<CloudflarePage> createState() => _CloudflarePageState();
}

class _CloudflarePageState extends ConsumerState<CloudflarePage> {
  Timer? _verificationTimer;
  String? _initialClearance;
  String? _lastLoggedClearance;
  String? _error;
  Set<String> get _pollUrls => {
        if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) widget.initialUrl!,
        for (final host in hanimeSiteHosts) 'https://$host/',
      };
  var _saving = false;

  Future<void> _completeVerification(String requestUrl) async {
    if (_saving) return;
    _saving = true;
    unawaited(appLog('cf poll begin (urls=${_pollUrls.length})'));
    try {
      // 站点 301 迁移（hanime1.com → hanime1.me）后，cf_clearance 签发在
      // 跳转目标域；只读 initialUrl 域的 cookie 永远看不到新验证，导致
      // 验证完成也不弹回。跨站点系域名合并收集（与登录页 _candidates 同款）。
      final cookies = await ref.read(han1meHttpClientProvider).webViewCookiesFor(_pollUrls);
      final clearance = _clearanceCookie(cookies);
      if (clearance != _lastLoggedClearance) {
        unawaited(appLog('cf poll clearance=${clearance == null ? "none" : "present (${clearance.length} chars)"}'));
        _lastLoggedClearance = clearance;
      }
      if (clearance == null || clearance == _initialClearance || !mounted) return;
      unawaited(appLog('cf clearance changed → save & pop'));
      await ref.read(accountProvider.notifier).saveCloudflareCookie(cookies);
      if (!mounted) return;
      _verificationTimer?.cancel();
      unawaited(appLog('cf verification done → pop'));
      Navigator.pop(context, true);
    } catch (error) {
      unawaited(appLog('cf poll error: $error'));
      if (mounted) setState(() => _error = '$error');
    } finally {
      _saving = false;
    }
  }

  void _startVerification(String requestUrl) {
    if (_verificationTimer != null) return;
    _verificationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_saving) _completeVerification(requestUrl);
    });
  }

  String? _clearanceCookie(String cookies) {
    for (final cookie in cookies.split(';')) {
      if (cookie.trim().toLowerCase().startsWith('cf_clearance=')) return cookie.trim();
    }
    return null;
  }

  @override
  void dispose() {
    _verificationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = ref.watch(settingsProvider).valueOrNull?.resolvedBaseUrl ?? 'https://hanime1.com';
    final initialUrl = widget.initialUrl ?? baseUrl;
    final webViewEnvironment = ref.watch(webViewEnvironmentProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.cloudflareVerification)),
      body: Stack(children: [
        InAppWebView(
          webViewEnvironment: webViewEnvironment,
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            thirdPartyCookiesEnabled: true,
            userAgent: Han1meApi.userAgent,
          ),
          onWebViewCreated: (controller) async {
            unawaited(appLog('cf page open: $initialUrl'));
            _initialClearance = _clearanceCookie(await ref.read(han1meHttpClientProvider).webViewCookiesFor({
              if (initialUrl.isNotEmpty) initialUrl,
              for (final host in hanimeSiteHosts) 'https://$host/',
            }));
            final url = WebUri(initialUrl);
            await controller.loadUrl(urlRequest: URLRequest(url: url));
            unawaited(appLog('cf initial clearance=${_initialClearance == null ? "none" : "present"}'));
            _startVerification(initialUrl);
          },
        ),
        if (_error != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: MaterialBanner(
              content: Text(_error!),
              actions: [TextButton(onPressed: () => setState(() => _error = null), child: Text(AppLocalizations.of(context)!.close))],
            ),
          ),
      ]),
    );
  }
}
