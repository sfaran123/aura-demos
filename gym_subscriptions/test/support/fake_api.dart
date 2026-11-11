import 'package:aura_gym/src/integration/aura_api.dart';

/// Backend stand-in: company "aurademo1" on "auratech2.tech", user admin/secret.
/// [responses] answers GET paths (e.g. '/gym/members'); a missing path returns
/// an empty, valid answer. [errors] makes a path throw.
class FakeApi extends AuraApi {
  final calls = <String>[];
  final Map<String, Object?> responses = {};
  final Map<String, AuraApiException> errors = {};

  @override
  Future<void> verifyCompany({required String domain, required String company}) async {
    calls.add('verify $company@$domain');
    if (domain != 'auratech2.tech') throw AuraApiException(AuraErrorKind.unreachable);
    if (company != 'aurademo1') throw AuraApiException(AuraErrorKind.companyNotFound);
  }

  @override
  Future<AuraSession> login(AuraWorkspace workspace, {required String name, required String password}) async {
    calls.add('login $name ${workspace.api('/login')}');
    if (name != 'admin' || password != 'secret') throw AuraApiException(AuraErrorKind.badCredentials);
    return AuraSession.fromLoginResponse({
      'token': 'tok123',
      'data': {'id': 1, 'name': 'admin', 'email': 'a@b.c', 'company_name': 'Demo', 'role_id': 1, 'warehouse_id': 2},
    })!;
  }

  /// POST bodies sent, by path.
  final posts = <(String, Map<String, Object?>)>[];

  /// Answers POST paths; a [postErrors] entry makes the POST throw (GETs of the same path still work).
  final Map<String, AuraApiException> postErrors = {};
  final Map<String, Object? Function(Map<String, Object?> body)> postHandlers = {};

  @override
  Future<Object?> postJson(AuraWorkspace workspace, AuraSession session, String path, Map<String, Object?> body) async {
    calls.add('POST $path');
    posts.add((path, body));
    final err = postErrors[path] ?? errors[path];
    if (err != null) throw err;
    final h = postHandlers[path];
    if (h == null) throw AuraApiException(AuraErrorKind.server, 'HTTP 404');
    return h(body);
  }

  @override
  Future<Object?> getJson(AuraWorkspace workspace, AuraSession session, String path,
      {Map<String, String>? query}) async {
    final q = query == null || query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    calls.add('GET $path$q');
    final err = errors[path];
    if (err != null) throw err;
    if (responses.containsKey('$path$q')) return responses['$path$q'];
    if (responses.containsKey(path)) return responses[path];
    return switch (path) {
      '/sales/getproduct-v2' => <Object?>[],
      '/sales' => {
          'data': {'sale_data': <Object?>[], 'last_page': 1}
        },
      _ => {'data': <Object?>[]},
    };
  }
}
