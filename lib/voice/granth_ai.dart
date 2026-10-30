import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/models.dart';
import '../services/catalog_store.dart';
import '../services/file_actions.dart';
import '../services/gallery_service.dart';
import '../services/search.dart';
import '../services/storage.dart';
import '../state/places.dart';
import '../state/router.dart';
import 'command_parser.dart';
import 'entity_resolver.dart';
import 'voice_query.dart';

/// On-device voice. Not a cloud clone of any assistant. Created by Faisal Rafi.
enum TatvaVoice { female, male }

class TatvaVoicePreset {
  const TatvaVoicePreset(this.id, this.label, this.hint, this.pitch, this.rate);
  final TatvaVoice id;
  final String label;
  final String hint;
  final double pitch;
  final double rate;
}

const tatvaVoices = <TatvaVoicePreset>[
  TatvaVoicePreset(
    TatvaVoice.female,
    'स्त्री · Aarohi',
    'नरम, ऊँची आवाज़',
    1.16,
    0.48,
  ),
  TatvaVoicePreset(
    TatvaVoice.male,
    'पुरुष · Arun',
    'गहरी, शांत आवाज़',
    0.76,
    0.45,
  ),
];

class _Option {
  _Option(this.title, this.open);
  final String title;
  final Future<String> Function() open;
}

/// Voice navigation for the existing Granth screens. Mic button starts a
/// session — it does not listen while the app is closed.
class GranthAiController extends ChangeNotifier {
  GranthAiController() {
    _loadPrefs();
  }

  static const _kVoice = 'granth-ai-voice';
  static const _kSpeak = 'granth-ai-speak';

  stt.SpeechToText? _speech;
  FlutterTts? _tts;
  bool listening = false;
  bool available = false;
  String status = 'तैयार';
  String recognized = '';
  String response = '';
  bool voiceEnabled = true;
  TatvaVoice voice = TatvaVoice.female;
  double sound = 0;
  String? _locale;
  int _gen = 0;
  String _lastKey = '';
  int _lastAt = 0;
  bool _handling = false;
  bool _resume = false;
  List<_Option> _pending = const [];
  int _session = 0;
  int _bound = 0;
  bool _accept = false;
  int _retries = 0;
  bool _retryQueued = false;
  bool _gotWords = false;

  static const _navPhrases = <String>[
    'तत्व',
    'सुनो तत्व',
    'विषय',
    'ग्रंथ',
    'प्रमाण',
    'पीछे',
    'होम',
    'डैशबोर्ड',
    'ऋग्वेद',
    'सामवेद',
    'यजुर्वेद',
    'अथर्ववेद',
    'गीता',
    'खोलो',
  ];

  TatvaVoicePreset get preset => tatvaVoices.firstWhere((e) => e.id == voice);

  void _loadPrefs() {
    final saved = Store.I.getString(_kVoice);
    if (saved == 'male' || saved == 'female') {
      voice = saved == 'male' ? TatvaVoice.male : TatvaVoice.female;
    }
    final speak = Store.I.getString(_kSpeak);
    if (speak == '0' || speak == '1') voiceEnabled = speak != '0';
  }

  Future<void> startListening() async {
    _loadPrefs();
    _gen++;
    _session++;
    _handling = false;
    _resume = false;
    _retries = 0;
    _retryQueued = false;
    _gotWords = false;
    _accept = false;
    final session = _session;
    final perm = await Permission.microphone.request();
    if (session != _session) return;
    if (!perm.isGranted) {
      status = 'माइक बंद है';
      response = 'माइक्रोफ़ोन की अनुमति चाहिए। सेटिंग में माइक चालू करें।';
      listening = false;
      notifyListeners();
      if (perm.isPermanentlyDenied) {
        await openAppSettings();
      }
      return;
    }
    final speech = _speech ??= stt.SpeechToText();
    try {
      if (!available) {
        available = await speech.initialize(
          onStatus: _onStatus,
          onError: _onError,
          finalTimeout: const Duration(milliseconds: 1200),
          options: [
            stt.SpeechToText.androidNoBluetooth,
            stt.SpeechToText.androidIntentLookup,
          ],
        );
        if (available) await _pickLocale(speech);
      }
    } catch (_) {
      available = false;
      status = 'आवाज़ नहीं बनी';
      response =
          'इस फ़ोन पर स्पीच पहचान शुरू नहीं हुई। नीचे लिख दें, जैसे ऋग्वेद खोलो।';
      notifyListeners();
      return;
    }
    if (session != _session) return;
    if (!available) {
      status = 'आवाज़ नहीं बनी';
      response =
          'इस फ़ोन पर स्पीच पहचान उपलब्ध नहीं है। नीचे लिख दें, जैसे ऋग्वेद खोलो।';
      notifyListeners();
      return;
    }
    listening = true;
    recognized = '';
    sound = 0;
    status = 'सुन रहा हूँ...';
    if (_pending.isEmpty) {
      response = 'बोलिए: ऋग्वेद खोलो, विषय, प्रमाण, या पीछे।';
    }
    notifyListeners();
    await _beginListen(session);
  }

  /// Phone recognizer, not the offline Hindi pack. Offline-first fails at once
  /// on most Android phones and the button used to report that as "no voice".
  Future<void> _beginListen(int session) async {
    final speech = _speech;
    if (speech == null || session != _session) return;
    _gotWords = false;
    _retryQueued = false;
    try {
      if (speech.isListening) {
        await speech.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } catch (_) {}
    if (session != _session) return;
    _bound = session;
    _accept = true;
    if (session != _session) {
      _accept = false;
      return;
    }
    try {
      await speech.listen(
        onResult: _onResult,
        onSoundLevelChange: _onLevel,
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          onDevice: false,
          listenMode: stt.ListenMode.confirmation,
          pauseFor: const Duration(seconds: 2),
          listenFor: const Duration(seconds: 8),
          localeId: _locale,
          cancelOnError: false,
          contextualPhrases: _navPhrases,
        ),
      );
    } catch (_) {
      if (session != _session) return;
      _queueRetry(session, 'error_client');
    }
  }

  void _onError(SpeechRecognitionError err) {
    if (!_accept || _bound != _session) return;
    _accept = false;
    final heard = recognized.trim();
    if (_gotWords && heard.isNotEmpty) {
      listening = false;
      sound = 0;
      _process(heard);
      return;
    }
    final code = err.errorMsg;
    listening = false;
    sound = 0;
    if (code == 'error_no_match' || code == 'error_speech_timeout') {
      status = 'सुनाई नहीं दिया';
      response = 'कुछ सुनाई नहीं दिया। फिर से बोलिए, या नीचे लिख दें।';
      notifyListeners();
      return;
    }
    if (code == 'error_permission') {
      status = 'माइक बंद है';
      response = 'माइक्रोफ़ोन की अनुमति चाहिए। सेटिंग में माइक चालू करें।';
      notifyListeners();
      return;
    }
    _queueRetry(_bound, code);
  }

  void _queueRetry(int session, String code) {
    if (session != _session || _retryQueued || _gotWords) return;
    final language =
        code == 'error_language_unavailable' ||
        code == 'error_language_not_supported';
    final retryable =
        language ||
        code == 'error_client' ||
        code == 'error_busy' ||
        code == 'error_network' ||
        code == 'error_network_timeout' ||
        code == 'error_server' ||
        code == 'error_server_disconnected' ||
        code == 'error_audio_error' ||
        code.startsWith('error_unknown');
    if (!retryable || _retries >= 2) {
      _failMic();
      return;
    }
    _retries++;
    _retryQueued = true;
    if (language || _retries >= 2) _locale = null;
    status = 'फिर सुन रहा हूँ...';
    listening = false;
    sound = 0;
    notifyListeners();
    _retryLater(session);
  }

  Future<void> _retryLater(int session) async {
    final speech = _speech;
    try {
      await speech?.cancel();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (session != _session) return;
    listening = true;
    sound = 0;
    recognized = '';
    status = 'सुन रहा हूँ...';
    notifyListeners();
    await _beginListen(session);
  }

  void _failMic() {
    listening = false;
    sound = 0;
    status = 'आवाज़ नहीं बनी';
    response = 'माइक से नहीं सुना। नीचे लिख दें, जैसे ऋग्वेद खोलो।';
    notifyListeners();
  }

  Future<void> _pickLocale(stt.SpeechToText speech) async {
    try {
      final locales = await speech.locales();
      for (final l in locales) {
        final id = l.localeId.toLowerCase().replaceAll('-', '_');
        if (id == 'hi_in') {
          _locale = l.localeId;
          return;
        }
      }
      for (final l in locales) {
        final id = l.localeId.toLowerCase();
        if (id.startsWith('hi')) {
          _locale = l.localeId;
          return;
        }
      }
    } catch (_) {}
  }

  void _onStatus(String s) {
    if (!_accept || _bound != _session) return;
    if (s == 'listening') {
      listening = true;
      if (status != 'समझ रहा हूँ...') status = 'सुन रहा हूँ...';
    } else if (s == 'notListening' || s == 'done') {
      listening = false;
      sound = 0;
      if (status == 'सुन रहा हूँ...') status = 'समझ रहा हूँ...';
    }
    notifyListeners();
  }

  void _onLevel(double level) {
    if (!_accept || _bound != _session || !listening) return;
    final n = level <= 1.2
        ? level.clamp(0.0, 1.0)
        : ((level + 2) / 12).clamp(0.0, 1.0);
    sound = n.toDouble();
    notifyListeners();
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!_accept || _bound != _session) return;
    final words = result.recognizedWords;
    final isFinal = result.finalResult;
    recognized = words;
    if (words.trim().isNotEmpty) _gotWords = true;
    notifyListeners();
    if (!isFinal) return;
    _accept = false;
    listening = false;
    sound = 0;
    if (words.trim().isEmpty) {
      status = 'सुनाई नहीं दिया';
      response = 'कुछ सुनाई नहीं दिया। फिर से बोलिए, या नीचे लिख दें।';
      notifyListeners();
      return;
    }
    _process(words);
  }

  Future<void> stopListening() async {
    _gen++;
    _session++;
    _handling = false;
    _resume = false;
    _retryQueued = false;
    _accept = false;
    _pending = const [];
    try {
      await _speech?.cancel();
    } catch (_) {}
    try {
      await _tts?.stop();
    } catch (_) {}
    listening = false;
    sound = 0;
    status = 'तैयार';
    notifyListeners();
  }

  /// Typed navigation. The tap already woke the assistant, so this does not
  /// ask for "सुनो तत्व" and does not clear a pending clarification.
  Future<void> submitText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _gen++;
    _session++;
    _handling = false;
    _resume = false;
    _retryQueued = false;
    _accept = false;
    try {
      await _speech?.cancel();
    } catch (_) {}
    try {
      await _tts?.stop();
    } catch (_) {}
    listening = false;
    sound = 0;
    recognized = trimmed;
    notifyListeners();
    await _process(trimmed);
  }

  void setVoice(TatvaVoice next) {
    voice = next;
    Store.I.setString(_kVoice, next == TatvaVoice.male ? 'male' : 'female');
    notifyListeners();
  }

  void toggleVoice() {
    voiceEnabled = !voiceEnabled;
    Store.I.setString(_kSpeak, voiceEnabled ? '1' : '0');
    if (!voiceEnabled) _tts?.stop();
    notifyListeners();
  }

  Future<void> _process(String raw) async {
    final key = raw.trim().toLowerCase();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (key == _lastKey && now - _lastAt < 1500) return;
    _lastKey = key;
    _lastAt = now;
    if (_handling) return;
    _handling = true;
    _resume = false;
    final gen = _gen;
    status = 'समझ रहा हूँ...';
    notifyListeners();
    try {
      final spoken = await _run(raw, gen);
      if (gen != _gen) return;
      response = spoken;
      final keepListening = gen == _gen && _resume;
      status = keepListening
          ? 'सुन रहा हूँ...'
          : (spoken.isEmpty ? 'तैयार' : 'हो गया');
      notifyListeners();
      if (spoken.isNotEmpty) await _speak(spoken, gen);
      if (keepListening && gen == _gen) {
        _resume = false;
        _retries = 0;
        listening = true;
        sound = 0;
        recognized = '';
        status = 'सुन रहा हूँ...';
        notifyListeners();
        await _beginListen(_session);
      }
    } catch (_) {
      if (gen != _gen) return;
      response = 'कुछ गड़बड़ हो गई। फिर से बोलिए।';
      status = 'समझ नहीं आया';
      notifyListeners();
      await _speak(response, gen);
    } finally {
      if (gen == _gen) _handling = false;
    }
  }

  Future<String> _run(String raw, int gen) async {
    if (_pending.isNotEmpty) {
      final picked = choiceIndex(raw, _pending.length);
      if (picked != null) {
        final opt = _pending[picked];
        _pending = const [];
        status = 'स्क्रीन खोल रहा हूँ...';
        notifyListeners();
        return opt.open();
      }
      final narrowed = _matchByTitle(stripWake(normalizeText(raw)));
      if (narrowed != null) {
        _pending = const [];
        return narrowed.open();
      }
    }
    final cmd = parseUtterance(raw, requireWake: false);
    if (gen != _gen) return '';
    if (cmd.needsWake) {
      if (_pending.isNotEmpty) {
        return 'कौन सा? पहला, दूसरा बोलिए, या नाम दोहराइए।';
      }
      return 'कमांड समझ नहीं आया। उदाहरण: ऋग्वेद खोलो, विषय, प्रमाण, पीछे।';
    }
    _pending = const [];
    if (cmd.intent == NavIntent.wakeOnly) {
      _resume = true;
      return 'हाँ, बोलिए। क्या खोलना है?';
    }
    if (cmd.intent == NavIntent.unknown) {
      status = 'समझ नहीं आया';
      return 'कमांड समझ नहीं आया। उदाहरण: ऋग्वेद खोलो, विषय, प्रमाण, पीछे।';
    }
    return _execute(cmd);
  }

  _Option? _matchByTitle(String name) {
    if (name.isEmpty) return null;
    final hits = _pending.where((o) => _normalizeHit(o.title, name)).toList();
    if (hits.length == 1) return hits.first;
    return null;
  }

  bool _normalizeHit(String title, String name) {
    final a = title.toLowerCase();
    final b = name.toLowerCase();
    return a.contains(b) || b.contains(a);
  }

  Future<String> _execute(NavCommand cmd) async {
    switch (cmd.intent) {
      case NavIntent.dashboard:
        AppNav.I.go('#/dashboard');
        return 'डैशबोर्ड खोल दिया है।';
      case NavIntent.topics:
        AppNav.I.go('#/topics');
        return 'विषय सेक्शन खोल दिया है।';
      case NavIntent.granths:
        AppNav.I.go('#/granths');
        return 'ग्रंथ सेक्शन खोल दिया है।';
      case NavIntent.pramans:
        AppNav.I.go('#/pramans');
        return 'प्रमाण सेक्शन खोल दिया है।';
      case NavIntent.back:
        if (AppNav.I.route.panel == Panel.dashboard) {
          return 'आप पहले से होम पर हैं।';
        }
        AppNav.I.back();
        return 'पीछे आ गए हैं।';
      case NavIntent.search:
        return _search(cmd.destinationType, cmd.searchQuery);
      case NavIntent.openGranth:
        return _openGranth(cmd.destinationName);
      case NavIntent.openTopic:
        return _openTopic(cmd.destinationName);
      case NavIntent.openPraman:
        return _openPraman(cmd.destinationName);
      case NavIntent.openPdf:
        return _openPdf(cmd.destinationName);
      case NavIntent.wakeOnly:
      case NavIntent.unknown:
        return 'कमांड समझ नहीं आया।';
    }
  }

  Future<String> _search(String scope, String query) async {
    if (query.isEmpty) {
      if (scope == 'topic') {
        AppNav.I.go('#/topics');
        return 'विषय खोल दिए हैं। नाम बोलिए तो खोज भर दूँ।';
      }
      if (scope == 'praman') {
        AppNav.I.go('#/pramans');
        return 'प्रमाण खोल दिए हैं। नाम बोलिए तो खोज भर दूँ।';
      }
      AppNav.I.go('#/granths?all=1');
      return 'ग्रंथ खोल दिए हैं। नाम बोलिए तो खोज भर दूँ।';
    }
    if (scope == 'topic') {
      VoiceQuery.push('topic-list-place', query);
      AppNav.I.go('#/topics');
      return 'विषय में खोज खोल दी है।';
    }
    if (scope == 'praman') {
      VoiceQuery.push('praman-list::', query);
      AppNav.I.go('#/pramans');
      return 'प्रमाण में खोज खोल दी है।';
    }
    VoiceQuery.push('granth-list-place', query);
    AppNav.I.go('#/granths?all=1');
    return 'ग्रंथ में खोज खोल दी है।';
  }

  Future<String> _openGranth(String name) async {
    final store = CatalogStore.I;
    if (!store.hasData) return 'डेटा अभी लोड नहीं हुआ। एक बार सिंक करें।';
    status = 'ग्रंथ ढूँढ रहा हूँ...';
    notifyListeners();
    final hit = matchGranths(name, store.granths);
    if (hit.missing) return 'यह ग्रंथ अभी ऐप में नहीं मिला।';
    if (hit.ambiguous) {
      return _ask(
        hit.many.map((g) => _Option(g.title, () => _goGranth(g))).toList(),
      );
    }
    return _goGranth(hit.one!);
  }

  Future<String> _goGranth(Granth g) async {
    Places.setQuery('praman-list:${g.id}:', '');
    status = 'स्क्रीन खोल रहा हूँ...';
    notifyListeners();
    AppNav.I.go('#/pramans?granth=${g.id}');
    return '${_label(g.title)} खोल दिया है।';
  }

  Future<String> _openTopic(String name) async {
    final store = CatalogStore.I;
    if (!store.hasData) return 'डेटा अभी लोड नहीं हुआ। एक बार सिंक करें।';
    status = 'विषय ढूँढ रहा हूँ...';
    notifyListeners();
    final hit = matchTopics(name, store.topics);
    if (hit.missing) return 'यह विषय अभी ऐप में नहीं मिला।';
    if (hit.ambiguous) {
      return _ask(
        hit.many.map((t) => _Option(t.title, () => _goTopic(t))).toList(),
      );
    }
    return _goTopic(hit.one!);
  }

  Future<String> _goTopic(Topic t) async {
    Places.setQuery('praman-list::${t.id}', '');
    AppNav.I.go('#/pramans?topic=${t.id}');
    return '${_label(t.title)} खोल दिया है।';
  }

  Future<String> _openPraman(String name) async {
    final store = CatalogStore.I;
    if (!store.hasData) return 'डेटा अभी लोड नहीं हुआ। एक बार सिंक करें।';
    status = 'प्रमाण ढूँढ रहा हूँ...';
    notifyListeners();
    final hit = matchPramans(name, store.pramans);
    if (hit.missing) return 'यह प्रमाण अभी ऐप में नहीं मिला।';
    if (hit.ambiguous) {
      return _ask(
        hit.many
            .map(
              (p) => _Option(
                p.title.isEmpty ? p.granthTitle : p.title,
                () => _goPraman(p),
              ),
            )
            .toList(),
      );
    }
    return _goPraman(hit.one!);
  }

  Future<String> _goPraman(Praman p) async {
    Places.setQuery('praman-list::', '');
    AppNav.I.go('#/pramans?id=${p.id}');
    final label = p.title.isEmpty ? p.granthTitle : p.title;
    return '${_label(label)} खोल दिया है।';
  }

  Future<String> _openPdf(String name) async {
    final store = CatalogStore.I;
    Granth? g;
    if (name.isEmpty) {
      final id = AppNav.I.route.granthId;
      if (id != null) {
        for (final row in store.granths) {
          if (row.id == id) g = row;
        }
      }
      if (g == null) return 'किस ग्रंथ का PDF खोलना है? नाम बोलिए।';
    } else {
      if (!store.hasData) return 'डेटा अभी लोड नहीं हुआ। एक बार सिंक करें।';
      status = 'ग्रंथ ढूँढ रहा हूँ...';
      notifyListeners();
      final hit = matchGranths(name, store.granths);
      if (hit.missing) return 'यह ग्रंथ अभी ऐप में नहीं मिला।';
      if (hit.ambiguous) {
        return _ask(
          hit.many
              .map((row) => _Option(row.title, () => _openSavedPdf(row)))
              .toList(),
        );
      }
      g = hit.one;
    }
    return _openSavedPdf(g!);
  }

  /// Opens a PDF only when it is already in the gallery. Never starts a download.
  Future<String> _openSavedPdf(Granth g) async {
    try {
      if (Store.I.ready) {
        final items = await GalleryService.I.items();
        final id = 'pdf-granth-${g.id}';
        for (final item in items) {
          if (item.kind == GalleryKind.pdf &&
              item.id == id &&
              item.filePath.isNotEmpty) {
            final ok = await FileActions.open(item.filePath, item.fileName);
            if (ok) return '${_label(g.title)} PDF खोल रहा हूँ।';
          }
        }
      }
    } catch (_) {}
    Places.setQuery('praman-list:${g.id}:', '');
    AppNav.I.go('#/pramans?granth=${g.id}');
    return '${_label(g.title)} का PDF अभी डाउनलोड नहीं है। ग्रंथ खोल दिया है।';
  }

  String _ask(List<_Option> options) {
    _pending = options;
    final names = options
        .map((e) => e.title)
        .where((e) => e.isNotEmpty)
        .take(3)
        .join(', ');
    status = 'समझ रहा हूँ...';
    return 'कई नाम मिले: $names. पहला, दूसरा बोलिए, या नाम दोहराइए।';
  }

  String _label(String title) => title.trim().isEmpty ? 'यह' : title.trim();

  Future<void> _speak(String text, int gen) async {
    if (!voiceEnabled || text.isEmpty || gen != _gen) return;
    try {
      final tts = _tts ??= FlutterTts();
      await tts.awaitSpeakCompletion(true);
      await tts.setLanguage('hi-IN');
      await tts.setVolume(1);
      await tts.setPitch(preset.pitch);
      await tts.setSpeechRate(preset.rate);
      await _applyEngineVoice(tts);
      if (gen != _gen) return;
      await tts.speak(text);
    } catch (_) {}
  }

  Future<void> _applyEngineVoice(FlutterTts tts) async {
    try {
      final raw = await tts.getVoices;
      if (raw is! List) return;
      Map? female;
      Map? male;
      Map? hindi;
      for (final item in raw) {
        if (item is! Map) continue;
        final locale = '${item['locale'] ?? ''}'.toLowerCase();
        if (!locale.startsWith('hi') &&
            !locale.contains('en-in') &&
            !locale.contains('en_in')) {
          continue;
        }
        hindi ??= item;
        final blob = '${item['name']} ${item['gender']}'.toLowerCase();
        final isFemale = blob.contains('female') || blob.contains('woman');
        final isMale = blob.contains('male') && !isFemale;
        if (isFemale && female == null) female = item;
        if (isMale && male == null) male = item;
      }
      final pick = voice == TatvaVoice.female
          ? (female ?? hindi)
          : (male ?? hindi);
      if (pick == null) return;
      final name = pick['name'];
      final locale = pick['locale'];
      if (name is String && locale is String) {
        await tts.setVoice({'name': name, 'locale': locale});
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _gen++;
    _speech?.stop();
    _tts?.stop();
    super.dispose();
  }
}
