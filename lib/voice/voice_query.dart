import 'package:flutter/foundation.dart';

import '../state/places.dart';

/// Bumps when voice navigation writes a list's search box. Screens listen and
/// refill the existing field. Created by Faisal Rafi.
class VoiceQuery {
  VoiceQuery._();
  static final ticks = ValueNotifier<int>(0);

  static void push(String placeKey, String query) {
    Places.setQuery(placeKey, query);
    ticks.value++;
  }
}
