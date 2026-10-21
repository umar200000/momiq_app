import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momiq_app/features/customer/data/customer_store.dart';
void main() {
  test('fresh account has no invented profile, orders, pets or messages', () async {
    SharedPreferences.setMockInitialValues({});
    final store = CustomerStore(petSession: CustomerPetSession());
    await store.load(); addTearDown(store.dispose);
    expect(store.profile['first'], isEmpty);
    for (final key in ['pets','bookings','messages','addresses','support']) { expect(store.list(key), isEmpty); }
    await expectLater(store.send('missing','Hello'), throwsStateError);
    expect(store.list('messages'), isEmpty);
  });
  test('legacy demo orders disappear while user profile and addresses survive', () async {
    SharedPreferences.setMockInitialValues({CustomerStore.storageKey: jsonEncode({
      'profile': {'first':'Actual','last':'Person','photo':null},
      'bookings':[{'id':'MQ-DEMO-01','sample':true}], 'messages':[{'id':'welcome'}],
      'favorites':['hoji'], 'pets':[], 'addresses':[{'id':'actual-address'}],
      'notifications':{'chat':true},'support':[],
    })});
    final store = CustomerStore(); await store.load(); addTearDown(store.dispose);
    expect(store.profile['first'],'Actual');
    expect(store.list('addresses').single['id'],'actual-address');
    expect(store.list('bookings'),isEmpty); expect(store.list('messages'),isEmpty); expect(store.favorites,isEmpty);
  });
}
