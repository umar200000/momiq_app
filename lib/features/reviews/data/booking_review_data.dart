typedef ReviewData = Map<String, dynamic>;
bool _number(Object? v) =>
    v is String && RegExp(r'^[1-9][0-9]{0,17}$').hasMatch(v);
bool _text(Object? v, int max) => v is String && v.runes.length <= max;
bool _time(Object? v) =>
    v is String && v.length <= 64 && DateTime.tryParse(v) != null;
Never _bad() => throw const FormatException('Invalid booking review response');

ReviewData bookingReviewData(
  ReviewData value,
  String bookingId, {
  ReviewData? request,
}) {
  if (value['bookingId'] != bookingId ||
      value['canEdit'] != false ||
      value['reviewEditable'] != false ||
      [
        'canCreate',
        'canWithdraw',
        'canRestore',
      ].any((key) => value[key] is! bool)) {
    _bad();
  }
  final review = value['review'];
  if (review != null &&
      (review is! Map ||
          !_number(review['id']) ||
          !_text(review['name'], 201) ||
          !_text(review['text'], 2000) ||
          review['stars'] is! int ||
          review['stars'] < 1 ||
          review['stars'] > 5 ||
          review['revision'] is! int ||
          review['revision'] < 1 ||
          [
            'hidden',
            'withdrawn',
            'testOnly',
          ].any((key) => review[key] is! bool) ||
          !_time(review['created']) ||
          !_time(review['updated']))) {
    _bad();
  }
  if ((value['canCreate'] == true && review != null) ||
      ((value['canWithdraw'] == true || value['canRestore'] == true) &&
          review == null) ||
      (value['canWithdraw'] == true && value['canRestore'] == true)) {
    _bad();
  }
  final decision = value['moderation'], target = value['appealTarget'];
  if (decision != null &&
      (decision is! Map ||
          review == null ||
          review['hidden'] != true ||
          !_text(decision['reason'], 500) ||
          !_time(decision['decidedAt']) ||
          decision['revision'] is! int ||
          decision['revision'] < 1 ||
          decision['revision'] > review['revision'])) {
    _bad();
  }
  if (target != null &&
      (target is! Map ||
          decision == null ||
          target['kind'] != 'review' ||
          target['purpose'] != 'appeal' ||
          target['id'] != review['id'] ||
          target['revision'] != '${review['revision']}')) {
    _bad();
  }
  if (request != null) {
    final receipt = value['acknowledgement'];
    if (review == null ||
        receipt is! Map ||
        receipt['requestId'] != request['requestId'] ||
        receipt['reviewId'] != review['id'] ||
        receipt['action'] != request['action'] ||
        receipt['revision'] is! int ||
        receipt['revision'] != request['revision'] + 1 ||
        receipt['revision'] > review['revision'] ||
        review['stars'] != request['stars'] ||
        review['text'] != (request['text'] as String).trim()) {
      _bad();
    }
    // Exact retries may return a newer visibility decision with the original receipt.
    if (receipt['revision'] == review['revision'] &&
        review['withdrawn'] != (request['action'] == 'withdraw')) {
      _bad();
    }
  }
  return {
    ...value,
    if (review != null) 'review': ReviewData.from(review),
    if (decision != null) 'moderation': ReviewData.from(decision),
    if (target != null) 'appealTarget': Map<String, String>.from(target),
  };
}

ReviewData? bookingReviewDraft(ReviewData? value) {
  if (value == null) return null;
  if (value.length != 5 ||
      !value.keys.toSet().containsAll([
        'stars',
        'text',
        'revision',
        'action',
        'requestId',
      ]) ||
      value['stars'] is! int ||
      value['stars'] < 1 ||
      value['stars'] > 5 ||
      !_text(value['text'], 2000) ||
      value['revision'] is! int ||
      value['revision'] < 0 ||
      !['save', 'withdraw', 'restore'].contains(value['action']) ||
      value['requestId'] is! String ||
      !RegExp(r'^[A-Za-z0-9_-]{16,100}$').hasMatch(value['requestId'])) {
    throw const FormatException('Invalid saved review request');
  }
  return Map.of(value);
}
