import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momiq_app/features/customer/data/customer_api.dart';
import 'package:momiq_app/features/profile/presentation/profile_export_tile.dart';

class ExportApi extends CustomerApi {
  ExportApi() : super('TEST token', 'owner');
  final response = Completer<Map<String, dynamic>>();
  final paths = <String>[];
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) {
    paths.add('$method $path');
    return response.future;
  }
}

void main() {
  for (final scenario in ['saved', 'cancelled', 'foreign', 'replaced']) {
    testWidgets('profile export $scenario', (t) async {
      final api = ExportApi(), files = <Map<String, dynamic>>[];
      final prior = CustomerApi.active;
      CustomerApi.active = api;
      addTearDown(() => CustomerApi.active = prior);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileExportTile(
              api: api,
              save: (name, bytes) async {
                expect(
                  name,
                  matches(r'^momiq-profile-[A-Za-z0-9_-]{32}\.json$'),
                );
                files.add(jsonDecode(utf8.decode(bytes)));
                return scenario == 'cancelled'
                    ? null
                    : Uri.file('/TEST/profile.json');
              },
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('saveProfileExport')));
      await t.pumpAndSettle();
      expect(api.paths, isEmpty);
      await t.tap(find.text('Joy tanlash'));
      await t.pumpAndSettle();
      expect(api.paths, ['GET /me/profile-export']);
      if (scenario == 'replaced') CustomerApi.active = ExportApi();
      api.response.complete({
        'format': 'momiq-profile-v1',
        'ownerId': scenario == 'foreign' ? 'other' : 'owner',
        'generatedAt': '2026-10-31T12:00:00Z',
        'profile': {'first': 'TEST', 'photo': 'PRIVATE'},
        'addresses': [
          {'label': 'Home', 'token': 'PRIVATE'},
        ],
        'pets': [
          {
            'name': 'Cat',
            'passport': 'PRIVATE',
            'notes': {'hidden': 'PRIVATE'},
          },
        ],
        'preferences': {
          'notifications': {'orders': true, 'extra': 'PRIVATE'},
        },
        'sitterProfile': {
          'homePhotos': ['PRIVATE'],
          'schedule': {
            'start': 540,
            'end': 1080,
            'timezone': 'Asia/Tashkent',
            'days': List.filled(7, true),
            'extra': 'PRIVATE',
          },
          'closedDates': [
            '2026-11-05',
            {'secret': 'PRIVATE'},
          ],
          'services': [
            {
              'type': 'boarding',
              'price': 500000,
              'capacity': 2,
              'active': true,
              'pets': [
                'cat',
                {'secret': 'PRIVATE'},
              ],
              'location': {'address': 'PRIVATE'},
              'internalNote': 'PRIVATE',
            },
          ],
        },
        'unexpectedSecret': 'TEST token',
      });
      await t.pumpAndSettle();
      if (scenario == 'saved' || scenario == 'cancelled') {
        expect(files.single['profile']['first'], 'TEST');
        expect(jsonEncode(files.single), isNot(contains('PRIVATE')));
        final sitter = files.single['sitterProfile'];
        expect(sitter['services'].single, {
          'type': 'boarding',
          'price': 500000,
          'capacity': 2,
          'active': true,
          'pets': ['cat'],
        });
        expect(sitter['closedDates'], ['2026-11-05']);
        expect(sitter['schedule']['days'], List.filled(7, true));
        expect(files.single.containsKey('unexpectedSecret'), false);
      } else {
        expect(files, isEmpty);
      }
      expect(
        find.text('Nusxa saqlandi'),
        scenario == 'saved' ? findsOneWidget : findsNothing,
      );
    });
  }
}
