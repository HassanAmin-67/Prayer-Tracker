import 'package:flutter/material.dart';

enum DotState { done, missed, locked }

class PrayerWidgetCard extends StatelessWidget {
  const PrayerWidgetCard({
    super.key,
    required this.label,
    required this.doneCount,
    required this.names,
    required this.states,
  });

  final String label;
  final int doneCount;
  final List<String> names;
  final List<DotState> states;

  static const _bgTop = Color(0xFF0B8F58);
  static const _bgBottom = Color(0xFF033A2F);
  static const _mint = Color(0xFF2BD28C);
  static const double _d = 28;

  Color _lineColor(DotState s) =>
      s == DotState.done ? _mint : Colors.white.withValues(alpha: 0.3);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: 320,
            height: 110,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_bgTop, _bgBottom],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                        Text(
                          '$doneCount of 5',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Center(
                        child: Row(
                          children: [
                            for (int i = 0; i < 5; i++) Expanded(child: _cell(i)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(int i) {
    final s = states[i];
    final leftColor = i == 0 ? Colors.transparent : _lineColor(states[i - 1]);
    final rightColor = i == 4 ? Colors.transparent : _lineColor(s);
    final nameColor = s == DotState.locked
        ? Colors.white.withValues(alpha: 0.4)
        : Colors.white.withValues(alpha: 0.95);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Container(height: 2, color: leftColor)),
            _circle(s),
            Expanded(child: Container(height: 2, color: rightColor)),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          names[i],
          style: TextStyle(fontSize: 11, color: nameColor),
        ),
      ],
    );
  }

  Widget _circle(DotState s) {
    final done = s == DotState.done;
    final fill = done
        ? _mint
        : (s == DotState.locked
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.transparent);
    final border = done
        ? _mint
        : (s == DotState.missed ? Colors.white : Colors.white.withValues(alpha: 0.25));

    return Container(
      width: _d,
      height: _d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: border, width: 1.6),
      ),
      child: done ? CustomPaint(painter: _CheckPainter(Colors.white)) : null,
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(s.width * 0.28, s.height * 0.52)
      ..lineTo(s.width * 0.44, s.height * 0.68)
      ..lineTo(s.width * 0.74, s.height * 0.34);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) => old.color != color;
}