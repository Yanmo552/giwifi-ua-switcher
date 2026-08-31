import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:giwifi_ua_switcher/services/auth_service.dart';

String _formPage() => '''
<html><body>
<form id="loginForm">
<input type="hidden" name="sign" value="sig123">
<input type="hidden" name="sta_ip" value="10.0.0.1">
<input type="hidden" name="iv" value="0123456789abcdef">
<input type="hidden" name="login_type" value="1">
<input type="password" name="user_password">
</form>
</body></html>
''';

void main() {
  test('移动端 UA：首页无表单时自动降级到 pagetype=login 再认证', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${server.port}';
    var sawMobileForm = false;
    var loginPosts = 0;

    server.listen((req) async {
      final path = req.uri.path;
      final query = req.uri.query;
      try {
        if (path == '/gportal/web/login') {
          if (query.contains('pagetype=login')) {
            sawMobileForm = true;
            req.response.headers.contentType = ContentType.html;
            req.response.write(_formPage());
          } else {
            req.response.headers.contentType = ContentType.html;
            req.response.write(
              '<html><head><title>欢迎使用GiWiFi</title></head>'
              '<body><script>function reloadMobile(){}</script>'
              '<div class="web-login">网页登录</div></body></html>',
            );
          }
        } else if (path == '/gportal/Web/loginAction') {
          loginPosts++;
          req.response.write(jsonEncode(<String, dynamic>{
            'status': 1,
            'info': '认证成功',
            'data': <String, dynamic>{},
          }));
        } else if (path == '/gportal/web/logout') {
          final start = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          req.response.write('<html>var start = "$start"; online_duration</html>');
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      } catch (_) {
        await req.response.close();
      }
    });

    final auth = AuthService(baseUrl: base);
    final result = await auth.login(
      username: 'test2024',
      password: 'TestPass123@',
      userAgent:
          'Mozilla/5.0 (Linux; Android 14; 24031PN0DC) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
    );
    await server.close(force: true);

    expect(result.success, isTrue);
    expect(result.message, contains('认证成功'));
    expect(sawMobileForm, isTrue);
    expect(loginPosts, 1);
  });

  test('已在线时自动注销再切换设备认证', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${server.port}';
    var logoutPosts = 0;
    var loginGets = 0;

    server.listen((req) async {
      final path = req.uri.path;
      final query = req.uri.query;
      try {
        if (path == '/gportal/web/login' && query.isEmpty) {
          loginGets++;
          req.response.headers.contentType = ContentType.html;
          if (loginGets == 1) {
            // 第一次：已在线页面（无登录表单，含“注销”）
            req.response.write(
              '<html><body><a href="/gportal/web/logout">注销</a></body></html>',
            );
          } else {
            req.response.write(_formPage());
          }
        } else if (path == '/gportal/web/login') {
          req.response.headers.contentType = ContentType.html;
          req.response.write(_formPage());
        } else if (path == '/gportal/web/logout') {
          final start = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          req.response.write(
            '<html><input type="hidden" name="si" value="abc123">'
            'var start = "$start"; online_duration</html>',
          );
        } else if (path == '/gportal/Web/logoutAction') {
          logoutPosts++;
          req.response.write(jsonEncode(<String, dynamic>{'status': 1}));
        } else if (path == '/gportal/Web/loginAction') {
          req.response.write(jsonEncode(<String, dynamic>{
            'status': 1,
            'info': '认证成功',
            'data': <String, dynamic>{},
          }));
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      } catch (_) {
        await req.response.close();
      }
    });

    final auth = AuthService(baseUrl: base);
    final result = await auth.login(
      username: 'test2024',
      password: 'TestPass123@',
      userAgent: 'TestUA',
    );
    await server.close(force: true);

    expect(result.success, isTrue);
    expect(logoutPosts, 1);
    expect(loginGets, greaterThanOrEqualTo(2));
  });
}