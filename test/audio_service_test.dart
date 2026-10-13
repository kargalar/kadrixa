import 'package:camerapro/services/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

void main() {
  const builtIn = InputDevice(id: 'built-in', label: 'Telefon Mikrofonu');
  const usb = InputDevice(id: 'usb-2', label: 'USB Mikrofon');
  const devices = <InputDevice>[builtIn, usb];

  test('restores a microphone by its saved id', () {
    final selected = AudioService.resolvePreferredDevice(
      devices: devices,
      savedId: usb.id,
      savedLabel: usb.label,
    );

    expect(selected, usb);
  });

  test('falls back to the saved label when a device id changes', () {
    final selected = AudioService.resolvePreferredDevice(
      devices: devices,
      savedId: 'old-usb-id',
      savedLabel: usb.label,
    );

    expect(selected, usb);
  });

  test('uses the default device when the saved microphone is unavailable', () {
    final selected = AudioService.resolvePreferredDevice(
      devices: devices,
      savedId: 'missing',
      savedLabel: 'Takılı Olmayan Mikrofon',
    );

    expect(selected, builtIn);
  });
}
