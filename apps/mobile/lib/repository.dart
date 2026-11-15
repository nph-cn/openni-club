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
  String? get authenticationUnavailable {
    if (!isProduction) return null;
    if (isLocal || Uri.tryParse(baseUrl)?.scheme != 'https') {
      return '正式模式需要配置 HTTPS 俱乐部 API。';
    }
    if (wechat.unavailableReason != null) return wechat.unavailableReason;
    if (['privacyText', 'termsText', 'supportContact'].any(
      (key) => club[key] is! String || (club[key] as String).trim().isEmpty,
    )) {
      return '俱乐部尚未完善隐私、服务条款与客服信息，暂不可登录或预约。';
    }
    return null;
  }

  bool loaded = false;
  String? error;
  String? token;
  Json club = {};
  List<Json> banners = [];
  List<Json> services = [];
  List<Json> players = [];
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

  Future<dynamic> request(String method, String path, [Json? body]) async {
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
    final data = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      if (response.statusCode == 401) token = null;
      final error = data is Map ? data['error'] : null;
      throw Exception(error is Map ? error['message'] ?? '请求失败，请稍后重试' : '请求失败');
    }
    return data;
  }

  Future<void> load() async {
    error = null;
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
          following.addAll(prefs.getStringList('openni_following') ?? []);
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
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> signIn() async {
    if (token != null) return;
    if (authenticationUnavailable case final String reason) {
      throw Exception(reason);
    }
    if (isLocal) return;
    final result = isProduction
        ? await request('POST', '/auth/wechat-app', {
            'code': await wechat.authenticate(),
          })
        : await request('POST', '/auth/demo', {'name': memberName});
    token = result['token'];
    if (token == null || token!.isEmpty) throw Exception('登录未完成，请重试。');
    notifyListeners();
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
      orders = (await request('GET', '/orders') as List)
          .map((e) => Json.from(e))
          .toList();
      notifyListeners();
    }
  }

  Future<void> save() async {
    if (persist && isLocal) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('openni_demo_orders', jsonEncode(orders));
      await prefs.setString('openni_name', memberName);
      await prefs.setBool('openni_favorite', favorite);
      await prefs.setStringList('openni_following', following.toList());
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
      final updated = Json.from(await request('GET', '/orders/${order['id']}'));
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
      return availability.putIfAbsent(
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
    final data = await request('GET', '/me');
    role = data['role'];
    memberPlayerId = data['playerId'];
    memberName = data['user']['name'];
    notifyListeners();
  }

  Future<void> rename(String name) async {
    if (name.trim().isEmpty || name.length > 30) {
      throw Exception('昵称需为 1–30 个字符。');
    }
    if (!isLocal) {
      await request('PATCH', '/me', {'name': name});
    }
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
      final data = await request(
        'POST',
        token == null ? '/auth/demo' : '/auth/demo/role',
        {'name': memberName, 'role': value, 'playerId': ?playerId},
      );
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
      if (isProduction) throw Exception('请配置俱乐部 API。');
      final fixture = Json.from(
        jsonDecode(
          await rootBundle.loadString(
            'assets/demo/member-preview.json',
            cache: false,
          ),
        ),
      );
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
    final data = await Future.wait([
      request('GET', '/member/orders'),
      request('GET', '/member/earnings'),
    ]);
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
