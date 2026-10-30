import '../services/search.dart';

/// What the navigation assistant should do. Created by Faisal Rafi.
enum NavIntent {
  dashboard,
  topics,
  granths,
  pramans,
  back,
  openGranth,
  openTopic,
  openPraman,
  search,
  openPdf,
  wakeOnly,
  unknown,
}

class NavCommand {
  const NavCommand({
    required this.intent,
    this.destinationType = '',
    this.destinationName = '',
    this.searchQuery = '',
    this.needsWake = false,
    this.confidence = 1,
  });

  final NavIntent intent;
  final String destinationType;
  final String destinationName;
  final String searchQuery;
  final bool needsWake;
  final double confidence;

  bool get requiresClarification => false;
}

/// Wake phrase: "सुनो तत्व" / "suno tatv" (and close spellings).
final RegExp wakePhrase = RegExp(
  r'(सुनो|सुना|suno|sunno)\s*(तत्व|तत्त्व|tatva|tattva|tatwa|tatw|tatav|tatv)',
);

const _fillerPhrases = [
  'kar do',
  'khol do',
  'dikha do',
  'le chalo',
  'par jao',
  'par jaao',
  'par chalo',
  'karke dikhao',
  'ko open',
  'main screen',
];

const _fillerWords = [
  'open',
  'kholo',
  'khol',
  'kholna',
  'khole',
  'kholiye',
  'dikhao',
  'dikha',
  'dikhaiye',
  'show',
  'karo',
  'kar',
  'please',
  'kindly',
  'mujhe',
  'mujhko',
  'the',
  'an',
  'a',
  'section',
  'par',
  'jao',
  'jaao',
  'le',
  'chalo',
  'ko',
  'mein',
  'me',
  'do',
  'for',
  'of',
  'about',
  'se',
  'all',
  'sabhi',
  'sab',
  'screen',
  'go',
  'to',
  'app',
  'pe',
  'per',
  'kijiye',
  'now',
  'ab',
  'hai',
  'this',
  'that',
  'related',
  'karke',
  'wala',
  'wali',
  'mere',
  'mera',
  'meri',
  'just',
  'खोलो',
  'खोल',
  'दिखाओ',
  'दिखा',
  'करो',
  'मुझे',
  'पर',
  'जाओ',
  'चलाओ',
  'सेक्शन',
  'कृपया',
  'में',
  'का',
  'की',
  'के',
];

const _dashWords = ['dashboard', 'home', 'डैशबोर्ड', 'होम', 'मुख्य'];
const _topicWords = ['topics', 'topic', 'विषय', 'विषयों', 'टॉपिक', 'टॉपिक्स'];
const _pramanWords = [
  'pramaans',
  'pramans',
  'pramaan',
  'praman',
  'प्रमाण',
  'प्रमाणों',
];
const _granthWords = ['granths', 'granth', 'ग्रन्थ', 'ग्रंथ'];
const _searchWords = [
  'search',
  'find',
  'dhundho',
  'dhundo',
  'dhoondo',
  'khojo',
  'khoj',
  'खोजो',
  'खोज',
  'ढूंढो',
  'ढूँढो',
  'ढूंढ',
  'ढूँढ',
];
const _pdfWords = ['pdf', 'peedeeef', 'पीडीएफ'];
const _backWords = [
  'back',
  'peeche',
  'piche',
  'peche',
  'picche',
  'previous',
  'पीछे',
  'पिछे',
  'वापस',
];

bool _hasWord(String s, List<String> words) {
  final padded = ' $s ';
  for (final w in words) {
    if (padded.contains(' $w ')) return true;
  }
  return false;
}

String _without(String s, List<String> words) {
  var t = ' $s ';
  for (final w in words) {
    t = t.replaceAll(' $w ', ' ');
  }
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String dropFillers(String s) {
  var t = ' ${s.replaceAll(RegExp(r'\s+'), ' ').trim()} ';
  for (final p in _fillerPhrases) {
    t = t.replaceAll(' $p ', ' ');
  }
  for (var i = 0; i < 4; i++) {
    for (final w in _fillerWords) {
      t = t.replaceAll(' $w ', ' ');
    }
  }
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String stripWake(String normalized) => normalized
    .replaceAll(wakePhrase, ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// 0-based choice when the user is clarifying ("पहला", "2", "second").
int? choiceIndex(String raw, int count) {
  if (count <= 0) return null;
  final s = stripWake(normalizeText(raw));
  int? n;
  if (RegExp(r'^(1|pehla|pehla wala|first|पहला|एक)$').hasMatch(s)) n = 0;
  if (RegExp(r'^(2|dusra|doosra|second|दूसरा|दो)$').hasMatch(s)) n = 1;
  if (RegExp(r'^(3|teesra|tisra|third|तीसरा|तीन)$').hasMatch(s)) n = 2;
  if (RegExp(r'^(4|chautha|fourth|चौथा|चार)$').hasMatch(s)) n = 3;
  if (n == null || n >= count) return null;
  return n;
}

NavCommand parseUtterance(String raw, {bool requireWake = true}) {
  final norm = normalizeText(raw);
  final woke = wakePhrase.hasMatch(norm);
  if (!woke && requireWake) {
    return const NavCommand(
      intent: NavIntent.unknown,
      needsWake: true,
      confidence: 0,
    );
  }
  final body = woke ? stripWake(norm) : norm;
  if (body.isEmpty) {
    return const NavCommand(intent: NavIntent.wakeOnly, confidence: 1);
  }
  return parseCommand(body);
}

/// [text] is already wake-stripped and normalized.
NavCommand parseCommand(String text) {
  final s = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return const NavCommand(intent: NavIntent.wakeOnly);

  if (_hasWord(s, _pdfWords)) {
    final name = dropFillers(_without(s, _pdfWords));
    return NavCommand(
      intent: NavIntent.openPdf,
      destinationType: 'pdf',
      destinationName: name,
      searchQuery: name,
    );
  }
  if (_hasWord(s, _backWords)) {
    return const NavCommand(intent: NavIntent.back, destinationType: 'back');
  }
  if (_hasWord(s, _searchWords)) {
    var scope = 'granth';
    if (_hasWord(s, _topicWords)) scope = 'topic';
    if (_hasWord(s, _pramanWords)) scope = 'praman';
    final q = dropFillers(
      _without(
        _without(
          _without(_without(s, _searchWords), _topicWords),
          _pramanWords,
        ),
        _granthWords,
      ),
    );
    return NavCommand(
      intent: NavIntent.search,
      destinationType: scope,
      destinationName: q,
      searchQuery: q,
    );
  }
  if (_hasWord(s, _dashWords)) {
    final rest = dropFillers(_without(s, _dashWords));
    if (rest.isEmpty) {
      return const NavCommand(
        intent: NavIntent.dashboard,
        destinationType: 'dashboard',
      );
    }
  }
  if (_hasWord(s, _topicWords)) {
    final name = dropFillers(_without(s, _topicWords));
    if (name.isEmpty) {
      return const NavCommand(
        intent: NavIntent.topics,
        destinationType: 'topic',
      );
    }
    return NavCommand(
      intent: NavIntent.openTopic,
      destinationType: 'topic',
      destinationName: name,
      searchQuery: name,
    );
  }
  if (_hasWord(s, _pramanWords)) {
    final name = dropFillers(_without(s, _pramanWords));
    if (name.isEmpty) {
      return const NavCommand(
        intent: NavIntent.pramans,
        destinationType: 'praman',
      );
    }
    return NavCommand(
      intent: NavIntent.openPraman,
      destinationType: 'praman',
      destinationName: name,
      searchQuery: name,
    );
  }
  if (_hasWord(s, _granthWords)) {
    final name = dropFillers(_without(s, _granthWords));
    if (name.isEmpty) {
      return const NavCommand(
        intent: NavIntent.granths,
        destinationType: 'granth',
      );
    }
    return NavCommand(
      intent: NavIntent.openGranth,
      destinationType: 'granth',
      destinationName: name,
      searchQuery: name,
    );
  }
  final name = dropFillers(s);
  if (name.isEmpty) {
    return const NavCommand(intent: NavIntent.unknown, confidence: 0);
  }
  return NavCommand(
    intent: NavIntent.openGranth,
    destinationType: 'granth',
    destinationName: name,
    searchQuery: name,
    confidence: 0.8,
  );
}
