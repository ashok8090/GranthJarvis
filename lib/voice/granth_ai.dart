import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
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
  TatvaVoicePreset(TatvaVoice.female, 'स्त्री · Aarohi', 'नरम, ऊँची आवाज़', 1.16, 0.48),
  TatvaVoicePreset(TatvaVoice.male, 'पुरुष · Arun', 'गहरी, शांत आवाज़', 0.76, 0.45),
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
    final perm = await Permission.microphone.request();
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
          onError: (e) {
            listening = false;
            sound = 0;
            status = 'आवाज़ नहीं बनी';
            response = 'फिर से बोलिए। शोर कम हो तो बेहतर सुनाई देगा।';
            notifyListeners();
          },
        );
        if (available) await _pickLocale(speech);
      }
    } catch (e) {
      available = false;
      status = 'आवाज़ नहीं बनी';
      response = 'इस फ़ोन पर स्पीच पहचान शुरू नहीं हुई।';
      notifyListeners();
      return;
    }
    if (!available) {
      status = 'आवाज़ नहीं बनी';
      response = 'इस फ़ोन पर स्पीच पहचान उपलब्ध नहीं है।';
      notifyListeners();
      return;
    }
    listening = true;
    recognized = '';
    sound = 0;
    status = 'सुन रहा हूँ...';
    notifyListeners();
    await _listen(speech, onDevice: true);
  }

  Future<void> _listen(stt.SpeechToText speech, {required bool onDevice}) async {
    try {
      await speech.listen(
        onResult: _onResult,
        onSoundLevelChange: _onLevel,
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          onDevice: onDevice,
          listenMode: stt.ListenMode.dictation,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(seconds: 12),
          localeId: _locale,
          cancelOnError: true,
        ),
      );
    } catch (_) {
      if (onDevice) {
        await _listen(speech, onDevice: false);
        return;
      }
      listening = false;
      status = 'आवाज़ नहीं बनी';
      response = 'सुन नहीं सका। माइक चेक करके फिर बोलिए।';
      notifyListeners();
    }
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
    if (s == 'listening') {
      listening = true;
      status = 'सुन रहा हूँ...';
    } else if (s == 'notListening' || s == 'done') {
      listening = false;
      sound = 0;
      if (status == 'सुन रहा हूँ...') status = 'समझ रहा हूँ...';
    }
    notifyListeners();
  }

  void _onLevel(double level) {
    final n = level <= 1.2 ? level.clamp(0.0, 1.0) : ((level + 2) / 12).clamp(0.0, 1.0);
    sound = n.toDouble();
    notifyListeners();
  }

  void _onResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords;
    final isFinal = result.finalResult;
    recognized = words;
    notifyListeners();
    if (isFinal) {
      listening = false;
      sound = 0;
      if (words.trim().isEmpty) {
        status = 'तैयार';
        notifyListeners();
        return;
      }
      _process(words);
    }
  }

  Future<void> stopListening() async {
    _gen++;
    _handling = false;
    _resume = false;
    _pending = const [];
    try {
      await _speech?.stop();
    } catch (_) {}
    try {
      await _tts?.stop();
    } catch (_) {}
    listening = false;
    sound = 0;
    status = 'तैयार';
    notifyListeners();
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
      status = keepListening ? 'सुन रहा हूँ...' : (spoken.isEmpty ? 'तैयार' : 'हो गया');
      notifyListeners();
      if (spoken.isNotEmpty) await _speak(spoken, gen);
      if (keepListening && gen == _gen) {
        _resume = false;
        final speech = _speech;
        if (speech != null) {
          listening = true;
          sound = 0;
          recognized = '';
          status = 'सुन रहा हूँ...';
          notifyListeners();
          await _listen(speech, onDevice: true);
        }
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
    final cmd = parseUtterance(raw);
    if (gen != _gen) return '';
    if (cmd.needsWake) {
      if (_pending.isNotEmpty) {
        return 'कौन सा? पहला, दूसरा बोलिए, या नाम दोहराइए।';
      }
      return 'पहले सुनो तत्व बोलिए। जैसे: सुनो तत्व, ऋग्वेद खोलो।';
    }
    _pending = const [];
    if (cmd.intent == NavIntent.wakeOnly) {
      _resume = true;
      return 'हाँ, बोलिए। क्या खोलना है?';
    }
    if (cmd.intent == NavIntent.unknown) {
      status = 'समझ नहीं आया';
      return 'कमांड समझ नहीं आया। सुनो तत्व, फिर स्क्रीन का नाम बोलिए।';
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
    if (hit.ambiguous) return _ask(hit.many.map((g) => _Option(g.title, () => _goGranth(g))).toList());
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
    if (hit.ambiguous) return _ask(hit.many.map((t) => _Option(t.title, () => _goTopic(t))).toList());
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
      return _ask(hit.many.map((p) => _Option(p.title.isEmpty ? p.granthTitle : p.title, () => _goPraman(p))).toList());
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
        return _ask(hit.many.map((row) => _Option(row.title, () => _openSavedPdf(row))).toList());
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
          if (item.kind == GalleryKind.pdf && item.id == id && item.filePath.isNotEmpty) {
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
    final names = options.map((e) => e.title).where((e) => e.isNotEmpty).take(3).join(', ');
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
        if (!locale.startsWith('hi') && !locale.contains('en-in') && !locale.contains('en_in')) continue;
        hindi ??= item;
        final blob = '${item['name']} ${item['gender']}'.toLowerCase();
        final isFemale = blob.contains('female') || blob.contains('woman');
        final isMale = blob.contains('male') && !isFemale;
        if (isFemale && female == null) female = item;
        if (isMale && male == null) male = item;
      }
      final pick = voice == TatvaVoice.female ? (female ?? hindi) : (male ?? hindi);
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
