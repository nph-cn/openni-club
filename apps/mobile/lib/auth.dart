import 'dart:async';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;

import 'discover.dart' show ServiceArt;
import 'loading.dart';
import 'repository.dart';
import 'ui.dart';

String safeReturnPath(String? value) {
  final uri = Uri.tryParse(value ?? '/');
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !uri.path.startsWith('/') ||
      uri.path.startsWith('//') ||
      uri.path.startsWith('/login')) {
    return '/';
  }
  return uri.toString();
}

Future<bool> requireClubLogin(BuildContext context, ClubRepository repo) async {
  if (!repo.isProduction || repo.token != null) return true;
  final next = GoRouterState.of(context).uri.toString();
  return await context.push<bool>('/login?next=${Uri.encodeComponent(next)}') ==
      true;
}

class AuthPage extends StatefulWidget {
  const AuthPage(
    this.repo, {
    super.key,
    this.kind = 'login',
    this.next = '/',
    this.previewError = false,
    this.previewSubmitting = false,
    this.verifyCode,
  });
  final ClubRepository repo;
  final String kind, next;
  final bool previewError, previewSubmitting;
  final Future<void> Function(String, String)? verifyCode;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final phone = TextEditingController(), code = TextEditingController();
  final codeFocus = FocusNode();
  late String step = widget.kind;
  bool accepted = false, loading = false, busy = false;
  Json? challenge;
  String? failure;
  String? errorCode;
  int resendSeconds = 0, requestEpoch = 0;
  Timer? timer;
  DateTime? retryAt;
  ClubRepository get repo => widget.repo;
  @override
  void initState() {
    super.initState();
    if (step != 'welcome') {
      loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) loadCapabilities();
      });
    }
  }

  Future<void> loadCapabilities() async {
    setState(() {
      loading = true;
      failure = null;
    });
    try {
      await repo.loadAuthCapabilities(force: true);
      if (widget.kind == 'code' && repo.isLocal && !repo.isProduction) {
        phone.text = '13800138000';
        accepted = true;
        challenge = await repo.requestSmsChallenge(phone.text);
        startCountdown(challenge!['retryAfterSeconds'] as int);
        if (widget.previewSubmitting) {
          code.text = '${challenge!['testCode']}';
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) verify();
          });
        }
        if (widget.previewError) {
          code.text = '000000';
          try {
            await repo.verifySms('${challenge!['challengeId']}', code.text);
          } catch (e) {
            setFailure(e);
          }
        }
      } else if (step == 'code' && challenge == null) {
        step = 'phone';
      }
    } catch (e) {
      setFailure(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void startCountdown(int seconds) {
    timer?.cancel();
    retryAt = repo.now.add(Duration(seconds: seconds));
    resendSeconds = seconds;
    if (seconds <= 0) return;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = retryAt!.difference(repo.now).inMilliseconds;
      setState(
        () => resendSeconds = remaining <= 0 ? 0 : (remaining / 1000).ceil(),
      );
      if (resendSeconds == 0) timer?.cancel();
    });
  }

  void setFailure(Object error) {
    failure = '$error'.replaceFirst('Exception: ', '');
    if (error is ClubApiException) {
      errorCode = error.code;
      if (['SMS_NOT_CONFIGURED', 'CLUB_NOT_READY'].contains(error.code)) {
        failure = '手机登录暂不可用，请稍后重试';
      }
      if (error.retryAfterSeconds != null) {
        startCountdown(error.retryAfterSeconds!);
      }
      if (error.attemptsRemaining != null && error.attemptsRemaining! > 0) {
        failure = '${error.message}，还可尝试 ${error.attemptsRemaining} 次';
      }
    }
  }

  Future<void> sendCode() async {
    if (busy || resendSeconds > 0) return;
    if (loading || repo.authCapabilities?['sms']?['enabled'] != true) {
      setState(() => failure = '手机登录尚未开通');
      return;
    }
    if (!accepted) {
      setState(() => failure = '请先同意服务协议与隐私政策');
      return;
    }
    if (!RegExp(r'^1[3-9][0-9]{9}$').hasMatch(phone.text)) {
      setState(() => failure = '请输入正确的手机号');
      return;
    }
    final epoch = ++requestEpoch;
    setState(() {
      busy = true;
      failure = null;
      errorCode = null;
    });
    try {
      final result = await repo.requestSmsChallenge(phone.text);
      if (!mounted || epoch != requestEpoch) return;
      FocusScope.of(context).unfocus();
      setState(() {
        challenge = result;
        step = 'code';
        code.clear();
      });
      startCountdown(result['retryAfterSeconds'] as int? ?? 60);
    } catch (e) {
      if (mounted && epoch == requestEpoch) setState(() => setFailure(e));
    } finally {
      if (mounted && epoch == requestEpoch) setState(() => busy = false);
    }
  }

  Future<void> verify() async {
    if (busy || challenge == null) return;
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code.text)) {
      setState(() => failure = '请输入 6 位验证码');
      return;
    }
    final epoch = ++requestEpoch;
    setState(() {
      busy = true;
      failure = null;
      errorCode = null;
    });
    try {
      await (widget.verifyCode ?? repo.verifySms)(
        '${challenge!['challengeId']}',
        code.text,
      );
      if (mounted && epoch == requestEpoch && step == 'code') finish();
    } catch (e) {
      if (mounted && epoch == requestEpoch) setState(() => setFailure(e));
    } finally {
      if (mounted && epoch == requestEpoch) setState(() => busy = false);
    }
  }

  void backStep() {
    requestEpoch++;
    setState(() {
      step = step == 'code' ? 'phone' : 'login';
      busy = false;
      failure = null;
    });
  }

  void finish() {
    TextInput.finishAutofillContext();
    FocusScope.of(context).unfocus();
    final target = safeReturnPath(widget.next);
    if (context.canPop()) {
      context.pop(true);
    } else {
      context.go(target);
    }
  }

  Future<void> wechat() async {
    if (!accepted) {
      setState(() => failure = '请先同意服务协议与隐私政策');
      return;
    }
    final epoch = ++requestEpoch;
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      await repo.signInWithWechat();
      if (mounted && epoch == requestEpoch) finish();
    } catch (e) {
      if (mounted && epoch == requestEpoch) setState(() => setFailure(e));
    } finally {
      if (mounted && epoch == requestEpoch) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    phone.dispose();
    code.dispose();
    codeFocus.dispose();
    super.dispose();
  }

  Widget policies() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 38,
            height: 40,
            child: Checkbox(
              value: accepted,
              visualDensity: VisualDensity.compact,
              onChanged: busy
                  ? null
                  : (v) => setState(() => accepted = v ?? false),
            ),
          ),
          const Expanded(
            child: Text(
              '同意服务协议与隐私政策',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(left: 30),
        child: Wrap(
          children: [
            TextButton(
              onPressed: () => context.push('/legal/terms'),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: const Text('服务协议'),
            ),
            TextButton(
              onPressed: () => context.push('/legal/privacy'),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: const Text('隐私政策'),
            ),
          ],
        ),
      ),
    ],
  );
  Widget errorMessage() => failure == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFBEDEB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 15,
                    color: danger,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      failure!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: danger,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
  Widget action(String title, VoidCallback? onPressed) => SizedBox(
    width: double.infinity,
    height: 46,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      style: busy
          ? FilledButton.styleFrom(
              disabledBackgroundColor: brandColor(repo),
              disabledForegroundColor: onBrand(repo),
            )
          : null,
      child: busy
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 15,
                  height: 15,
                  child:
                      MediaQuery.of(context).reduceMotion ||
                          MediaQuery.of(context).disableAnimations
                      ? const Icon(Icons.hourglass_bottom_rounded, size: 15)
                      : const CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                const Text('处理中…'),
              ],
            )
          : Text(title),
    ),
  );

  Widget _authIntro({
    required IconData icon,
    required String title,
    required String subtitle,
  }) => Row(
    children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: rule, width: .6),
        ),
        child: Icon(icon, size: 20, color: ink),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: typeTitle),
            const SizedBox(height: 2),
            Text(subtitle, style: typeSecondary),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (step == 'welcome') return welcome();
    final sms = repo.authCapabilities?['sms'] as Map?;
    final smsEnabled = sms?['enabled'] == true;
    final isCode = step == 'code';
    return PopScope(
      canPop: step == 'login',
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) backStep();
      },
      child: ClubPage(
        repo: repo,
        title: '',
        onBack: step == 'login' ? null : backStep,
        child: AnimatedSwitcher(
          duration:
              MediaQuery.of(context).reduceMotion ||
                  MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: PageList(
            key: ValueKey(step),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
            children: [
              if (step == 'login') ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: BrandMark(repo, size: 48),
                ),
                const SizedBox(height: 14),
                Text(
                  '登录${repo.clubName}',
                  style: typePage,
                ),
                const SizedBox(height: 4),
                const Text(
                  '示例账号可浏览聊天、预约与成员演示流程。',
                  style: typeSecondary,
                ),
                const SizedBox(height: 24),
                if (loading)
                  const SkeletonPulse(
                    child: Column(
                      children: [
                        SkeletonBlock(height: 46),
                        SizedBox(height: 10),
                        SkeletonBlock(height: 46),
                      ],
                    ),
                  )
                else ...[
                  if (repo.wechatUnavailable == null) ...[
                    action('微信登录', wechat),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: smsEnabled
                            ? () => setState(() {
                                step = 'phone';
                                failure = null;
                              })
                            : null,
                        icon: const Icon(Icons.phone_iphone_rounded, size: 18),
                        label: Text(smsEnabled ? '手机号登录' : '手机号登录暂不可用'),
                      ),
                    ),
                  ] else ...[
                    action(
                      smsEnabled ? '手机号登录' : '手机号登录暂不可用',
                      smsEnabled
                          ? () => setState(() {
                              step = 'phone';
                              failure = null;
                            })
                          : null,
                    ),
                    const SizedBox(height: 10),
                    const SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: null,
                        child: Text('微信登录暂不可用'),
                      ),
                    ),
                  ],
                ],
                errorMessage(),
                if (!loading && repo.authCapabilities == null)
                  TextButton(
                    onPressed: loadCapabilities,
                    child: const Text('重新加载登录方式'),
                  ),
                const SizedBox(height: 18),
                policies(),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/'),
                    child: const Text('先浏览服务'),
                  ),
                ),
                const SizedBox(height: 4),
                const Center(
                  child: Text(
                    '本地演示不会发送短信或发起微信授权',
                    style: TextStyle(fontSize: 11, color: faint),
                  ),
                ),
              ] else if (!isCode) ...[
                _authIntro(
                  icon: Icons.phone_iphone_rounded,
                  title: '手机号登录',
                  subtitle: '首次验证后自动创建账号',
                ),
                const SizedBox(height: 22),
                AutofillGroup(
                  child: TextField(
                    controller: phone,
                    autofocus: false,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [
                      AutofillHints.telephoneNumberNational,
                    ],
                    inputFormatters: [
                      TextInputFormatter.withFunction((old, value) {
                        var digits = value.text.replaceAll(
                          RegExp(r'[^0-9]'),
                          '',
                        );
                        if (digits.startsWith('86') && digits.length == 13) {
                          digits = digits.substring(2);
                        }
                        if (digits.length > 11) {
                          digits = digits.substring(0, 11);
                        }
                        return TextEditingValue(
                          text: digits,
                          selection: TextSelection.collapsed(
                            offset: digits.length,
                          ),
                        );
                      }),
                    ],
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1,
                    ),
                    decoration: const InputDecoration(
                      prefixText: '+86  ',
                      hintText: '请输入手机号',
                      hintStyle: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                      labelText: '手机号',
                    ),
                    onChanged: (_) => setState(() => failure = null),
                    onSubmitted: (_) => sendCode(),
                  ),
                ),
                errorMessage(),
                const SizedBox(height: 18),
                action(
                  resendSeconds > 0 ? '${resendSeconds}s 后重新获取' : '获取验证码',
                  !loading && smsEnabled && resendSeconds == 0
                      ? sendCode
                      : null,
                ),
                if (!loading && !smsEnabled)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      '手机登录尚未开通，请选择其他方式',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 14),
                policies(),
              ] else ...[
                _authIntro(
                  icon: Icons.shield_outlined,
                  title: '输入验证码',
                  subtitle: '${challenge?['phoneMasked'] ?? ''}',
                ),
                const SizedBox(height: 22),
                if (loading)
                  const SkeletonPulse(child: SkeletonBlock(height: 60))
                else
                  AutofillGroup(
                    child: TextField(
                      controller: code,
                      focusNode: codeFocus,
                      autofocus: false,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 12,
                      ),
                      decoration: InputDecoration(
                        labelText: '6 位验证码',
                        hintText: '000000',
                        hintStyle: const TextStyle(
                          fontSize: 24,
                          letterSpacing: 12,
                          color: faint,
                        ),
                        errorText: null,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(13),
                          borderSide: BorderSide(
                            color: failure == null ? rule : danger,
                          ),
                        ),
                      ),
                      onChanged: (_) => setState(() {
                        failure = null;
                        errorCode = null;
                      }),
                      onSubmitted: (_) => verify(),
                    ),
                  ),
                errorMessage(),
                const SizedBox(height: 18),
                action('验证并登录', !loading ? verify : null),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: busy || resendSeconds > 0 ? null : sendCode,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: Text(
                      resendSeconds > 0 ? '${resendSeconds}s 后重新获取' : '重新获取验证码',
                    ),
                  ),
                ),
                if (challenge?['delivery'] == 'test')
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: sage,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.info_circle,
                          size: 14,
                          color: muted,
                        ),
                        const SizedBox(width: 7),
                        const Expanded(
                          child: Text(
                            '本地验证码，未发送短信',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ),
                        SelectableText(
                          '${challenge?['testCode'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  '验证码仅用于本次演示登录；不会创建真实账号。',
                  style: TextStyle(fontSize: 11, color: faint, height: 1.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget welcome() {
    final service = repo.services.firstOrNull;
    return ClubPage(
      repo: repo,
      appBar: false,
      child: PageList(
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * .46,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (service != null)
                  ServiceArt(service, radius: 0)
                else
                  const ColoredBox(color: ink),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x660B0F14),
                        Color(0x330B0F14),
                        Color(0xF2F4F5F7),
                      ],
                      stops: [0, .55, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  top: 14,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(5, 5, 10, 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .86),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        BrandMark(repo, size: 30),
                        const SizedBox(width: 7),
                        Text(
                          repo.shortName,
                          style: typeLabel.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(repo.clubName, style: typePage.copyWith(fontSize: 26)),
                const SizedBox(height: 4),
                Text(
                  '${repo.club['tagline'] ?? '游戏陪练预约'}',
                  style: typeSecondary,
                ),
                const SizedBox(height: 16),
                for (final feature in const [
                  (Icons.sports_esports_outlined, '官方目录', '按游戏、服务和规格选择'),
                  (Icons.event_available_outlined, '预约时段', '查看队友排班并提交预约'),
                  (Icons.assignment_turned_in_outlined, '履约进度', '订单、交付记录与评价'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: rule, width: .6),
                          ),
                          child: Icon(feature.$1, size: 15, color: ink),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Row(
                            children: [
                              Text(
                                feature.$2,
                                style: typeLabel.copyWith(fontSize: 12.5),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  feature.$3,
                                  style: typeCaption,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                action('登录 / 注册', () async {
                  final next = safeReturnPath(widget.next);
                  final signedIn = await context.push<bool>(
                    '/login?next=${Uri.encodeComponent(next)}',
                  );
                  if (signedIn == true && mounted) {
                    context.go(next);
                  }
                }),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => context.go(safeReturnPath(widget.next)),
                    child: const Text('先浏览服务', style: TextStyle(fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    '${repo.club['notice'] ?? '虚构演示俱乐部'}',
                    textAlign: TextAlign.center,
                    style: typeCaption.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
