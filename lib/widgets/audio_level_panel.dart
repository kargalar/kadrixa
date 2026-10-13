import 'dart:math' as math;

import 'package:flutter/material.dart';

enum AudioLevelBand { low, ideal, high }

class AudioLevelScale {
  const AudioLevelScale._();

  static double normalize(double db) {
    final clamped = db.clamp(-60.0, 0.0);
    final linear = (clamped + 60.0) / 60.0;
    return math.pow(linear, 0.55).toDouble();
  }

  static AudioLevelBand bandFor(double db) {
    if (db < -36) return AudioLevelBand.low;
    if (db > -10) return AudioLevelBand.high;
    return AudioLevelBand.ideal;
  }
}

class AudioLevelPanel extends StatelessWidget {
  const AudioLevelPanel({
    super.key,
    required this.amplitudes,
    required this.isRecording,
    required this.microphoneLabel,
    required this.onMicrophoneTap,
    required this.onVisibilityToggle,
    this.compact = false,
  });
  final List<double> amplitudes;
  final bool isRecording;
  final String microphoneLabel;
  final VoidCallback? onMicrophoneTap;
  final VoidCallback onVisibilityToggle;
  final bool compact;
  static const height = 88.0;
  static const compactHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final db = amplitudes.isEmpty ? -60.0 : amplitudes.last;
    final band = AudioLevelScale.bandFor(db);
    final label = switch (band) {
      AudioLevelBand.low => 'LEVEL LOW',
      AudioLevelBand.ideal => 'LEVEL OK',
      AudioLevelBand.high => 'LEVEL HIGH',
    };
    final color = band == AudioLevelBand.high ? colors.error : colors.onSurface;
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    return Container(
      key: const Key('audio_level_panel'),
      height: (compact ? compactHeight : height) * textScale.clamp(1.0, 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 40 * textScale.clamp(1.0, 1.5),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onMicrophoneTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      spacing: 8,
                      children: [
                        Icon(
                          Icons.mic_none_rounded,
                          size: 20,
                          color: colors.onSurfaceVariant,
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                microphoneLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: color,
                                      fontSize: 10,
                                      letterSpacing: 0.6,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  '${db.round()} dB',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: color),
                ),
                IconButton(
                  key: const Key('audio_waveform_hide_button'),
                  onPressed: onVisibilityToggle,
                  tooltip: 'Hide audio waveform',
                  iconSize: 18,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ],
            ),
          ),
          if (!compact)
            Expanded(
              child: RepaintBoundary(
                child: CustomPaint(
                  size: const Size(double.infinity, 24),
                  painter: AudioWaveformPainter(
                    amplitudes: amplitudes,
                    color: isRecording ? colors.error : colors.onSurface,
                    idealBandColor: colors.surfaceContainerHighest,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              key: const Key('audio_peak_meter'),
              value: AudioLevelScale.normalize(db),
              minHeight: 2,
              color: color,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class AudioWaveformPainter extends CustomPainter {
  const AudioWaveformPainter({
    required this.amplitudes,
    required this.color,
    required this.idealBandColor,
  });

  final List<double> amplitudes;
  final Color color;
  final Color idealBandColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty || size.isEmpty) return;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height * 0.18, size.width, size.height * 0.64),
        const Radius.circular(10),
      ),
      Paint()..color = idealBandColor,
    );

    final middle = size.height / 2;
    final maximumHeight = size.height / 2 - 3;
    final widthStep = amplitudes.length == 1
        ? size.width
        : size.width / (amplitudes.length - 1);
    final upper = Path()..moveTo(0, middle);
    final lower = Path()..moveTo(0, middle);

    for (var index = 0; index < amplitudes.length; index++) {
      final x = index * widthStep;
      final height =
          maximumHeight * AudioLevelScale.normalize(amplitudes[index]);
      if (index == 0) {
        upper.moveTo(x, middle - height);
        lower.moveTo(x, middle + height);
      } else {
        upper.lineTo(x, middle - height);
        lower.lineTo(x, middle + height);
      }
    }

    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(upper, stroke);
    canvas.drawPath(lower, stroke);
  }

  @override
  bool shouldRepaint(covariant AudioWaveformPainter oldDelegate) {
    return oldDelegate.amplitudes != amplitudes ||
        oldDelegate.color != color ||
        oldDelegate.idealBandColor != idealBandColor;
  }
}
