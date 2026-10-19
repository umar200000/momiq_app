import 'package:flutter/material.dart';
import 'customer_widgets.dart';

List<CJson> customerSitterReviews(CustomerStore store, CJson sitter) {
  final samples = <CJson>[
    {
      'name': 'Madina Karimova',
      'stars': 5,
      'text': 'Mehribon va mas’uliyatli enaga. Parvarishdan mamnun qoldim.',
      'date': '2026-09-25',
    },
    {
      'name': 'Dilnoza Akbarova',
      'stars': 5,
      'text':
          'Ovqat va parvarish bo‘yicha ko‘rsatmalarimga amal qildi. Videolarni vaqtida yubordi.',
      'date': '2026-09-20',
    },
    {
      'name': 'Aziza Saidova',
      'stars': 4,
      'text':
          'Hammasi yaxshi o‘tdi. Savollarimga javob berdi, do‘stimni xotirjam qoldirdim.',
      'date': '2026-09-14',
    },
    {
      'name': 'Javohir Usmonov',
      'stars': 5,
      'text':
          'Kelishilgan vaqtda qabul qildi. Keyingi safar ham murojaat qilaman.',
      'date': '2026-09-08',
    },
  ];
  final own = store
      .list('bookings')
      .where(
        (b) =>
            b['sitter'] == sitter['id'] &&
            b['status'] == 'completed' &&
            b['review'] != null,
      )
      .map((b) {
        final review = b['review'] as Map;
        return <String, dynamic>{
          'name': '${store.profile['first']} ${store.profile['last']}',
          'stars': review['stars'],
          'text': review['text'],
          'date': review['date'] ?? b['to'],
          'own': true,
        };
      })
      .toList();
  final reviews = [...own, ...samples];
  reviews.sort(
    (a, b) => DateTime.parse(b['date']).compareTo(DateTime.parse(a['date'])),
  );
  return reviews;
}

String customerReviewSummary(CustomerStore store, CJson sitter) {
  final reviews = customerSitterReviews(store, sitter);
  final average =
      reviews.fold<double>(0, (sum, r) => sum + (r['stars'] as num)) /
      reviews.length;
  return '${average.toStringAsFixed(1)} (${reviews.length})';
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
  Widget build(BuildContext context) {
    final reviews = customerSitterReviews(store, sitter);
    void open() =>
        cPush(context, CustomerSitterReviewsPage(store: store, sitter: sitter));
    return cCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cText(
            lt('Mijozlar fikri', 'Customer reviews', 'Отзывы клиентов'),
            size: 19,
            bold: true,
          ),
          const SizedBox(height: 8),
          cRating(customerReviewSummary(store, sitter)),
          const SizedBox(height: 12),
          cText(reviews.first['name'], bold: true, size: 14),
          const SizedBox(height: 6),
          Text(
            reviews.first['text'],
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          cButton(
            lt(
              'Barcha sharhlar (${reviews.length})',
              'All reviews (${reviews.length})',
              'Все отзывы (${reviews.length})',
            ),
            open,
            secondary: true,
            id: 'viewSitterReviews',
          ),
        ],
      ),
      onTap: open,
    );
  }
}

class CustomerSitterReviewsPage extends StatelessWidget {
  const CustomerSitterReviewsPage({
    super.key,
    required this.store,
    required this.sitter,
  });
  final CustomerStore store;
  final CJson sitter;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final reviews = customerSitterReviews(store, sitter);
      return CustomerPage(
        title: lt('Mijozlar fikri', 'Customer reviews', 'Отзывы клиентов'),
        children: [
          cCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cText(sitter['name'], size: 22, bold: true),
                const SizedBox(height: 8),
                cRating(customerReviewSummary(store, sitter)),
                const SizedBox(height: 8),
                cText(
                  lt(
                    'Hozircha namuna sharhlar va shu qurilmada saqlangan fikrlar ko‘rsatilmoqda.',
                    'Showing sample reviews and feedback saved on this device.',
                    'Показаны примеры отзывов и отзывы, сохранённые на этом устройстве.',
                  ),
                  size: 12,
                ),
              ],
            ),
          ),
          for (var i = 0; i < reviews.length; i++)
            cCard(
              Column(
                key: ValueKey('sitterReview-$i'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: listingBorder,
                        child: Text(
                          (reviews[i]['name'] as String).substring(0, 1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            cText(reviews[i]['name'], bold: true),
                            if (reviews[i]['own'] == true)
                              cText(
                                lt(
                                  'Sizning sharhingiz',
                                  'Your review',
                                  'Ваш отзыв',
                                ),
                                size: 12,
                              ),
                            cText(shortDate(reviews[i]['date']), size: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Semantics(
                    label: '${reviews[i]['stars']} / 5',
                    child: Row(
                      children: [
                        for (var star = 1; star <= 5; star++)
                          Icon(
                            star <= reviews[i]['stars']
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 20,
                            color: listingGold,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if ((reviews[i]['text'] as String).isNotEmpty)
                    cText(reviews[i]['text']),
                ],
              ),
            ),
        ],
      );
    },
  );
}
