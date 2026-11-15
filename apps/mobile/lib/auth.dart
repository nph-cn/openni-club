import 'dart:async';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

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
            width: 42,
            height: 48,
            child: Checkbox(
              value: accepted,
              onChanged: busy
                  ? null
                  : (v) => setState(() => accepted = v ?? false),
            ),
          ),
          const Expanded(
            child: Text(
              '同意服务协议与隐私政策',
              style: TextStyle(fontSize: 14, color: muted),
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(left: 36),
        child: Wrap(
          children: [
            TextButton(
              onPressed: () => context.push('/legal/terms'),
              child: const Text('服务协议'),
            ),
            TextButton(
              onPressed: () => context.push('/legal/privacy'),
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
          padding: const EdgeInsets.only(top: 16),
          child: Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 19,
                  color: Color(0xFFAA3532),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    failure!,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFFAA3532),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
  Widget action(String title, VoidCallback? onPressed) => SizedBox(
    width: double.infinity,
    height: 54,
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
                  width: 18,
                  height: 18,
                  child:
                      MediaQuery.of(context).reduceMotion ||
                          MediaQuery.of(context).disableAnimations
                      ? const Icon(Icons.hourglass_bottom_rounded, size: 18)
                      : const CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                const Text('处理中…'),
              ],
            )
          : Text(title),
    ),
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
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
            children: [
              if (step == 'login') ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: BrandMark(repo, size: 58),
                ),
                const SizedBox(height: 26),
                Text(
                  '登录${repo.clubName}',
                  style: const TextStyle(
                    fontSize: 29,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 40),
                if (loading)
                  const SkeletonPulse(
                    child: Column(
                      children: [
                        SkeletonBlock(height: 54),
                        SizedBox(height: 14),
                        SkeletonBlock(height: 54),
                      ],
                    ),
                  )
                else ...[
                  if (repo.wechatUnavailable == null) ...[
                    action('微信登录', wechat),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 54,
                      child: OutlinedButton.icon(
                        onPressed: smsEnabled
                            ? () => setState(() {
                                step = 'phone';
                                failure = null;
                              })
                            : null,
                        icon: const Icon(Icons.phone_iphone_rounded, size: 21),
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
                    const SizedBox(height: 14),
                    const SizedBox(
                      height: 54,
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
                const SizedBox(height: 28),
                policies(),
                const SizedBox(height: 36),
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/'),
                    child: const Text('先浏览服务'),
                  ),
                ),
              ] else if (!isCode) ...[
                const Text(
                  '手机号登录',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text(
                  '首次验证后自动创建账号',
                  style: TextStyle(fontSize: 15, color: muted),
                ),
                const SizedBox(height: 32),
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
                      fontSize: 23,
                      fontWeight: FontWeight.w500,
                      letterSpacing: .4,
                    ),
                    decoration: const InputDecoration(
                      prefixText: '+86  ',
                      hintText: '请输入手机号',
                      hintStyle: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                      ),
                      labelText: '手机号',
                    ),
                    onChanged: (_) => setState(() => failure = null),
                    onSubmitted: (_) => sendCode(),
                  ),
                ),
                errorMessage(),
                const SizedBox(height: 24),
                action(
                  resendSeconds > 0 ? '${resendSeconds}s 后重新获取' : '获取验证码',
                  !loading && smsEnabled && resendSeconds == 0
                      ? sendCode
                      : null,
                ),
                if (!loading && !smsEnabled)
                  const Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: Text(
                      '手机登录尚未开通，请选择其他方式',
                      style: TextStyle(color: muted, fontSize: 14),
                    ),
                  ),
                const SizedBox(height: 20),
                policies(),
              ] else ...[
                const Text(
                  '输入验证码',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  '${challenge?['phoneMasked'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 18,
                    color: muted,
                    letterSpacing: .6,
                  ),
                ),
                const SizedBox(height: 32),
                if (loading)
                  const SkeletonPulse(child: SkeletonBlock(height: 68))
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
                        fontSize: 30,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 18,
                      ),
                      decoration: InputDecoration(
                        labelText: '6 位验证码',
                        hintText: '000000',
                        hintStyle: const TextStyle(
                          fontSize: 30,
                          letterSpacing: 18,
                          color: muted,
                        ),
                        errorText: null,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: failure == null
                                ? rule
                                : const Color(0xFFAA3532),
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
                const SizedBox(height: 24),
                action('验证并登录', !loading ? verify : null),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: busy || resendSeconds > 0 ? null : sendCode,
                    child: Text(
                      resendSeconds > 0 ? '${resendSeconds}s 后重新获取' : '重新获取验证码',
                    ),
                  ),
                ),
                if (challenge?['delivery'] == 'test')
                  Container(
                    margin: const EdgeInsets.only(top: 22),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: sage,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '本地验证码，未发送短信',
                          style: TextStyle(fontSize: 14, color: muted),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          '${challenge?['testCode'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 3,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget welcome() => ClubPage(
    repo: repo,
    appBar: false,
    child: PageList(
      padding: EdgeInsets.zero,
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * .51,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (repo.services.isNotEmpty)
                ServiceArt(repo.services.first, radius: 0),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, canvas],
                  ),
                ),
              ),
              Positioned(
                left: 24,
                top: 22,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .88),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: BrandMark(repo, size: 42),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                repo.clubName,
                style: const TextStyle(
                  fontSize: 33,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '游戏陪练预约',
                style: TextStyle(fontSize: 20, color: muted),
              ),
              const SizedBox(height: 42),
              action('登录 / 注册', () async {
                final next = safeReturnPath(widget.next);
                final signedIn = await context.push<bool>(
                  '/login?next=${Uri.encodeComponent(next)}',
                );
                if (signedIn == true && mounted) {
                  context.go(next);
                }
              }),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  onPressed: () => context.go(safeReturnPath(widget.next)),
                  child: const Text('先浏览服务', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
