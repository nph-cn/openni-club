import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:fluwx/fluwx.dart';

/// Only public App ID and universal link belong in the client. App secret and
/// payment signing stay on the server. A fake gateway can be injected in tests.
abstract interface class WechatGateway {
  String? get unavailableReason;
  Future<String> authenticate();
  Future<void> pay(Map<String, dynamic> parameters);
}

class NativeWechatGateway implements WechatGateway {
  NativeWechatGateway({
    this.appId = const String.fromEnvironment('WECHAT_APP_ID'),
    this.universalLink = const String.fromEnvironment('WECHAT_UNIVERSAL_LINK'),
  });

  final String appId, universalLink;
  Fluwx? _sdk;
  bool _busy = false;

  @override
  String? get unavailableReason {
    if (kIsWeb ||
        ![
          TargetPlatform.iOS,
          TargetPlatform.android,
        ].contains(defaultTargetPlatform)) {
      return '微信登录与支付请在 iOS 或 Android App 内使用。';
    }
    if (!appId.startsWith('wx') || appId.length < 5) {
      return '俱乐部尚未配置微信 App ID，请联系运营方。';
    }
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        (!universalLink.startsWith('https://') ||
            !universalLink.endsWith('/'))) {
      return '俱乐部尚未配置 iOS 微信 Universal Link，请联系运营方。';
    }
    return null;
  }

  Future<Fluwx> _ready() async {
    if (unavailableReason case final String reason) throw Exception(reason);
    if (_sdk == null) {
      final sdk = Fluwx();
      final registered = await sdk.registerApi(
        appId: appId,
        universalLink: universalLink,
      );
      if (!registered) throw Exception('微信初始化失败，请联系运营方检查签名与 App ID。');
      _sdk = sdk;
    }
    if (!await _sdk!.isWeChatInstalled) throw Exception('请先安装微信，再重试。');
    return _sdk!;
  }

  Future<T> _request<T extends WeChatResponse>(
    Future<bool> Function(Fluwx sdk) launch,
  ) async {
    if (_busy) throw Exception('请先完成当前微信操作。');
    _busy = true;
    try {
      final sdk = await _ready();
      final response = Completer<T>();
      final subscription = sdk.addSubscriber((event) {
        if (event is T && !response.isCompleted) response.complete(event);
      });
      try {
        if (!await launch(sdk)) throw Exception('无法打开微信，请稍后重试。');
        final result = await response.future.timeout(
          const Duration(minutes: 3),
          onTimeout: () => throw Exception('微信操作超时。支付结果请在订单中刷新确认。'),
        );
        if (result.errCode == -2) throw Exception('已取消微信操作。');
        if (!result.isSuccessful) {
          throw Exception('微信操作未完成（${result.errCode}），请重试。');
        }
        return result;
      } finally {
        subscription.cancel();
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Future<String> authenticate() async {
    final state = List.generate(
      24,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final result = await _request<WeChatAuthResponse>(
      (sdk) => sdk.authBy(
        which: NormalAuth(scope: 'snsapi_userinfo', state: state),
      ),
    );
    if (result.state != state || result.code == null || result.code!.isEmpty) {
      throw Exception('微信登录响应校验失败，请重新登录。');
    }
    return result.code!;
  }

  @override
  Future<void> pay(Map<String, dynamic> p) async {
    // Reject wrong app / malformed server response before opening the wallet.
    if (p['appId'] != appId || p['package'] != 'Sign=WXPay') {
      throw Exception('支付配置不匹配，请联系俱乐部。');
    }
    for (final key in ['partnerId', 'prepayId', 'nonceStr', 'sign']) {
      if (p[key] is! String || (p[key] as String).isEmpty) {
        throw Exception('支付参数不完整，请重试。');
      }
    }
    final timestamp = int.tryParse('${p['timeStamp']}');
    if (timestamp == null || timestamp <= 0) throw Exception('支付时间戳无效。');
    await _request<WeChatPaymentResponse>(
      (sdk) => sdk.pay(
        which: Payment(
          appId: appId,
          partnerId: p['partnerId'],
          prepayId: p['prepayId'],
          packageValue: p['package'],
          nonceStr: p['nonceStr'],
          timestamp: timestamp,
          sign: p['sign'],
        ),
      ),
    );
    // SDK success is deliberately not treated as proof of payment.
  }
}
