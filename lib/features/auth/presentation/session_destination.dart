import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../customer/data/customer_api.dart';
import '../../customer/presentation/customer_home_page.dart';
import '../../customer/presentation/customer_registration_page.dart';
import '../../home/presentation/pages/sitter_home_page.dart';
import '../../onboarding/presentation/pages/sitter_registration_page.dart';
import '../../role_selection/presentation/pages/role_selection_page.dart';

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
  final api = await CustomerApi.restore();
  if (api == null) return const RoleSelectionPage();
  final customer = await CustomerApi.customerRole();
  try {
    final response = await api.request('GET', '/me');
    final account = Map<String, dynamic>.from(response['account']);
    await CustomerApi.rememberAccount(account);
    return accountDestination(account, customer: customer);
  } on CustomerApiException catch (e) {
    if (e.status == 401 || e.status == 403) {
      await CustomerApi.clearLocal();
      return const RoleSelectionPage();
    }
    // A network problem must not erase a valid saved login.
  } catch (_) {
    // TLS/transport failures also keep the cached session.
  }
  final raw = (await SharedPreferences.getInstance()).getString(
    'momiq.api.account',
  );
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
