import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../utils/aes_crypto.dart';
import '../utils/form_builder.dart';
import '../utils/html_parser.dart';

/// 认证结果
class LoginResult {
  const LoginResult({
    required this.success,
    required this.message,
    this.raw,
  });

  final bool success;
  final String message;
  final Map<String, dynamic>? raw;
}

/// 在线状态
enum OnlineStatus { online, offline, unknown }

/// GiWiFi gportal 认证客户端（零第三方依赖，dart:io HttpClient）。
///
/// 流程：
/// 1. 以指定 UA 请求登录页（服务器据此渲染 device_type 等隐藏字段）
/// 2. 组装表单 -> AES-128-CBC + ZeroPadding（密钥硬编码于 aes.js）
/// 3. POST /gportal/Web/loginAction
class AuthService {
  AuthService({
    this.baseUrl = 'http://100.100.9.2',
    this.timeout = const Duration(seconds: 10),
  });

  final String baseUrl;
  final Duration timeout;

  static const String kLoginPath = '/gportal/web/login';
  static const String kLoginActionPath = '/gportal/Web/loginAction';

  Map<String, String> _pageHeaders(String userAgent) => <String, String>{
        'User-Agent': userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      };

  /// 拉取登录页 HTML（连接失败时带通用 wlan 参数重试一次）。
  Future<String> fetchLoginPage(String userAgent) async {
    var uri = Uri.parse('$baseUrl$kLoginPath');
    try {
      return await _getText(uri, userAgent);
    } on SocketException {
      uri = Uri.parse(
          '$baseUrl$kLoginPath?wlanuserip=10.0.0.1&wlanacname=GiWiFi');
      return await _getText(uri, userAgent);
    }
  }

  Future<LoginResult> login({
    required String username,
    required String password,
    required String userAgent,
    String accountType = '2',
  }) async {
    final html = await fetchLoginPage(userAgent);

    if (!_hasPasswordInput(html)) {
      if (_hasLogoutHint(html)) {
        return const LoginResult(
          success: false,
          message: '当前设备已在线，无需重复认证',
        );
      }
      return const LoginResult(
        success: false,
        message: '响应不是登录页（可能已在线，或未连接校园网）',
      );
    }

    final hidden = parseHiddenInputs(html);
    final iv = hidden['iv'] ?? '';
    final sign = hidden['sign'] ?? '';
    if (iv.isEmpty) {
      return const LoginResult(
        success: false,
        message: '登录页缺少 iv 参数，门户页面结构可能已变化',
      );
    }
    if (sign.isEmpty) {
      return const LoginResult(
        success: false,
        message: '登录页缺少 sign 参数，门户页面结构可能已变化',
      );
    }

    final fields = <String, String>{
      'sign': sign,
      'sta_vlan': hidden['sta_vlan'] ?? '',
      'sta_port': hidden['sta_port'] ?? '',
      'sta_ip': hidden['sta_ip'] ?? '',
      'nas_ip': hidden['nas_ip'] ?? '',
      'nas_name': hidden['nas_name'] ?? '',
      'last_url': hidden['last_url'] ?? '',
      'request_ip': hidden['request_ip'] ?? '',
      'device_mode': hidden['device_mode'] ?? '',
      'device_type': hidden['device_type'] ?? '1',
      'device_os_type': hidden['device_os_type'] ?? '3',
      'is_mobile': hidden['is_mobile'] ?? '0',
      'iv': iv,
      'login_type': hidden['login_type'] ?? '1',
      'account_type': accountType,
      'user_account': username,
      'user_password': password,
    };

    final formStr = buildFormString(fields);
    final data = aesCbcZeroPadEncrypt(formStr, kGiWifiAesKey, iv);

    final body =
        await _postForm('$baseUrl$kLoginActionPath', userAgent, data, iv);

    Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      final preview = body.length > 120 ? body.substring(0, 120) : body;
      return LoginResult(
        success: false,
        message: '服务器响应解析失败：$preview',
      );
    }

    final status = json['status'];
    final info = json['info']?.toString() ?? '未知响应';
    if (status == 1) {
      return LoginResult(success: true, message: '认证成功：$info', raw: json);
    }
    if (status == 0) {
      final data = json['data'];
      if (data is Map && data['resultCode'] == '40') {
        return LoginResult(
          success: false,
          message: '已登录或需跳转：${data['resultData'] ?? ''}',
          raw: json,
        );
      }
      return LoginResult(success: false, message: '认证失败：$info', raw: json);
    }
    return LoginResult(success: false, message: '未知响应：$json', raw: json);
  }

  Future<OnlineStatus> checkOnline(String userAgent) async {
    try {
      final html = await fetchLoginPage(userAgent);
      if (_hasPasswordInput(html)) return OnlineStatus.offline;
      if (_hasLogoutHint(html)) return OnlineStatus.online;
      return OnlineStatus.unknown;
    } catch (_) {
      return OnlineStatus.unknown;
    }
  }

  Future<String> _getText(Uri uri, String userAgent) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri).timeout(timeout);
      req.headers.set(HttpHeaders.userAgentHeader, userAgent);
      req.headers
          .set(HttpHeaders.acceptHeader, _pageHeaders(userAgent)['Accept']!);
      final resp = await req.close().timeout(timeout);
      final bytes = await resp
          .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
      if (resp.statusCode >= 400) {
        throw HttpException('HTTP ${resp.statusCode}');
      }
      return utf8.decode(bytes);
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _postForm(
    String url,
    String userAgent,
    String data,
    String iv,
  ) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse(url)).timeout(timeout);
      req.headers.set(HttpHeaders.userAgentHeader, userAgent);
      req.headers.set('X-Requested-With', 'XMLHttpRequest');
      req.headers.set(
        HttpHeaders.acceptHeader,
        'application/json, text/javascript, */*; q=0.01',
      );
      req.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      req.write(
        'data=${Uri.encodeComponent(data)}&iv=${Uri.encodeComponent(iv)}',
      );
      final resp = await req.close().timeout(timeout);
      return await utf8.decodeStream(resp);
    } finally {
      client.close(force: true);
    }
  }

  bool _hasPasswordInput(String html) => RegExp(
        r'type\s*=\s*["\x27]?password',
        caseSensitive: false,
      ).hasMatch(html);

  bool _hasLogoutHint(String html) =>
      html.contains('注销') || html.contains('logout') || html.contains('下线');
}
