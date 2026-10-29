import 'package:flutter/material.dart';
import 'granth_ai.dart';

/// Floating mic button and status overlay for Granth AI.
/// Created by Faisal Rafi
class GranthAiButton extends StatefulWidget {
  const GranthAiButton({super.key});

  @override
  State<GranthAiButton> createState() => _GranthAiButtonState();
}

class _GranthAiButtonState extends State<GranthAiButton> with SingleTickerProviderStateMixin {
  final GranthAiController _ai = GranthAiController();
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void dispose() {
    _ai.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ai,
      builder: (context, _) {
        return Positioned(
          right: 16,
          bottom: 80,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_ai.recognized.isNotEmpty || _ai.response.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxWidth: 260),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_ai.status, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      if (_ai.recognized.isNotEmpty) Text(_ai.recognized, style: const TextStyle(color: Colors.white, fontSize: 14)),
                      if (_ai.response.isNotEmpty) Text(_ai.response, style: const TextStyle(color: Colors.amber, fontSize: 14)),
                    ],
                  ),
                ),
              GestureDetector(
                onTap: () {
                  if (_ai.listening) {
                    _ai.stopListening();
                  } else {
                    _ai.startListening();
                  }
                },
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    final scale = _ai.listening ? 1.0 + _pulse.value * 0.15 : 1.0;
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _ai.listening ? Colors.redAccent : const Color(0xFF7B1F2E),
                          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: const Offset(0, 4))],
                        ),
                        child: Icon(_ai.listening ? Icons.mic : Icons.mic_none, color: Colors.white, size: 32),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
