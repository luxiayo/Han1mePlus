import 'dart:async';
import 'dart:convert';
import 'dart:io';

class WindowsConnectionFactory {

  static const hanimeHosts = {'hanime1.me', 'hanime1.com', 'hanimeone.me', 'javchu.com'};

  static const builtInAddresses = [
    '172.64.229.154',
    '162.159.0.1',
    '108.162.192.1',
    '172.64.33.1',
    '104.19.0.1',
    '2606:4700:3035::ac43:bb8d',
    '2606:4700:3030::6815:746',
    '2606:4700:3030::6815:714',
  ];

  WindowsConnectionFactory({
    required this.useBuiltInHosts,
    required this.useDoh,
    required this.dohPreset,
    required this.dohCustomUrl,
    required this.dohBootstrapIps,
    required this.dohTimeoutSeconds,
  });

  final bool useBuiltInHosts;
  final bool useDoh;
  final String dohPreset;
  final String dohCustomUrl;
  final String dohBootstrapIps;
  final int dohTimeoutSeconds;

  Duration get _timeout => Duration(seconds: dohTimeoutSeconds);

  late final _doh = _DohResolver(
    preset: dohPreset,
    customUrl: dohCustomUrl,
    bootstrapIps: dohBootstrapIps,
    timeout: _timeout,
  );

  Future<ConnectionTask<Socket>> call(Uri uri, String? proxyHost, int? proxyPort) async {
    if (proxyHost != null) return Socket.startConnect(proxyHost, proxyPort ?? uri.port);
    final port = uri.hasPort ? uri.port : (uri.isScheme('https') ? 443 : 80);
    if (useBuiltInHosts && hanimeHosts.contains(uri.host)) {
      return _connect(uri, [...builtInAddresses, uri.host], port);
    }
    if (!useDoh) return await _startConnect(uri.host, port);
    try {
      final addresses = await _doh.resolve(uri.host);
      if (addresses.isNotEmpty) return await _connect(uri, [...addresses, uri.host], port);
    } catch (_) {}
    return _connect(uri, [uri.host], port);
  }

  Future<ConnectionTask<Socket>> _connect(Uri uri, List<String> addresses, int port) async {
    final allowBadCertificate = useBuiltInHosts && hanimeHosts.contains(uri.host);
    // 并行竞速所有候选地址，最先完成 TLS 的胜出、其余销毁：
    // 串行逐个等待会让每个不可达 IP 各吃满连接超时（默认 10s），
    // 启动期首个请求可拖 20 秒以上（白屏元凶）。
    final winner = Completer<SecureSocket>();
    var failures = 0;
    Object? lastError;
    StackTrace? lastStackTrace;

    Future<void> attempt(String address) async {
      Socket? plain;
      SecureSocket? secure;
      try {
        if (address == uri.host) {
          // 系统 DNS 路径：直接 TLS 连接（证书严格校验）。
          final task = await SecureSocket.startConnect(uri.host, port);
          secure = await task.socket.timeout(_timeout);
        } else {
          // 钉死 IP 路径：裸连 IP + 以目标域名为 SNI 完成 TLS，
          // 站内域允许坏证书（优选 IP 的证书可能不匹配）。
          plain = await Socket.connect(address, port, timeout: _timeout);
          if (winner.isCompleted) {
            plain.destroy();
            return;
          }
          secure = await SecureSocket.secure(plain, host: uri.host, onBadCertificate: allowBadCertificate ? (_) => true : null);
          plain = null;
        }
        if (winner.isCompleted) {
          secure.destroy();
          return;
        }
        winner.complete(secure);
      } catch (error, stackTrace) {
        plain?.destroy();
        secure?.destroy();
        failures++;
        lastError = error;
        lastStackTrace = stackTrace;
        if (failures == addresses.length && !winner.isCompleted) {
          winner.completeError(lastError!, lastStackTrace!);
        }
      }
    }

    for (final address in addresses) {
      unawaited(attempt(address));
    }
    final socket = await winner.future;
    return ConnectionTask.fromSocket(Future.value(socket), socket.destroy);
  }

  Future<ConnectionTask<Socket>> _startConnect(String host, int port) => SecureSocket.startConnect(host, port);
}

class _DohResolver {
  static final _cache = <String, _CachedAddresses>{};

  _DohResolver({
    required this.preset,
    required this.customUrl,
    required this.bootstrapIps,
    required this.timeout,
  });

  final String preset;
  final String customUrl;
  final String bootstrapIps;
  final Duration timeout;

  Future<List<String>> resolve(String host) async {
    final endpoint = _endpoint;
    if (endpoint == null) return const [];
    final key = '$endpoint:$host';
    final cached = _cache[key];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) return cached.addresses;
    final answers = await Future.wait([_query(endpoint, host, 'A'), _query(endpoint, host, 'AAAA')]);
    final addresses = answers.expand((answer) => answer).toSet().toList(growable: false);
    if (addresses.isNotEmpty) _cache[key] = _CachedAddresses(addresses, DateTime.now().add(const Duration(minutes: 5)));
    return addresses;
  }

  Uri? get _endpoint => switch (preset) {
        'alidns' => Uri.parse('https://dns.alidns.com/dns-query'),
        'dnspod' => Uri.parse('https://doh.pub/dns-query'),
        'cloudflare' => Uri.parse('https://cloudflare-dns.com/dns-query'),
        'custom' => Uri.tryParse(customUrl.trim()),
        _ => null,
      };

  HttpClient? _queryClient;

  HttpClient get _client => _queryClient ??= (HttpClient()..connectionTimeout = timeout);

  Future<List<String>> _query(Uri endpoint, String host, String type) async {
    final client = _client;
    final bootstrap = _bootstrapIps;
    if (bootstrap.isNotEmpty) {
      client.connectionFactory = (uri, proxyHost, proxyPort) async {
        if (proxyHost != null) return Socket.startConnect(proxyHost, proxyPort ?? uri.port);
        if (uri.host != endpoint.host) return SecureSocket.startConnect(uri.host, uri.port);
        // 逐个尝试 bootstrap IP，避免单个 IP 失效导致 DoH 整体不可用。
        for (final ip in bootstrap) {
          Socket? plain;
          try {
            plain = await Socket.connect(ip, uri.port, timeout: timeout);
            final secure = await SecureSocket.secure(plain, host: uri.host);
            return ConnectionTask.fromSocket(Future.value(secure), secure.destroy);
          } catch (_) {
            plain?.destroy();
          }
        }
        throw const SocketException('Failed to connect to any DoH bootstrap IP');
      };
    }
    final request = await client.getUrl(endpoint.replace(queryParameters: {'name': host, 'type': type}));
    request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) return const [];
    final json = jsonDecode(await utf8.decoder.bind(response).join());
    if (json is! Map) return const [];
    return (json['Answer'] as List? ?? const [])
        .whereType<Map>()
        .map((answer) => answer['data'])
        .whereType<String>()
        .where((address) => InternetAddress.tryParse(address) != null)
        .toList(growable: false);
  }

  List<String> get _bootstrapIps {
    final values = bootstrapIps.split(RegExp(r'[,;\s]+')).where((value) => InternetAddress.tryParse(value) != null).toList();
    if (values.isNotEmpty) return values;
    return switch (preset) {
      'alidns' => const ['223.5.5.5', '223.6.6.6'],
      'dnspod' => const ['1.12.12.12', '120.53.53.53'],
      'cloudflare' => const ['1.1.1.1', '1.0.0.1'],
      _ => const [],
    };
  }
}

class _CachedAddresses {
  const _CachedAddresses(this.addresses, this.expiresAt);

  final List<String> addresses;
  final DateTime expiresAt;
}
