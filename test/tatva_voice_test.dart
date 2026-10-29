import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/models/models.dart';
import 'package:granthprabandhan/voice/command_parser.dart';
import 'package:granthprabandhan/voice/entity_resolver.dart';

void main() {
  test('wake phrase is suno tatva, not a name that listens by itself', () {
    expect(parseUtterance('rigved kholo').needsWake, isTrue);
    expect(parseUtterance('hey granth topics').needsWake, isTrue);
    expect(parseUtterance('सुनो तत्व').intent, NavIntent.wakeOnly);
    expect(parseUtterance('suno tatv').intent, NavIntent.wakeOnly);
    expect(parseUtterance('sunno tattva').intent, NavIntent.wakeOnly);
  });

  test('navigation commands after the wake phrase', () {
    expect(parseUtterance('suno tatva topics').intent, NavIntent.topics);
    expect(parseUtterance('सुनो तत्व डैशबोर्ड').intent, NavIntent.dashboard);
    expect(parseUtterance('suno tatv home').intent, NavIntent.dashboard);
    expect(parseUtterance('suno tatva praman').intent, NavIntent.pramans);
    expect(parseUtterance('suno tatva granth').intent, NavIntent.granths);
    expect(parseUtterance('suno tatva back').intent, NavIntent.back);
    expect(parseUtterance('सुनो तत्व पीछे').intent, NavIntent.back);

    final pdf = parseUtterance('suno tatva rigved pdf');
    expect(pdf.intent, NavIntent.openPdf);
    expect(pdf.destinationName, contains('rigved'));

    final search = parseUtterance('suno tatva praman khojo mrityu');
    expect(search.intent, NavIntent.search);
    expect(search.destinationType, 'praman');
    expect(search.searchQuery, contains('mrityu'));

    final open = parseUtterance('सुनो तत्व ऋग्वेद खोलो');
    expect(open.intent, NavIntent.openGranth);
    expect(open.destinationName, contains('ऋग्वेद'));
  });

  test('clarification picks the spoken choice and does not invent a granth', () {
    expect(choiceIndex('पहला', 3), 0);
    expect(choiceIndex('second', 3), 1);
    expect(choiceIndex('4', 2), isNull);

    final rows = [
      Granth({'id': '1', 'title': 'ऋग्वेद', 'author': '', 'description': ''}),
      Granth({'id': '2', 'title': 'सामवेद', 'author': '', 'description': 'साम'}),
    ];
    final hit = matchGranths('rig veda', rows);
    expect(hit.one?.id, '1');
    expect(hit.ambiguous, isFalse);

    final missing = matchGranths('not a real book zzzqqq', rows);
    expect(missing.missing, isTrue);
    expect(missing.one, isNull);
  });
}
