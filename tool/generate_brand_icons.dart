import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as image;

const _sourcePath = 'assets/branding/kadrixa-symbol.png';
const _androidResources = 'android/app/src/main/res';
const _iosIcons = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
const _background = (red: 8, green: 9, blue: 11);
const _legacyGlyphFraction = 0.70;
const _adaptiveGlyphFraction = 0.42;
const _adaptiveCanvasSize = 432;

void main() {
  final source = image.decodePng(File(_sourcePath).readAsBytesSync());
  if (source == null || source.numChannels != 4) {
    throw StateError('The launcher symbol must be a transparent PNG.');
  }
  final glyph = _trimTransparentMargins(source);
  _writePng('assets/branding/kadrixa-icon.png', _legacyIcon(glyph, 1024));
  const androidSizes = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  for (final entry in androidSizes.entries) {
    _writePng(
      '$_androidResources/mipmap-${entry.key}/ic_launcher.png',
      _legacyIcon(glyph, entry.value),
    );
  }
  final foreground = _placeGlyph(
    glyph,
    _adaptiveCanvasSize,
    fraction: _adaptiveGlyphFraction,
    transparent: true,
  );
  _writePng(
    '$_androidResources/drawable-nodpi/ic_launcher_foreground.png',
    foreground,
  );
  final monochrome = image.Image.from(foreground);
  for (final pixel in monochrome) {
    pixel
      ..r = 255
      ..g = 255
      ..b = 255;
  }
  _writePng(
    '$_androidResources/drawable-nodpi/ic_launcher_monochrome.png',
    monochrome,
  );

  final catalog =
      jsonDecode(File('$_iosIcons/Contents.json').readAsStringSync())
          as Map<String, dynamic>;
  for (final entry in catalog['images'] as List<dynamic>) {
    final asset = entry as Map<String, dynamic>;
    final points = double.parse((asset['size'] as String).split('x').first);
    final scale = double.parse((asset['scale'] as String).replaceAll('x', ''));
    _writePng(
      '$_iosIcons/${asset['filename']}',
      _legacyIcon(glyph, (points * scale).round()),
    );
  }
  stdout.writeln('Kadrixa launcher icons generated for Android and iOS.');
}

image.Image _trimTransparentMargins(image.Image source) {
  var left = source.width;
  var top = source.height;
  var right = -1;
  var bottom = -1;
  for (final pixel in source) {
    if (pixel.a <= 16) continue;
    left = math.min(left, pixel.x);
    top = math.min(top, pixel.y);
    right = math.max(right, pixel.x);
    bottom = math.max(bottom, pixel.y);
  }
  if (right < left || bottom < top) {
    throw StateError('The launcher symbol is empty.');
  }
  return image.copyCrop(
    source,
    x: left,
    y: top,
    width: right - left + 1,
    height: bottom - top + 1,
  );
}

image.Image _legacyIcon(image.Image glyph, int size) => _placeGlyph(
  glyph,
  size,
  fraction: _legacyGlyphFraction,
  transparent: false,
);

image.Image _placeGlyph(
  image.Image glyph,
  int size, {
  required double fraction,
  required bool transparent,
}) {
  final canvas = image.Image(
    width: size,
    height: size,
    numChannels: transparent ? 4 : 3,
  );
  if (!transparent) {
    image.fill(
      canvas,
      color: image.ColorRgb8(
        _background.red,
        _background.green,
        _background.blue,
      ),
    );
  }
  final scale = size * fraction / math.max(glyph.width, glyph.height);
  final resized = image.copyResize(
    glyph,
    width: (glyph.width * scale).round(),
    height: (glyph.height * scale).round(),
    interpolation: image.Interpolation.average,
  );
  image.compositeImage(
    canvas,
    resized,
    dstX: (size - resized.width) ~/ 2,
    dstY: (size - resized.height) ~/ 2,
  );
  return canvas;
}

void _writePng(String path, image.Image asset) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(image.encodePng(asset));
}
