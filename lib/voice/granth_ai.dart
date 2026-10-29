import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/catalog_store.dart';
import '../services/search.dart';
import '../state/router.dart';
import '../models/models.dart';

/// Granth AI — voice navigation assistant for the existing Granth app.
/// Created by Faisal Rafi
class GranthAiController extends ChangeNotifier {
  GranthAiController() {
    _init();
  }

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool listening = false;
  bool available = false;
  String status = 'Ready';
  String recognized = '';
  String response = '';
  bool voiceEnabled = true;

  Future<void> _init() async {
    available = await _speech.initialize(
      onStatus: (s) => _setStatus(s == 'listening' ? 'Listening...' : status),
      onError: (e) => _setStatus('Error: ${e.errorMsg}'),
    );
    await _tts.setLanguage('hi-IN');
    await _tts.setSpeechRate(0.5);
  }

  void _setStatus(String s) {
    status = s;
    notifyListeners();
  }

  Future<void> startListening() async {
    final perm = await Permission.microphone.request();
    if (!perm.isGranted) {
      _setStatus('Microphone permission denied');
      await _speak('Microphone permission chahiye');
      return;
    }
    if (!available) {
      _setStatus('Speech recognition not available');
      return;
    }
    listening = true;
    recognized = '';
    _setStatus('Listening...');
    await _speech.listen(
      onResult: (result) {
        recognized = result.recognizedWords;
        notifyListeners();
        if (result.finalResult) {
          _processCommand(recognized);
        }
      },
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      localeId: 'hi_IN',
      partialResults: true,
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
    listening = false;
    _setStatus('Ready');
  }

  Future<void> _processCommand(String raw) async {
    _setStatus('Understanding command...');
    final cmd = _normalize(raw.toLowerCase());
    final intent = _detectIntent(cmd);
    String spoken = '';

    try {
      switch (intent.type) {
        case 'dashboard':
          AppNav.I.go('#/dashboard');
          spoken = 'Dashboard khol diya hai';
          break;
        case 'topics':
          AppNav.I.go('#/topics');
          spoken = 'Topics section khol diya hai';
          break;
        case 'granths':
          AppNav.I.go('#/granths');
          spoken = 'Granth section khol diya hai';
          break;
        case 'pramans':
          AppNav.I.go('#/pramans');
          spoken = 'Pramaan section khol diya hai';
          break;
        case 'back':
          AppNav.I.back();
          spoken = 'Peeche aa gaye hain';
          break;
        case 'open_granth':
          final granth = _findGranth(intent.entity ?? '');
          if (granth != null) {
            AppNav.I.go('#/pramans?granth=${granth.id}');
            spoken = '${granth.title} khol diya hai';
          } else {
            spoken = 'Ye Granth abhi app mein nahi mila';
          }
          break;
        case 'search':
          // For now navigate to the appropriate section; full search population needs UI access
          AppNav.I.go('#/granths');
          spoken = 'Search results dikha raha hoon';
          break;
        default:
          spoken = 'Command samajh nahi aaya';
      }
      response = spoken;
      _setStatus('Completed');
      if (voiceEnabled) await _speak(spoken);
    } catch (e) {
      response = 'Kuch gadbad ho gayi';
      _setStatus('Error');
      await _speak(response);
    }
    notifyListeners();
  }

  String _normalize(String s) {
    return s
        .replaceAll(RegExp(r'hey granth|hey granth!|granth'), '')
        .replaceAll(RegExp(r'[^\w\s\u0900-\u097F]'), ' ')
        .trim();
  }

  ({String type, String? entity}) _detectIntent(String cmd) {
    if (RegExp(r'dashboard|home|मुख्य|डैशबोर्ड').hasMatch(cmd)) return (type: 'dashboard', entity: null);
    if (RegExp(r'topic|विषय|topics').hasMatch(cmd)) return (type: 'topics', entity: null);
    if (RegExp(r'granth|ग्रंथ|granths').hasMatch(cmd) && !RegExp(r'open|kholo|dikhao').hasMatch(cmd)) return (type: 'granths', entity: null);
    if (RegExp(r'pramaan|प्रमाण|pramans').hasMatch(cmd)) return (type: 'pramans', entity: null);
    if (RegExp(r'back|peeche|previous|वापस').hasMatch(cmd)) return (type: 'back', entity: null);
    if (RegExp(r'search|dhundho|खोज').hasMatch(cmd)) return (type: 'search', entity: cmd);
    // Specific granth
    final name = cmd.replaceAll(RegExp(r'open|kholo|dikhao|show|karo|khol'), '').trim();
    if (name.isNotEmpty) return (type: 'open_granth', entity: name);
    return (type: 'unknown', entity: null);
  }

  Granth? _findGranth(String query) {
    final store = CatalogStore.I;
    final needles = needlesFor(query);
    Granth? best;
    int bestRank = 1 << 30;
    for (final g in store.granths) {
      final doc = store.granthDoc(g);
      if (matches(doc, needles)) {
        final rank = matchRank(doc, needles);
        if (rank < bestRank) {
          bestRank = rank;
          best = g;
        }
      }
    }
    // Aliases for Vedas
    final lower = query.toLowerCase();
    if (best == null) {
      for (final g in store.granths) {
        final t = g.title.toLowerCase();
        if ((lower.contains('rig') && t.contains('ऋग')) ||
            (lower.contains('sam') && t.contains('साम')) ||
            (lower.contains('yajur') && t.contains('यजुर्')) ||
            (lower.contains('atharva') && t.contains('अथर्व'))) {
          return g;
        }
      }
    }
    return best;
  }

  Future<void> _speak(String text) async {
    if (!voiceEnabled) return;
    await _tts.speak(text);
  }

  void toggleVoice() {
    voiceEnabled = !voiceEnabled;
    notifyListeners();
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    super.dispose();
  }
}
