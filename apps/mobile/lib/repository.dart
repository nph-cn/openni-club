import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'wechat_gateway.dart';

typedef Json = Map<String, dynamic>;

List<Json> serviceVariants(Json service) =>
    (service['variants'] as List? ?? []).map((v) => Json.from(v)).toList();
Json selectedService(Json service, String? variantId) {
  final variant = serviceVariants(service)
      .where((v) => v['id'] == variantId)
      .firstOrNull;
  return variant == null
      ? service
      : {
          ...service,
          ...variant,
          'id': service['id'],
          'variantId': variant['id'],
          'variantTitle': variant['title'],
          'title': service['title'],
        };
}

class ClubApiException implements Exception {
  const ClubApiException(
    this.code,
    this.message, {
    this.retryAfterSeconds,
    this.attemptsRemaining,
  });
  final String code, message;
  final int? retryAfterSeconds, attemptsRemaining;
  @override
  String toString() => message;
}

class ClubRepository extends ChangeNotifier {
  ClubRepository({
    this._baseUrl = const String.fromEnvironment('API_BASE_URL'),
    this.persist = true,
    this._appMode = const String.fromEnvironment('APP_MODE', defaultValue: ''),
    WechatGateway? wechat,
    DateTime Function()? clock,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _customWechat = wechat != null,
       _clock = clock ?? DateTime.now,
       wechat = wechat ?? NativeWechatGateway();
  final String _baseUrl, _appMode;
  String get baseUrl =>
      _baseUrl.isNotEmpty ? _baseUrl : '${brand['apiBaseUrl'] ?? ''}';
  String get appMode =>
      _appMode.isNotEmpty ? _appMode : '${brand['mode'] ?? 'demo'}';
  Json brand = {};
  final bool persist;
  WechatGateway wechat;
  final bool _customWechat;
  final http.Client _client;
  final DateTime Function() _clock;
  DateTime get now => _clock();
  bool get isLocal => baseUrl.isEmpty;
  bool get isProduction => appMode == 'production';
  String? get operatingUnavailable {
    if (!isProduction) return null;
    if (isLocal || Uri.tryParse(baseUrl)?.scheme != 'https') {
      return '正式模式需要配置 HTTPS 俱乐部 API。';
    }
    if (['privacyText', 'termsText', 'supportContact'].any(
      (key) => club[key] is! String || (club[key] as String).trim().isEmpty,
    )) {
      return '俱乐部尚未完善隐私、服务条款与客服信息，暂不可登录或预约。';
    }
    return null;
  }

  String? get authenticationUnavailable {
    if (operatingUnavailable != null) return operatingUnavailable;
    if (isProduction &&
        token == null &&
        authCapabilities?['sms']?['enabled'] != true) {
      return wechat.unavailableReason;
    }
    return null;
  }

  String? get wechatUnavailable =>
      wechat.unavailableReason ??
      (authCapabilities != null &&
              authCapabilities?['wechatApp']?['enabled'] != true
          ? '俱乐部尚未开通微信登录'
          : null);

  bool loaded = false, loading = false;
  Json? authCapabilities;
  final Map<String, Json> _localChallenges = {};
  DateTime? _lastLocalChallenge;
  int _challengeSequence = 0;
  String? error;
  int _sessionRevision = 0;
  String? _token;
  String? get token => _token;
  set token(String? value) {
    if (_token == value) return;
    _token = value;
    _sessionRevision++;
  }

  Json club = {};
  List<Json> banners = [];
  List<Json> services = [];
  List<Json> players = [];
  List<Json> games = [];
  List<Json> tiers = [];
  List<Json> clubFeatures = [];
  List<Json> announcements = [];
  List<Json> orders = [];
  bool favorite = false;
  final following = <String>{};
  String memberName = '新朋友';
  String role = 'customer';
  String? memberPlayerId;
  List<Json> notifications = [], memberOrders = [];
  Json earnings = {};
  final availability = <String, List<Json>>{};
  String get clubName => '${club['name'] ?? brand['name'] ?? '俱乐部'}';
  String get shortName =>
      '${club['shortName'] ?? brand['shortName'] ?? clubName}';

  /// 只展示俱乐部已开通且启用的游戏类目。
  List<Json> get enabledGames => games
      .where((game) => game['enabled'] != false)
      .toList()
    ..sort(
      (a, b) => (a['sortOrder'] as num? ?? 99).compareTo(
        b['sortOrder'] as num? ?? 99,
      ),
    );

  Json? gameByName(String name) {
    for (final game in games) {
      if ('${game['name']}' == name) return game;
    }
    return null;
  }

  Json? playerById(String? id) {
    if (id == null) return null;
    for (final player in players) {
      if ('${player['id']}' == id) return player;
    }
    return null;
  }

  Json? tierFor(Json player) {
    final id = '${player['tier'] ?? ''}';
    if (id.isEmpty) return null;
    for (final tier in tiers) {
      if ('${tier['id']}' == id) return tier;
    }
    return null;
  }

  List<Json> get certifiedPlayers => players
      .where((player) => player['certified'] == true)
      .toList();

  bool featureEnabled(String id) => clubFeatures.any(
    (feature) => feature['id'] == id && feature['enabled'] == true,
  );


  void _requireSession(int revision) {
    if (revision != _sessionRevision) {
      throw const ClubApiException('SESSION_CHANGED', '登录状态已改变，请重试。');
    }
  }

  Future<dynamic> request(String method, String path, [Json? body]) async {
    final revision = _sessionRevision;
    final personalRequest =
        method != 'GET' ||
        RegExp(r'^/(?:me|orders|member|account|notifications)(?:/|\?|$)')
            .hasMatch(path);
    final uri = Uri.parse('${baseUrl.replaceFirst(RegExp(r'/$'), '')}$path');
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final http.Response response;
    switch (method) {
      case 'POST':
        response = await _client
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 15));
      case 'PATCH':
        response = await _client
            .patch(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 15));
      case 'PUT':
        response = await _client
            .put(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 15));
      case 'DELETE':
        response = await _client
            .delete(uri, headers: headers)
            .timeout(const Duration(seconds: 15));
      default:
        response = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 15));
    }
    // 旧会话的个人资料和操作响应不能写回当前账号；公开目录仍可继续加载。
    if (personalRequest) _requireSession(revision);
    final data = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      if (response.statusCode == 401 &&
          !path.startsWith('/auth/') &&
          revision == _sessionRevision) {
        token = null;
      }
      final error = data is Map ? data['error'] : null;
      throw ClubApiException(
        error is Map
            ? '${error['code'] ?? 'REQUEST_FAILED'}'
            : 'REQUEST_FAILED',
        error is Map ? '${error['message'] ?? '请求失败，请稍后重试'}' : '请求失败',
        retryAfterSeconds: error is Map
            ? error['retryAfterSeconds'] as int?
            : null,
        attemptsRemaining: error is Map
            ? error['attemptsRemaining'] as int?
            : null,
      );
    }
    return data;
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      try {
        brand = Json.from(
          jsonDecode(
            await rootBundle.loadString('assets/brand.json', cache: false),
          ),
        );
        club = {...brand};
        if (!_customWechat) {
          const appId = String.fromEnvironment('WECHAT_APP_ID');
          const link = String.fromEnvironment('WECHAT_UNIVERSAL_LINK');
          wechat = NativeWechatGateway(
            appId: appId.isNotEmpty ? appId : '${brand['wechatAppId'] ?? ''}',
            universalLink: link.isNotEmpty
                ? link
                : '${brand['universalLink'] ?? ''}',
          );
        }
      } catch (_) {
        /* Unit tests may intentionally omit the generated brand. */
      }
      if (!['demo', 'production'].contains(appMode)) {
        throw Exception('APP_MODE 必须为 demo 或 production。');
      }
      if (isProduction &&
          (isLocal || Uri.tryParse(baseUrl)?.scheme != 'https')) {
        services = [];
        players = [];
        announcements = [];
        club = {};
        throw Exception('正式模式必须配置 HTTPS API_BASE_URL。');
      }
      if (persist) {
        final prefs = await SharedPreferences.getInstance();
        following.addAll(prefs.getStringList('openni_following') ?? []);
      }
      if (isLocal) {
        final catalog = Json.from(
          jsonDecode(
            await rootBundle.loadString('assets/catalog.json', cache: false),
          ),
        );
        banners = (catalog['banners'] as List? ?? [])
            .map((v) => Json.from(v))
            .toList();
        services = (catalog['services'] as List)
            .map((v) => Json.from(v))
            .toList();
        players = (catalog['players'] as List)
            .map((v) => Json.from(v))
            .toList();
        games = (catalog['games'] as List? ?? [])
            .map((v) => Json.from(v))
            .toList();
        tiers = (catalog['tiers'] as List? ?? [])
            .map((v) => Json.from(v))
            .toList();
        clubFeatures = (catalog['clubFeatures'] as List? ?? [])
            .map((v) => Json.from(v))
            .toList();
        announcements = (catalog['announcements'] as List)
            .map((v) => Json.from(v))
            .toList();
        if (persist) {
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getString('openni_demo_orders');
          if (raw != null) {
            orders = (jsonDecode(raw) as List)
                .map((e) => Json.from(e))
                .toList();
          }
          memberName = prefs.getString('openni_name') ?? memberName;
          favorite = prefs.getBool('openni_favorite') ?? false;
        }
      } else {
        services = [];
        players = [];
        announcements = [];
        final results = await Future.wait([
          request('GET', '/club'),
          request('GET', '/services'),
          request('GET', '/players'),
          request('GET', '/announcements'),
          request('GET', '/banners'),
        ]);
        club = {...brand, ...Json.from(results[0])};
        if (isProduction && club['demoData'] != false) {
          throw Exception('俱乐部仍在使用演示资料，正式模式暂不可用。');
        }
        services = (results[1] as List).map((e) => Json.from(e)).toList();
        players = (results[2] as List).map((e) => Json.from(e)).toList();
        announcements = (results[3] as List).map((e) => Json.from(e)).toList();
        banners = (results[4] as List).map((e) => Json.from(e)).toList();
      }
      // 兼容尚未返回 games/tiers 的旧接口与网关：从真实服务目录派生，不编造新类目。
      if (games.isEmpty) {
        final names = <String>[];
        for (final service in services) {
          final name = '${service['game'] ?? ''}'.trim();
          if (name.isNotEmpty && !names.contains(name)) names.add(name);
        }
        games = [
          for (var i = 0; i < names.length; i++)
            Json.from({
              'id': 'game-${i + 1}',
              'name': names[i],
              'shortName': names[i],
              'category': '游戏',
              'platform': 'PC',
              'accent': '#8A9A5B',
              'enabled': true,
              'sortOrder': i + 1,
              'coverUrl': services
                  .firstWhere((s) => s['game'] == names[i])['coverUrl'],
              'description': '',
            }),
        ];
      }
      if (tiers.isEmpty) {
        tiers = [
          for (final tier in const [
            ('S', '王牌', 5, '#C6A15B'),
            ('A', '精英', 4, '#6FA7C9'),
            ('B', '进阶', 3, '#8FB27C'),
            ('C', '新锐', 2, '#A8A8A8'),
          ])
            Json.from({
              'id': tier.$1,
              'label': tier.$2,
              'level': tier.$3,
              'color': tier.$4,
              'perks': const <String>[],
            }),
        ];
      }
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    loaded = true;
    loading = false;
    notifyListeners();
  }

  Future<Json> loadAuthCapabilities({bool force = false}) async {
    if (authCapabilities != null && !force) return authCapabilities!;
    if (isLocal && !isProduction) {
      authCapabilities = {
        'mode': 'demo',
        'wechatApp': {'enabled': false},
        'sms': {
          'enabled': true,
          'provider': 'test',
          'testMode': true,
          'codeLength': 6,
          'expiresInSeconds': 300,
          'retryAfterSeconds': 60,
        },
      };
    } else {
      authCapabilities = Json.from(await request('GET', '/auth/capabilities'));
    }
    notifyListeners();
    return authCapabilities!;
  }

  Future<Json> requestSmsChallenge(String phone) async {
    phone = phone.trim().replaceFirst(RegExp(r'^\+86'), '');
    if (!RegExp(r'^1[3-9][0-9]{9}$').hasMatch(phone)) {
      throw const ClubApiException('PHONE_INVALID', '请输入正确的手机号');
    }
    if (isLocal && !isProduction) {
      final elapsed = _lastLocalChallenge == null
          ? 60
          : now.difference(_lastLocalChallenge!).inSeconds;
      if (elapsed < 60) {
        throw ClubApiException(
          'SMS_COOLDOWN',
          '请稍后重新获取',
          retryAfterSeconds: 60 - elapsed,
        );
      }
      for (final challenge in _localChallenges.values) {
        if (challenge['phone'] == phone && challenge['used'] != true) {
          challenge['superseded'] = true;
        }
      }
      _lastLocalChallenge = now;
      final id = 'local-${++_challengeSequence}';
      _localChallenges[id] = {
        'phone': phone,
        'code': '123456',
        'expiresAt': now.add(const Duration(minutes: 5)),
        'attempts': 0,
      };
      return {
        'challengeId': id,
        'phoneMasked': '${phone.substring(0, 3)}****${phone.substring(7)}',
        'expiresInSeconds': 300,
        'retryAfterSeconds': 60,
        'delivery': 'test',
        'testCode': '123456',
      };
    }
    return Json.from(
      await request('POST', '/auth/sms/challenges', {'phone': phone}),
    );
  }

  Future<void> verifySms(String challengeId, String code) async {
    final revision = _sessionRevision;
    if (isLocal && !isProduction) {
      final challenge = _localChallenges[challengeId];
      if (challenge == null) {
        throw const ClubApiException('OTP_INVALID', '验证码无效，请重新获取');
      }
      if (challenge['used'] == true) {
        throw const ClubApiException('OTP_USED', '验证码已使用，请重新获取');
      }
      if (challenge['superseded'] == true) {
        throw const ClubApiException('OTP_SUPERSEDED', '请使用最新验证码');
      }
      if (!now.isBefore(challenge['expiresAt'] as DateTime)) {
        throw const ClubApiException('OTP_EXPIRED', '验证码已过期，请重新获取');
      }
      if ((challenge['attempts'] as int) >= 5) {
        throw const ClubApiException(
          'OTP_ATTEMPTS_EXCEEDED',
          '尝试次数过多，请重新获取',
          retryAfterSeconds: 60,
        );
      }
      if (challenge['code'] != code) {
        challenge['attempts'] = (challenge['attempts'] as int) + 1;
        throw ClubApiException(
          'OTP_INVALID',
          '验证码不正确',
          attemptsRemaining: 5 - (challenge['attempts'] as int),
        );
      }
      challenge['used'] = true;
      token = 'local-preview-session';
      memberName = '手机用户';
      role = 'customer';
      memberPlayerId = null;
      notifyListeners();
      return;
    }
    _applySession(
      Json.from(
        await request('POST', '/auth/sms/verify', {
          'challengeId': challengeId,
          'code': code,
        }),
      ),
      revision: revision,
    );
    await loadAccount();
  }

  void _applySession(Json result, {required int revision}) {
    _requireSession(revision);
    final value = result['token'];
    if (value is! String || value.isEmpty) {
      throw const ClubApiException('AUTH_FAILED', '登录未完成，请重试');
    }
    token = value;
    if (result['user'] is Map) memberName = '${result['user']['name']}';
    role = '${result['role'] ?? 'customer'}';
    memberPlayerId = result['playerId'];
    notifyListeners();
  }

  Future<void> signInWithWechat() async {
    final revision = _sessionRevision;
    if (wechatUnavailable case final String reason) throw Exception(reason);
    if (isLocal) throw Exception('微信登录需要连接俱乐部');
    _applySession(
      Json.from(
        await request('POST', '/auth/wechat-app', {
          'code': await _authenticateWechat(revision),
        }),
      ),
      revision: revision,
    );
    await loadAccount();
  }

  Future<void> linkWechatForPayment() async {
    final revision = _sessionRevision;
    if (token == null || isLocal) throw Exception('请先登录');
    if (wechat.unavailableReason case final String reason) {
      throw Exception(reason);
    }
    _applySession(
      Json.from(
        await request('POST', '/auth/wechat-app/link', {
          'code': await _authenticateWechat(revision),
        }),
      ),
      revision: revision,
    );
    await loadAccount();
  }

  Future<void> signIn() async {
    if (token != null) return;
    if (authenticationUnavailable case final String reason) {
      throw Exception(reason);
    }
    if (isLocal) return;
    final revision = _sessionRevision;
    final result = isProduction
        ? await request('POST', '/auth/wechat-app', {
            'code': await _authenticateWechat(revision),
          })
        : await request('POST', '/auth/demo', {'name': memberName});
    _requireSession(revision);
    token = result['token'];
    if (token == null || token!.isEmpty) throw Exception('登录未完成，请重试。');
    notifyListeners();
  }

  Future<String> _authenticateWechat(int revision) async {
    final code = await wechat.authenticate();
    _requireSession(revision);
    return code;
  }

  Future<void> loadDemoPreview() async {
    if (!isLocal || isProduction || orders.isNotEmpty) return;
    final fixture = Json.from(
      jsonDecode(
        await rootBundle.loadString(
          'assets/demo/order-in-progress.json',
          cache: false,
        ),
      ),
    );
    orders = [fixture];
    notifyListeners();
  }

  Future<void> refreshOrders() async {
    if (!isLocal) {
      await signIn();
      final revision = _sessionRevision;
      final result = await request('GET', '/orders');
      _requireSession(revision);
      orders = (result as List).map((e) => Json.from(e)).toList();
      notifyListeners();
    }
  }

  Future<void> save() async {
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('openni_following', following.toList());
      if (isLocal) {
        await prefs.setString('openni_demo_orders', jsonEncode(orders));
        await prefs.setString('openni_name', memberName);
        await prefs.setBool('openni_favorite', favorite);
      }
    }
    notifyListeners();
  }

  Future<Json> book({
    required Json service,
    String? variantId,
    Json? player,
    required DateTime date,
    required String contact,
    required String note,
    required String idempotencyKey,
  }) async {
    final canonical = findService('${service['id']}');
    if (canonical == null) throw Exception('服务已不可用，请重新选择。');
    final variants = serviceVariants(canonical);
    if (variants.isNotEmpty && !variants.any((v) => v['id'] == variantId)) {
      throw Exception('请选择有效的服务规格。');
    }
    final selected = selectedService(canonical, variantId);
    if ((selected['teamSize'] as num? ?? 1) > 1) {
      throw Exception('当前暂不支持多成员订单，请联系俱乐部。');
    }
    if (isProduction) {
      if (authenticationUnavailable case final String reason) {
        throw Exception(reason);
      }
      await signIn();
    }
    final Json order;
    if (isLocal) {
      final existing = orders.where(
        (o) => o['idempotencyKey'] == idempotencyKey,
      );
      if (existing.isNotEmpty) return existing.first;
      order = {
        'id': 'ON${now.millisecondsSinceEpoch}',
        'serviceId': service['id'],
        'serviceTitle': service['title'],
        'variantId': variantId,
        'serviceSnapshot': selected,
        'playerId': player?['id'],
        'scheduledAt': date.toUtc().toIso8601String(),
        'contact': contact,
        'note': note,
        'priceCents': selected['priceCents'],
        'durationMinutes': selected['durationMinutes'],
        'status': 'pending',
        'fulfillmentStatus': 'awaiting_assignment',
        'paymentStatus': 'unpaid',
        'events': [
          {
            'id': 'created-${now.microsecondsSinceEpoch}',
            'type': 'created',
            'at': now.toUtc().toIso8601String(),
            'actor': {'role': 'customer', 'name': memberName},
            'message': '预约已提交，等待俱乐部安排',
          },
        ],
        'createdAt': now.toUtc().toIso8601String(),
        'idempotencyKey': idempotencyKey,
      };
    } else {
      await signIn();
      order = Json.from(
        await request('POST', '/orders', {
          'serviceId': service['id'],
          'variantId': ?variantId,
          'playerId': player?['id'],
          'scheduledAt': date.toUtc().toIso8601String(),
          'contact': contact,
          'note': note,
          'idempotencyKey': idempotencyKey,
        }),
      );
    }
    orders.insert(0, order);
    await save();
    return order;
  }

  Future<void> cancel(Json order) async {
    if (!['pending', 'confirmed'].contains(order['status'])) {
      throw Exception('当前订单不能取消');
    }
    if (!isLocal) {
      final updated = Json.from(
        await request('PATCH', '/orders/${order['id']}/cancel', {}),
      );
      order.addAll(updated);
    } else {
      order['status'] = 'cancelled';
      order['fulfillmentStatus'] = 'cancelled';
      (order['events'] as List? ?? []).add({
        'id': 'cancel-${now.microsecondsSinceEpoch}',
        'type': 'cancelled',
        'at': now.toUtc().toIso8601String(),
        'actor': {'role': 'customer', 'name': memberName},
        'message': '客户取消了预约',
      });
    }
    await save();
  }

  Future<void> refreshOrder(Json order) async {
    if (!isLocal) {
      final revision = _sessionRevision;
      final updated = Json.from(await request('GET', '/orders/${order['id']}'));
      _requireSession(revision);
      order.addAll(updated);
      await save();
    }
  }

  Future<void> pay(Json order) async {
    if (!isProduction || isLocal) throw Exception('演示模式不发起真实支付。');
    if (authenticationUnavailable case final String reason) {
      throw Exception(reason);
    }
    await signIn();
    if (!['pending', 'confirmed'].contains(order['status']) ||
        !['unpaid', 'pending'].contains(order['paymentStatus']) ||
        (order['priceCents'] as num? ?? 0) <= 0) {
      throw Exception('当前订单不需要付款。');
    }
    final payment = Json.from(
      await request('POST', '/orders/${order['id']}/pay', {}),
    );
    try {
      await wechat.pay(Json.from(payment['paymentParams']));
    } finally {
      // A cancellation / app switch can race the verified server notification.
      // Always read the server result, and never assign `paid` on the client.
      await refreshOrder(order);
    }
  }

  /// 结束本机会话，不调用账号删除接口，也不删除演示预约或本机关注。
  Future<void> signOut() async {
    // 即使登录请求还没返回、token 仍为空，也撤销该次会话意图。
    _sessionRevision++;
    token = null;
    role = 'customer';
    memberPlayerId = null;
    memberOrders = [];
    notifications = [];
    earnings = {};
    if (!isLocal) {
      orders = [];
      memberName = '新朋友';
    }
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    if (!isLocal) {
      await signIn();
      await request('DELETE', '/account');
    }
    token = null;
    orders.clear();
    favorite = false;
    following.clear();
    memberName = '新朋友';
    await save();
  }

  Json? findService(String id) =>
      services.where((s) => s['id'] == id).firstOrNull;
  Json? findPlayer(String? id) =>
      players.where((s) => s['id'] == id).firstOrNull;

  Future<void> toggleFollow(String id) async {
    following.contains(id) ? following.remove(id) : following.add(id);
    await save();
  }

  Future<List<Json>> getAvailability(
    String playerId,
    DateTime date,
    int duration,
  ) async {
    final day =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final key = '$playerId/$day/$duration';
    if (isLocal) {
      // Explicit local demo schedule. Remote mode never invents availability.
      final slots = availability.putIfAbsent(
        key,
        () => [14, 16, 18, 20].map((hour) {
          final start = DateTime.utc(
            date.year,
            date.month,
            date.day,
            hour,
          ).subtract(const Duration(hours: 8));
          return <String, dynamic>{
            'startAt': start.toUtc().toIso8601String(),
            'endAt': start
                .add(Duration(minutes: duration))
                .toUtc()
                .toIso8601String(),
            'available': true,
            'busy': false,
          };
        }).toList(),
      );
      // 缓存保留完整排班，每次读取按当前时间排除已经错过的开始时段。
      final earliest = now.toUtc().add(const Duration(minutes: 1));
      return slots.where((slot) {
        final start = DateTime.tryParse('${slot['startAt']}');
        return start != null && start.toUtc().isAfter(earliest);
      }).toList();
    }
    final result = await request(
      'GET',
      '/players/$playerId/availability?date=$day&durationMinutes=$duration',
    );
    final slots = (result['slots'] as List).map((e) => Json.from(e)).toList();
    availability[key] = slots;
    return slots;
  }

  Future<void> loadAccount() async {
    if (isLocal) return;
    await signIn();
    final revision = _sessionRevision;
    final data = await request('GET', '/me');
    _requireSession(revision);
    role = data['role'];
    memberPlayerId = data['playerId'];
    memberName = data['user']['name'];
    notifyListeners();
  }

  Future<void> rename(String name) async {
    final revision = _sessionRevision;
    if (name.trim().isEmpty || name.length > 30) {
      throw Exception('昵称需为 1–30 个字符。');
    }
    if (!isLocal) {
      await request('PATCH', '/me', {'name': name});
    }
    _requireSession(revision);
    memberName = name;
    await save();
  }

  Future<void> acceptInvitation(String code) async {
    if (isLocal || token == null) throw Exception('请先登录俱乐部账号。');
    await request('POST', '/member/invitation/accept', {'code': code});
    await loadAccount();
  }

  Future<void> switchDemoRole(String value, {String? playerId}) async {
    if (isProduction) throw Exception('成员权限由俱乐部邀请分配。');
    if (!isLocal) {
      final revision = _sessionRevision;
      final data = await request(
        'POST',
        token == null ? '/auth/demo' : '/auth/demo/role',
        {'name': memberName, 'role': value, 'playerId': ?playerId},
      );
      _requireSession(revision);
      token = data['token'] ?? token;
      await loadAccount();
    } else {
      role = value;
      memberPlayerId = playerId;
    }
    notifyListeners();
  }

  Future<Json> orderAction(
    Json order,
    String action, [
    Json body = const {},
  ]) async {
    if (isLocal) throw Exception('此履约操作需要连接俱乐部演示 API。');
    final updated = Json.from(
      await request('POST', '/orders/${order['id']}/$action', body),
    );
    order.addAll(updated);
    notifyListeners();
    return order;
  }

  Future<void> loadMemberData() async {
    if (isLocal) {
      final revision = _sessionRevision;
      if (isProduction) throw Exception('请配置俱乐部 API。');
      final fixture = Json.from(
        jsonDecode(
          await rootBundle.loadString(
            'assets/demo/member-preview.json',
            cache: false,
          ),
        ),
      );
      _requireSession(revision);
      role = 'member';
      memberPlayerId = fixture['me']['playerId'];
      memberName = fixture['me']['user']['name'];
      memberOrders = (fixture['orders'] as List)
          .map((v) => Json.from(v))
          .toList();
      earnings = Json.from(fixture['earnings']);
      notifications = (fixture['notifications'] as List)
          .map((v) => Json.from(v))
          .toList();
      notifyListeners();
      return;
    }
    await loadAccount();
    if (role != 'member') throw Exception('此账号尚未绑定俱乐部成员。');
    final revision = _sessionRevision;
    final data = await Future.wait([
      request('GET', '/member/orders'),
      request('GET', '/member/earnings'),
    ]);
    _requireSession(revision);
    memberOrders = (data[0] as List).map((e) => Json.from(e)).toList();
    earnings = Json.from(data[1]);
    notifyListeners();
  }

  Future<void> memberAction(
    Json order,
    String action, [
    Json body = const {},
  ]) async {
    if (isLocal) throw Exception('请先连接俱乐部 API，才能执行成员操作。');
    if (role != 'member') throw Exception('此账号没有成员权限。');
    final result = Json.from(
      await request('POST', '/member/orders/${order['id']}/$action', body),
    );
    order.addAll(result);
    await loadMemberData();
  }

  Future<List<Json>> memberAvailability() async {
    if (isLocal) {
      final fixture = Json.from(
        jsonDecode(
          await rootBundle.loadString(
            'assets/demo/member-preview.json',
            cache: false,
          ),
        ),
      );
      return (fixture['availability']['slots'] as List)
          .map((v) => Json.from(v))
          .toList();
    }
    final value = await request('GET', '/member/availability');
    return (value['slots'] as List).map((s) => Json.from(s)).toList();
  }

  Future<void> setMemberAvailability(List<Json> slots) async {
    if (isLocal) throw Exception('成员排班需要连接俱乐部 API。');
    await request('PUT', '/member/availability', {'slots': slots});
    notifyListeners();
  }
}
