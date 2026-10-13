import 'package:camerapro/widgets/audio_level_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps microphone dB values to readable bands', () {
    expect(AudioLevelScale.bandFor(-50), AudioLevelBand.low);
    expect(AudioLevelScale.bandFor(-24), AudioLevelBand.ideal);
    expect(AudioLevelScale.bandFor(-6), AudioLevelBand.high);
    expect(AudioLevelScale.normalize(-60), 0);
    expect(AudioLevelScale.normalize(0), 1);
  });

  testWidgets('shows a compact panel with high level and peak meter', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AudioLevelPanel(
            amplitudes: const <double>[-24, -18, -8],
            isRecording: false,
            microphoneLabel: 'USB Mic',
            onMicrophoneTap: () {},
            onVisibilityToggle: () {},
          ),
        ),
      ),
    );

    expect(find.text('LEVEL HIGH'), findsOneWidget);
    expect(find.text('USB Mic'), findsOneWidget);
    expect(find.byKey(const Key('audio_peak_meter')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('audio_level_panel'))).height,
      lessThanOrEqualTo(96),
    );
  });
}
