import 'package:flutter/material.dart';
import '../data/customer_api.dart';
import 'customer_widgets.dart';
import '../../support/support_page.dart';

/// Only the server's published, non-TEST aggregate counts toward reputation.
String customerReviewSummary(CustomerStore store, CJson sitter) {
  final count = sitter['reviews'];
  final rating = sitter['rating'];
  if (count is! int || count <= 0 || rating is! num) {
    return lt('Hali sharh yo‘q', 'No reviews yet', 'Отзывов пока нет');
  }
  return '${rating.toStringAsFixed(1)} ($count)';
}

class CustomerReviewsSection extends StatelessWidget {
  const CustomerReviewsSection({
    super.key,
    required this.store,
    required this.sitter,
  });
  final CustomerStore store;
  final CJson sitter;
  @override
  Widget build(BuildContext context) => cCard(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cText(
          lt('Mijozlar fikri', 'Customer reviews', 'Отзывы клиентов'),
          size: 19,
          bold: true,
        ),
        cRating(customerReviewSummary(store, sitter)),
        cButton(
          lt('Sharhlarni ko‘rish', 'View reviews', 'Посмотреть отзывы'),
          () => cPush(
            context,
            CustomerSitterReviewsPage(store: store, sitter: sitter),
          ),
          secondary: true,
          id: 'viewSitterReviews',
        ),
      ],
    ),
  );
}

class CustomerSitterReviewsPage extends StatefulWidget {
  const CustomerSitterReviewsPage({
    super.key,
    required this.store,
    required this.sitter,
    this.api,
  });
  final CustomerStore store;
  final CJson sitter;
  final CustomerApi? api;
  @override
  State<CustomerSitterReviewsPage> createState() =>
      _CustomerSitterReviewsPageState();
}

class _CustomerSitterReviewsPageState extends State<CustomerSitterReviewsPage> {
  late final api = widget.api ?? CustomerApi.active ?? CustomerApi('', '');
  final items = <CJson>[];
  bool busy = false, loaded = false, failed = false;
  String? cursor;
  int count = 0;
  num rating = 0;
  final session = CustomerApi.sessionVersion;
  bool get live => mounted && session == CustomerApi.sessionVersion;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false}) async {
    if (!live || busy || (more && cursor == null)) return;
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      final result = await api.request(
        'GET',
        '/sitters/${Uri.encodeComponent(widget.sitter['id'])}/reviews${more ? '?before=$cursor' : ''}',
      );
      if (!live) return;
      setState(() {
        if (!more) items.clear();
        final ids = items.map((r) => r['id']).toSet();
        items.addAll(
          (result['items'] as List)
              .map((r) => CJson.from(r))
              .where((r) => ids.add(r['id'])),
        );
        cursor = result['nextCursor'];
        count = result['count'];
        rating = result['rating'];
        loaded = true;
      });
    } catch (_) {
      if (live) setState(() => failed = true);
    } finally {
      if (live) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(lt('Mijozlar fikri', 'Customer reviews', 'Отзывы клиентов')),
      actions: [
        IconButton(
          tooltip: lt('Yangilash', 'Refresh', 'Обновить'),
          onPressed: busy ? null : () => load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          widget.sitter['name'],
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (busy) const LinearProgressIndicator(),
        if (failed)
          Text(
            lt(
              'Sharhlar yuklanmadi. Qayta urinib ko‘ring.',
              'Could not load reviews. Retry.',
              'Не удалось загрузить отзывы. Повторите.',
            ),
            key: const ValueKey('reviewLoadError'),
          ),
        if (loaded)
          Text(
            count == 0
                ? lt(
                    'Haqiqiy sharhlar hali yo‘q.',
                    'No genuine reviews yet.',
                    'Настоящих отзывов пока нет.',
                  )
                : '${rating.toStringAsFixed(1)} ($count)',
          ),
        if (loaded && items.isEmpty && !failed)
          Text(lt('Hali sharh yo‘q', 'No reviews yet', 'Отзывов пока нет')),
        for (final review in items)
          Card(
            key: ValueKey('serverReview-${review['id']}'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    review['name'],
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${review['stars']} / 5 · ${shortDate(review['created'])}',
                  ),
                  if (review['testOnly'] == true)
                    Text(
                      lt(
                        'TEST — reytingga qo‘shilmaydi',
                        'TEST — excluded from ratings',
                        'TEST — не учитывается в рейтинге',
                      ),
                    ),
                  if ((review['text'] as String).isNotEmpty)
                    Text(review['text']),
                  PublicContentReportButton(
                    api: api,
                    target: {'kind': 'review', 'id': review['id']},
                  ),
                ],
              ),
            ),
          ),
        if (cursor != null)
          TextButton(
            onPressed: busy ? null : () => load(more: true),
            child: Text(lt('Yana', 'More', 'Ещё')),
          ),
      ],
    ),
  );
}
