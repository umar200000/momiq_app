import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../customer/data/customer_api.dart';
import '../../customer/presentation/customer_home_page.dart';
import '../../customer/presentation/customer_registration_page.dart';
import '../../home/presentation/pages/sitter_home_page.dart';
import '../../onboarding/presentation/pages/sitter_registration_page.dart';
import '../../role_selection/presentation/pages/role_selection_page.dart';
import '../../listings/presentation/listing_style.dart' show lt;

Widget accountDestination(
  Map<String, dynamic> account, {
  required bool customer,
}) {
  if (!CustomerApi.hasProfile(account, customer: customer)) {
    return customer
        ? const CustomerRegistrationPage()
        : const SitterRegistrationPage();
  }
  if (customer) return const CustomerHomePage();
  final profile = account['profile'] as Map;
  return SitterHomePage(
    firstName: profile['first'],
    lastName: profile['last'],
    avatar: profile['photo'] is String ? base64Decode(profile['photo']) : null,
  );
}

Future<Widget> restoreDestination() async {
  CustomerApi? api;
  try {
    api = await CustomerApi.restore();
  } on SessionEnvironmentMismatch {
    return const SessionRecoveryPage(environmentMismatch: true);
  } catch (_) {
    // A temporarily locked/unavailable vault must not strand the splash or erase data.
    return const SessionRecoveryPage(environmentMismatch: false);
  }
  if (api == null) return const RoleSelectionPage();
  final version = CustomerApi.sessionVersion;
  bool current() =>
      identical(CustomerApi.active, api) &&
      version == CustomerApi.sessionVersion;
  const retry = SessionRecoveryPage(environmentMismatch: false);
  final customer = await CustomerApi.customerRole();
  if (!current()) return retry;
  try {
    final response = await api.request('GET', '/me');
    if (!current()) return retry;
    final account = Map<String, dynamic>.from(response['account']);
    await CustomerApi.rememberAccount(account, isCurrent: current);
    if (!current()) return retry;
    return accountDestination(account, customer: customer);
  } on CustomerApiException catch (e) {
    if (!current()) return retry;
    if (e.status == 401 || e.status == 403) {
      await CustomerApi.clearLocal();
      return const RoleSelectionPage();
    }
    // A network problem must not erase a valid saved login.
  } catch (_) {
    // TLS/transport failures also keep the cached session.
  }
  if (!current()) return retry;
  final raw = (await SharedPreferences.getInstance()).getString(
    'momiq.api.account',
  );
  if (!current()) return retry;
  if (raw != null) {
    try {
      return accountDestination(
        Map<String, dynamic>.from(jsonDecode(raw)),
        customer: customer,
      );
    } catch (_) {
      /* A damaged cache is not proof of an incomplete profile. */
    }
  }
  return customer ? const CustomerHomePage() : const SitterHomePage();
}

class SessionRecoveryPage extends StatefulWidget {
  const SessionRecoveryPage({super.key, required this.environmentMismatch});
  final bool environmentMismatch;
  @override
  State<SessionRecoveryPage> createState() => _SessionRecoveryPageState();
}

class _SessionRecoveryPageState extends State<SessionRecoveryPage> {
  bool _busy = false;
  String? _error;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final destination = await restoreDestination();
      if (!mounted) return;
      await Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute<void>(builder: (_) => destination));
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = lt(
            'Sessiya ochilmadi. Qayta urining.',
            'Could not open session. Retry.',
            'Не удалось открыть сессию. Повторите.',
          );
        });
      }
    }
  }

  Future<void> _clear() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          lt(
            'Mahalliy ma’lumotlar o‘chirilsinmi?',
            'Delete local data?',
            'Удалить локальные данные?',
          ),
        ),
        content: Text(
          lt(
            'Ushbu qurilmadagi sessiya va yuborilmagan chek, xabar, bron hamda video qoralamalari o‘chadi. Serverdagi hisob, buyurtmalar va balans saqlanadi.',
            'The session and unsent receipt, message, booking and video drafts on this device will be deleted. Your server account, bookings and balance remain.',
            'Сессия и неотправленные черновики чеков, сообщений, заказов и видео на этом устройстве будут удалены. Аккаунт, заказы и баланс на сервере сохранятся.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(lt('Bekor qilish', 'Cancel', 'Отмена')),
          ),
          TextButton(
            key: const ValueKey('confirmClearSession'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              lt(
                'O‘chirish va qayta kirish',
                'Delete and sign in',
                'Удалить и войти',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await CustomerApi.clearLocal();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const RoleSelectionPage()),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = lt(
            'Tozalash tugamadi. Qayta urining.',
            'Cleanup did not finish. Retry.',
            'Очистка не завершена. Повторите.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        lt('Saqlangan sessiya', 'Saved session', 'Сохранённая сессия'),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          widget.environmentMismatch
              ? lt(
                  'Bu ilova versiyasi saqlangan sessiya muhitiga mos emas. Avval ishlatilgan muhitga mos versiyani oching. Sessiya va qoralamalar saqlab qolindi; boshqa serverga yuborilmadi.',
                  'This build does not match your saved session environment. Open the build for the environment you used before. Your session and drafts have been preserved and were not sent to another server.',
                  'Эта сборка не соответствует среде сохранённой сессии. Откройте сборку для прежней среды. Сессия и черновики сохранены и не отправлены на другой сервер.',
                )
              : lt(
                  'Saqlangan sessiya ochilmadi. Qurilmani qulfdan chiqarib, qayta urining. Qoralamalarni tozalash so‘ralmadi.',
                  'Could not open the saved session. Unlock the device and retry. Draft cleanup was not requested.',
                  'Не удалось открыть сохранённую сессию. Разблокируйте устройство и повторите. Очистка черновиков не запрашивалась.',
                ),
        ),
        if (_error != null) Text(_error!),
        FilledButton(
          onPressed: _busy ? null : _retry,
          child: Text(lt('Qayta urinish', 'Retry', 'Повторить')),
        ),
        TextButton(
          key: const ValueKey('clearSavedSession'),
          onPressed: _busy ? null : _clear,
          child: Text(
            lt(
              'Mahalliy sessiyani tozalash',
              'Clear local session',
              'Очистить локальную сессию',
            ),
          ),
        ),
      ],
    ),
  );
}
