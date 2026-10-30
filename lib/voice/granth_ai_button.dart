import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../widgets/common.dart';
import 'granth_ai.dart';

/// Floating mic for तत्व. Tap to talk — it does not listen in the background.
/// Created by Faisal Rafi
class GranthAiButton extends StatefulWidget {
  const GranthAiButton({super.key});

  @override
  State<GranthAiButton> createState() => _GranthAiButtonState();
}

class _GranthAiButtonState extends State<GranthAiButton>
    with SingleTickerProviderStateMixin {
  final GranthAiController _ai = GranthAiController();
  final TextEditingController _input = TextEditingController();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _ai.addListener(_syncPulse);
  }

  /// Pulse only while the mic is open. An idle screen must not schedule frames.
  void _syncPulse() {
    if (!mounted) return;
    if (_ai.listening) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating || _pulse.value != 0) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _ai.removeListener(_syncPulse);
    _ai.dispose();
    _input.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _send(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;
    _input.clear();
    _ai.submitText(text);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ai,
      builder: (context, _) {
        final listening = _ai.listening;
        final showCard =
            listening ||
            _ai.status != 'तैयार' ||
            _ai.recognized.isNotEmpty ||
            _ai.response.isNotEmpty;
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        return Positioned(
          right: 16,
          bottom: keyboard > 0 ? keyboard + 12 : 80,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (showCard)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  constraints: const BoxConstraints(
                    maxWidth: 280,
                    minWidth: 260,
                  ),
                  decoration: BoxDecoration(
                    color: GColors.paper,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: GColors.maroon, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: GColors.shadow(0.16),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'तत्व · ${_ai.preset.label}',
                        style: GText.sans(
                          size: 11,
                          weight: FontWeight.w700,
                          color: GColors.maroon,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _ai.status,
                        style: GText.sans(size: 12, color: GColors.muted),
                      ),
                      if (_ai.recognized.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _ai.recognized,
                          style: GText.sans(
                            size: 14,
                            weight: FontWeight.w600,
                            color: GColors.text,
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (_ai.response.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _ai.response,
                          style: GText.script(
                            size: 15,
                            color: GColors.brown,
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: GColors.cream,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: GColors.creamDark),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _input,
                                textInputAction: TextInputAction.send,
                                onSubmitted: _send,
                                cursorColor: GColors.saffron,
                                style: GText.sans(
                                  size: 14,
                                  color: GColors.text,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: 'या लिखें: ऋग्वेद खोलो',
                                  hintStyle: GText.sans(
                                    size: 13,
                                    color: GColors.muted,
                                  ),
                                  contentPadding: const EdgeInsets.fromLTRB(
                                    10,
                                    10,
                                    4,
                                    10,
                                  ),
                                ),
                              ),
                            ),
                            Pressable(
                              onTap: () => _send(_input.text),
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(
                                  Icons.arrow_forward,
                                  color: GColors.maroon,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: GColors.paper,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: GColors.creamDark),
                  boxShadow: [
                    BoxShadow(
                      color: GColors.shadow(0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final v in tatvaVoices)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: _VoiceChip(
                          label: v.id == TatvaVoice.female ? 'स्त्री' : 'पुरुष',
                          selected: _ai.voice == v.id,
                          onTap: () => _ai.setVoice(v.id),
                        ),
                      ),
                    _VoiceChip(
                      label: _ai.voiceEnabled ? 'आवाज़' : 'मौन',
                      selected: _ai.voiceEnabled,
                      onTap: _ai.toggleVoice,
                    ),
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: listening
                    ? 'तत्व सुनना बंद करें'
                    : 'तत्व, बोलकर या लिखकर स्क्रीन खोलें',
                child: Pressable(
                  onTap: () {
                    if (listening) {
                      _ai.stopListening();
                    } else {
                      _ai.startListening();
                    }
                  },
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) {
                      final scale = listening
                          ? 1 + (_pulse.value * 0.06) + (_ai.sound * 0.08)
                          : 1.0;
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: listening ? GColors.saffron : GColors.maroon,
                        boxShadow: [
                          BoxShadow(
                            color: GColors.shadow(0.22),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        listening ? Icons.mic : Icons.mic_none,
                        color: GColors.paper,
                        size: 30,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VoiceChip extends StatelessWidget {
  const _VoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? GColors.maroon : GColors.cream,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: GText.sans(
            size: 12,
            weight: FontWeight.w700,
            color: selected ? GColors.paper : GColors.maroon,
          ),
        ),
      ),
    );
  }
}
