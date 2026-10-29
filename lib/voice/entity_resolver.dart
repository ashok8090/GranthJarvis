import '../models/models.dart';
import '../services/search.dart';

/// A match against the real catalog. Never invents a row. Created by Faisal Rafi.
class EntityMatch<T> {
  EntityMatch._(this.one, this.many);
  factory EntityMatch.none() => EntityMatch._(null, List<T>.empty());
  EntityMatch.one(this.one) : many = List<T>.empty();
  EntityMatch.many(List<T> values) : one = null, many = values;

  final T? one;
  final List<T> many;

  bool get missing => one == null && many.isEmpty;
  bool get ambiguous => one == null && many.length > 1;
}

/// Spoken forms folded onto the stored name. Original records are not renamed.
const List<List<String>> phraseAliases = [
  ['rig veda', 'ऋग्वेद'],
  ['rigveda', 'ऋग्वेद'],
  ['rig ved', 'ऋग्वेद'],
  ['rigved', 'ऋग्वेद'],
  ['sama veda', 'सामवेद'],
  ['samaveda', 'सामवेद'],
  ['sam veda', 'सामवेद'],
  ['samveda', 'सामवेद'],
  ['samved', 'सामवेद'],
  ['yajur veda', 'यजुर्वेद'],
  ['yajurveda', 'यजुर्वेद'],
  ['yajur ved', 'यजुर्वेद'],
  ['yajurved', 'यजुर्वेद'],
  ['atharva veda', 'अथर्ववेद'],
  ['atharvaveda', 'अथर्ववेद'],
  ['atharva ved', 'अथर्ववेद'],
  ['atharvaved', 'अथर्ववेद'],
  ['bhagavad gita', 'भगवदगीता'],
  ['bhagvad gita', 'भगवदगीता'],
  ['bhagwat geeta', 'भगवदगीता'],
  ['bhagavadgita', 'भगवदगीता'],
];

String foldAliases(String query) {
  var s = ' ${normalizeText(query)} ';
  final phrases = [...phraseAliases]..sort((a, b) => b[0].length.compareTo(a[0].length));
  for (final pair in phrases) {
    s = s.replaceAll(' ${pair[0]} ', ' ${pair[1]} ');
  }
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

EntityMatch<T> _pack<T>(List<T> hits) {
  if (hits.isEmpty) return EntityMatch.none();
  if (hits.length == 1) return EntityMatch.one(hits.first);
  return EntityMatch.many(hits.length > 4 ? hits.sublist(0, 4) : hits);
}

bool _romanEquals(String title, String query) {
  final romanQ = foldLatin(transliterate(normalizeText(query)));
  final romanT = foldLatin(transliterate(normalizeText(title)));
  if (romanQ.isEmpty || romanT.isEmpty) return false;
  if (romanT == romanQ) return true;
  final nq = normalizeText(query);
  if (normalizeText(title) == nq) return true;
  if (romanQ.length >= 5 && romanT.contains(romanQ)) return true;
  if (nq.length >= 3 && normalizeText(title).contains(nq)) return true;
  return false;
}

EntityMatch<T> _score<T>(String query, List<T> rows, String Function(T) title, List<String?> Function(T) fields) {
  final q = foldAliases(query);
  if (q.isEmpty || rows.isEmpty) return EntityMatch.none();

  final exact = <T>[];
  final titled = <T>[];
  for (final row in rows) {
    if (_romanEquals(title(row), q)) exact.add(row);
  }
  if (exact.isNotEmpty) {
    final eq = exact.where((row) {
      final romanQ = foldLatin(transliterate(normalizeText(q)));
      final romanT = foldLatin(transliterate(normalizeText(title(row))));
      return romanT == romanQ || normalizeText(title(row)) == normalizeText(q);
    }).toList();
    if (eq.length == 1) return EntityMatch.one(eq.first);
    if (exact.length == 1) return EntityMatch.one(exact.first);
    return _pack(exact);
  }

  final plan = QueryPlan(q);
  final scored = <(T, int)>[];
  for (final row in rows) {
    final s = scorePlan(plan, docOf(fields(row)));
    if (s > 0) scored.add((row, s));
  }
  if (scored.isEmpty) {
    // The existing list search (substring, then fuzzy) is the last local pass.
    final found = searchRows(rows, q, (row) => docOf(fields(row)));
    if (found.isEmpty) return EntityMatch.none();
    if (found.length == 1) return EntityMatch.one(found.first);
    titled.addAll(found.take(4));
    return _pack(titled);
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  final top = scored.first.$2;
  final close = scored.where((e) => e.$2 >= (top * 0.75).round()).map((e) => e.$1).toList();
  if (close.length >= 2 && top >= 20) return _pack(close);
  if (close.length == 1 && top >= 35) return EntityMatch.one(close.first);
  if (top >= 60) return EntityMatch.one(scored.first.$1);
  return EntityMatch.none();
}

int? _ordinal(String q) {
  final m = RegExp(r'(\d+)').firstMatch(q);
  if (m != null) return int.tryParse(m.group(1)!);
  const named = <String, int>{
    'eighteen': 18,
    'atharah': 18,
    'atharaha': 18,
    'अठारह': 18,
  };
  for (final e in named.entries) {
    if (q.contains(e.key)) return e.value;
  }
  return null;
}

bool _looksPurana(String q) => q.contains('puran') || q.contains('पुराण');

EntityMatch<Granth> matchGranths(String query, List<Granth> granths) {
  final q = foldAliases(query);
  final n = _ordinal(q);
  if (n != null && _looksPurana(q)) {
    final hits = granths.where((g) {
      final t = '${g.title} ${g.description}'.toLowerCase();
      final purana = t.contains('पुराण') || t.contains('puran');
      return purana && (t.contains('$n') || t.contains(_hindiNumber(n)));
    }).toList();
    return _pack(hits);
  }
  return _score(q, granths, (g) => g.title, (g) => [g.title, g.author, g.description]);
}

EntityMatch<Topic> matchTopics(String query, List<Topic> topics) =>
    _score(foldAliases(query), topics, (t) => t.title, (t) => [t.title, t.description]);

EntityMatch<Praman> matchPramans(String query, List<Praman> pramans) =>
    _score(foldAliases(query), pramans, (p) => p.title, (p) => [p.title, p.description, p.granthTitle, p.topicTitle]);

String _hindiNumber(int n) {
  const ones = ['', 'एक', 'दो', 'तीन', 'चार', 'पाँच', 'छह', 'सात', 'आठ', 'नौ'];
  if (n >= 0 && n < ones.length) return ones[n];
  if (n == 18) return 'अठारह';
  return '';
}
