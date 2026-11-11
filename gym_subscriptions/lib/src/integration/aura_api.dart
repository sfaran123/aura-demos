// Connection to the AURA backend (the same Laravel app the POS uses).
//
// Sign-in works like the AURA POS app:
//   1. Domain screen: GET https://<domain>/verify?tenant=<company>
//      with the X-API-KEY header -> 200 when the company exists.
//   2. Login screen:  POST https://<company>.<domain>/api/login
//      {name, password} -> {token, data: user}.
//   3. Every later API call sends the token in the `token` header.
//
// The verify key is not in the source (this repository is public). Pass it
// when running or building:
//   flutter run --dart-define=AURA_VERIFY_KEY=<key>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AuraConfig {
  /// Prefilled on the domain screen.
  static const defaultDomain = 'auratech2';
  static const defaultCompany = 'aurademo1';

  /// Header value for GET /verify, from --dart-define=AURA_VERIFY_KEY.
  static const verifyKey = String.fromEnvironment('AURA_VERIFY_KEY');

  static const timeout = Duration(seconds: 20);

  /// "auratech2", "auratech2.tech", "https://auratech2.tech/" -> "auratech2.tech".
  /// A name without a dot gets ".tech", like the POS app.
  static String normalizeDomain(String input) {
    var d = input.trim().toLowerCase();
    d = d.replaceFirst(RegExp(r'^https?://'), '');
    d = d.split('/').first;
    if (d.isEmpty) return d;
    return d.contains('.') ? d : '$d.tech';
  }

  static String normalizeCompany(String input) => input.trim().toLowerCase();
}

/// The business this device signs in to.
class AuraWorkspace {
  const AuraWorkspace({required this.domain, required this.company});

  /// Base domain, e.g. "auratech2.tech".
  final String domain;

  /// Tenant id, e.g. "aurademo1".
  final String company;

  /// e.g. https://aurademo1.auratech2.tech/api/login
  Uri api(String path) => Uri.parse('https://$company.$domain/api$path');

  Map<String, dynamic> toJson() => {'domain': domain, 'company': company};

  static AuraWorkspace? fromJson(Object? j) {
    if (j is! Map) return null;
    final domain = j['domain'], company = j['company'];
    if (domain is! String || company is! String || domain.isEmpty || company.isEmpty) return null;
    return AuraWorkspace(domain: domain, company: company);
  }
}

/// The signed-in user, from POST /api/login.
class AuraSession {
  const AuraSession({
    required this.token,
    required this.userId,
    required this.userName,
    this.email = '',
    this.phone = '',
    this.companyName = '',
    this.roleId = '',
    this.warehouseId,
    this.tapToPayTpn = '',
    this.tapToPayMerchantCode = '',
  });

  final String token;
  final String userId;
  final String userName;
  final String email;
  final String phone;
  final String companyName;
  final String roleId;
  final int? warehouseId;

  /// Dejavoo Tap to Pay TPN and merchant code of this user (web: Users > Setting Info);
  /// empty when not set (a sandbox build then uses Dejavoo's sandbox pair).
  final String tapToPayTpn;
  final String tapToPayMerchantCode;

  /// Headers for authenticated API calls.
  Map<String, String> get headers => {'Content-Type': 'application/json', 'Accept': 'application/json', 'token': token};

  static AuraSession? fromLoginResponse(Object? body) {
    if (body is! Map) return null;
    final token = body['token'];
    final user = body['data'];
    if (token == null || '$token'.isEmpty || user is! Map) return null;
    String s(String k) => user[k] == null ? '' : '${user[k]}';
    final wh = user['warehouse_id'];
    return AuraSession(
      token: '$token',
      userId: s('id'),
      userName: s('name'),
      email: s('email'),
      phone: s('phone'),
      companyName: s('company_name'),
      roleId: s('role_id'),
      warehouseId: wh is int ? wh : int.tryParse('${wh ?? ''}'),
      tapToPayTpn: s('tap_to_pay_tpn'),
      tapToPayMerchantCode: s('tap_to_pay_merchant_code'),
    );
  }

  Map<String, dynamic> toJson() => {
        'token': token,
        'userId': userId,
        'userName': userName,
        'email': email,
        'phone': phone,
        'companyName': companyName,
        'roleId': roleId,
        'warehouseId': warehouseId,
        'tapToPayTpn': tapToPayTpn,
        'tapToPayMerchantCode': tapToPayMerchantCode,
      };

  static AuraSession? fromJson(Object? j) {
    if (j is! Map || j['token'] is! String || (j['token'] as String).isEmpty) return null;
    String s(String k) => j[k] is String ? j[k] as String : '';
    final wh = j['warehouseId'];
    return AuraSession(
      token: j['token'] as String,
      userId: s('userId'),
      userName: s('userName'),
      email: s('email'),
      phone: s('phone'),
      companyName: s('companyName'),
      roleId: s('roleId'),
      warehouseId: wh is int ? wh : null,
      tapToPayTpn: s('tapToPayTpn'),
      tapToPayMerchantCode: s('tapToPayMerchantCode'),
    );
  }
}

/// Why a call failed. The UI turns [kind] into a translated message.
enum AuraErrorKind {
  /// No AURA_VERIFY_KEY in this build.
  noVerifyKey,

  /// /verify answered "Tenant not found".
  companyNotFound,

  /// Wrong username or password.
  badCredentials,

  /// No internet, DNS failure, or the server refused the connection.
  unreachable,

  /// The server did not answer in time.
  timeout,

  /// The token is no longer valid (signed in elsewhere, or the user was deactivated).
  sessionExpired,

  /// The user's role lacks the permission. [AuraApiException.detail] has the server message.
  forbidden,

  /// Anything else (5xx, unexpected body...). [AuraApiException.detail] has more.
  server,
}

class AuraApiException implements Exception {
  AuraApiException(this.kind, [this.detail = '']);
  final AuraErrorKind kind;
  final String detail;

  @override
  String toString() => 'AuraApiException($kind${detail.isEmpty ? '' : ': $detail'})';
}

class _Response {
  _Response(this.status, this.body);
  final int status;
  final Object? body;
}

class AuraApi {
  AuraApi({HttpClient Function()? client}) : _newClient = client ?? HttpClient.new;
  final HttpClient Function() _newClient;

  /// Checks that [company] exists on [domain] (e.g. "aurademo1" on "auratech2.tech").
  Future<void> verifyCompany({required String domain, required String company}) async {
    if (AuraConfig.verifyKey.isEmpty) throw AuraApiException(AuraErrorKind.noVerifyKey);
    final uri = Uri.https(domain, '/verify', {'tenant': company});
    final r = await _send('GET', uri, headers: {'X-API-KEY': AuraConfig.verifyKey});
    if (r.status == 200) return;
    if (r.status == 422) throw AuraApiException(AuraErrorKind.companyNotFound);
    throw AuraApiException(AuraErrorKind.server, 'HTTP ${r.status}');
  }

  /// Signs in with the AURA username (not the email) and password.
  Future<AuraSession> login(AuraWorkspace workspace, {required String name, required String password}) async {
    final r = await _send('POST', workspace.api('/login'), body: {'name': name, 'password': password});
    if (r.status == 200) {
      final session = AuraSession.fromLoginResponse(r.body);
      if (session != null) return session;
      throw AuraApiException(AuraErrorKind.server, 'Unexpected login response');
    }
    if (r.status == 422) {
      final body = r.body;
      // The backend answers {"msg": "invalid credentials"} for a wrong
      // username/password (and inactive users).
      if (body is Map && body['msg'] == 'invalid credentials') throw AuraApiException(AuraErrorKind.badCredentials);
      final msg = body is Map ? (body['message'] ?? body['msg']) : null;
      throw AuraApiException(AuraErrorKind.server, msg == null ? 'HTTP 422' : '$msg');
    }
    if (r.status == 404) throw AuraApiException(AuraErrorKind.companyNotFound);
    throw AuraApiException(AuraErrorKind.server, 'HTTP ${r.status}');
  }

  /// Authenticated GET of `https://<company>.<domain>/api<path>`; returns the decoded JSON.
  Future<Object?> getJson(AuraWorkspace workspace, AuraSession session, String path,
      {Map<String, String>? query}) async {
    var uri = workspace.api(path);
    if (query != null && query.isNotEmpty) uri = uri.replace(queryParameters: query);
    return _answer(await _send('GET', uri, headers: {'token': session.token}), path);
  }

  /// Authenticated POST of a JSON body; returns the decoded JSON answer.
  Future<Object?> postJson(AuraWorkspace workspace, AuraSession session, String path, Map<String, Object?> body) async {
    return _answer(await _send('POST', workspace.api(path), headers: {'token': session.token}, body: body), path);
  }

  Object? _answer(_Response r, String path) {
    if (r.status == 200) return r.body;
    final body = r.body;
    final msg = body is Map ? (body['message'] ?? body['msg']) : null;
    if (r.status == 401) throw AuraApiException(AuraErrorKind.sessionExpired);
    if (r.status == 403) throw AuraApiException(AuraErrorKind.forbidden, msg == null ? path : '$msg');
    throw AuraApiException(AuraErrorKind.server, 'HTTP ${r.status}${msg == null ? '' : ': $msg'}');
  }

  Future<_Response> _send(String method, Uri uri, {Map<String, String> headers = const {}, Object? body}) async {
    final client = _newClient()..connectionTimeout = AuraConfig.timeout;
    try {
      return await () async {
        final req = await client.openUrl(method, uri);
        req.headers.set(HttpHeaders.acceptHeader, 'application/json');
        headers.forEach(req.headers.set);
        if (body != null) {
          final bytes = utf8.encode(jsonEncode(body));
          req.headers.contentType = ContentType.json;
          req.contentLength = bytes.length;
          req.add(bytes);
        }
        final res = await req.close();
        final text = await res.transform(utf8.decoder).join();
        Object? json;
        try {
          json = text.isEmpty ? null : jsonDecode(text);
        } on FormatException {
          json = null;
        }
        return _Response(res.statusCode, json);
      }()
          .timeout(AuraConfig.timeout);
    } on TimeoutException {
      throw AuraApiException(AuraErrorKind.timeout);
    } on SocketException catch (e) {
      throw AuraApiException(AuraErrorKind.unreachable, e.message);
    } on HandshakeException catch (e) {
      throw AuraApiException(AuraErrorKind.unreachable, e.message);
    } on HttpException catch (e) {
      throw AuraApiException(AuraErrorKind.unreachable, e.message);
    } finally {
      client.close(force: true);
    }
  }
}
