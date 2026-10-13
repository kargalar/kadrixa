import 'package:camerapro/screens/gallery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('viewer skips unfinished items and deletes the swiped-to item', (
    tester,
  ) async {
    final removed = <String>[];
    final notifier = ValueNotifier<List<GalleryItem>>([
      GalleryItem(id: 'a', path: '/missing/a.jpg', isPhoto: true),
      GalleryItem(
        id: 'processing',
        path: '',
        isPhoto: false,
        status: GalleryItemStatus.processing,
      ),
      GalleryItem(id: 'b', path: '/missing/b.jpg', isPhoto: true),
      GalleryItem(
        id: 'failed',
        path: '',
        isPhoto: false,
        status: GalleryItemStatus.failed,
      ),
      GalleryItem(id: 'c', path: '/missing/c.jpg', isPhoto: true),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: GalleryScreen(
          itemsNotifier: notifier,
          onDeleteItem: (item) async => removed.add(item.id),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('gallery-item-c')));
    // The underlying gallery still has an in-progress spinner.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('media_pager')),
      const Offset(-600, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(removed, ['b']);
    expect(notifier.value.map((item) => item.id), [
      'a',
      'processing',
      'failed',
      'c',
    ]);
    expect(find.text('2 / 2'), findsOneWidget);
    for (var remaining = 2; remaining > 0; remaining--) {
      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('Gallery'), findsOneWidget);
    expect(notifier.value.map((item) => item.id), ['processing', 'failed']);
    expect(removed, ['b', 'a', 'c']);
    await tester.pumpWidget(const SizedBox());
    notifier.dispose();
  });

  testWidgets('failed item copies its stored error message when tapped', (
    tester,
  ) async {
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText =
                (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
          }
          return null;
        });
    final notifier = ValueNotifier<List<GalleryItem>>(<GalleryItem>[
      GalleryItem(
        id: 'failed',
        path: '',
        isPhoto: false,
        status: GalleryItemStatus.failed,
        errorMessage: 'FFmpeg return code: 1',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: GalleryScreen(itemsNotifier: notifier)),
    );
    await tester.tap(find.byKey(const ValueKey('gallery-item-failed')));
    await tester.pump();

    expect(clipboardText, 'FFmpeg return code: 1');
    expect(find.text('Error message copied to clipboard.'), findsOneWidget);
  });
}
