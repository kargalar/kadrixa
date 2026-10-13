import 'dart:async';
import 'dart:io';

import 'package:camerapro/constants/media_view_strings.dart';
import 'package:camerapro/models/gallery_item.dart';
import 'package:camerapro/screens/media_view_screen.dart';
import 'package:camerapro/services/media_sharing_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class TrackedSharingService extends MediaSharingService {
  final finished = Completer<void>();

  @override
  Future<void> share(GalleryItem item, {required Rect origin}) async {
    try {
      await super.share(item, origin: origin);
    } finally {
      finished.complete();
    }
  }
}

class FakeViewerVideoPlatform extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final playing = <int>{};
  final disposed = <int>{};
  bool delayInitialization = false;
  int nextId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = nextId++;
    streams[id] = StreamController<VideoEvent>();
    if (!delayInitialization) initialize(id);
    return id;
  }

  void initialize(int id) {
    streams[id]!.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 10),
        size: const Size(640, 480),
      ),
    );
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    playing.remove(playerId);
    disposed.add(playerId);
  }

  @override
  Future<void> play(int playerId) async => playing.add(playerId);

  @override
  Future<void> pause(int playerId) async => playing.remove(playerId);

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => SizedBox(key: ValueKey('player-$playerId'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  late Directory directory;
  late List<GalleryItem> items;
  late FakeViewerVideoPlatform videos;
  late VideoPlayerPlatform previousVideoPlatform;
  final shareCalls = <MethodCall>[];
  late TrackedSharingService sharingService;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('media_viewer_');
    final bytes = img.encodeJpg(img.Image(width: 640, height: 480));
    items = List.generate(3, (index) {
      final file = File('${directory.path}/photo-$index.jpg')
        ..writeAsBytesSync(bytes);
      return GalleryItem(id: '$index', path: file.path, isPhoto: true);
    });
    previousVideoPlatform = VideoPlayerPlatform.instance;
    videos = FakeViewerVideoPlatform();
    VideoPlayerPlatform.instance = videos;
    shareCalls.clear();
    sharingService = TrackedSharingService();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
          shareCalls.add(call);
          return 'dev.fluttercommunity.plus/share/dismissed';
        });
  });

  tearDown(() async {
    VideoPlayerPlatform.instance = previousVideoPlatform;
    for (final stream in videos.streams.values) {
      await stream.close();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null);
    directory.deleteSync(recursive: true);
  });

  Future<void> precachePhotos(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox).first);
    await tester.runAsync(() async {
      for (final item in items.where(
        (item) => item.isPhoto && File(item.path).existsSync(),
      )) {
        await precacheImage(FileImage(File(item.path)), context);
      }
    });
  }

  Future<void> pumpViewer(WidgetTester tester, {String initialId = '0'}) async {
    await precachePhotos(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaViewScreen(
          items: items,
          initialItemId: initialId,
          sharingService: sharingService,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> swipe(WidgetTester tester, double direction) async {
    await tester.drag(
      find.byKey(const Key('media_pager')),
      Offset(direction * 600, 0),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shareCurrent(WidgetTester tester) async {
    await tester.runAsync(
      () => tester.tap(find.byTooltip(MediaViewStrings.share)),
    );
    await tester.pump();
    await tester.runAsync(() => sharingService.finished.future);
    await tester.pumpAndSettle();
  }

  testWidgets('opens selected item and swipes both ways over the photo', (
    tester,
  ) async {
    await pumpViewer(tester, initialId: '1');
    expect(find.text('2 / 3'), findsOneWidget);
    await swipe(tester, -1);
    expect(find.text('3 / 3'), findsOneWidget);
    await swipe(tester, 1);
    await swipe(tester, 1);
    expect(find.text('1 / 3'), findsOneWidget);
    await swipe(tester, 1);
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('zoom pans the photo until it returns to normal size', (
    tester,
  ) async {
    await pumpViewer(tester);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer).first,
    );
    viewer.transformationController!.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pump();
    await swipe(tester, -1);
    expect(find.text('1 / 3'), findsOneWidget);
    viewer.transformationController!.value = Matrix4.identity();
    await tester.pump();
    await swipe(tester, -1);
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'shares the currently visible photo with a valid popover origin',
    (tester) async {
      await pumpViewer(tester);
      await swipe(tester, -1);
      await shareCurrent(tester);
      expect(shareCalls, hasLength(1));
      final arguments = shareCalls.single.arguments as Map;
      expect(arguments['paths'], [items[1].path]);
      expect(arguments['mimeTypes'], ['image/jpeg']);
      expect(arguments['originWidth'], greaterThan(0));
      expect(arguments['originHeight'], greaterThan(0));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('stops the previous video and shares the selected video', (
    tester,
  ) async {
    final file = File('${directory.path}/clip.mp4')
      ..writeAsBytesSync([1, 2, 3]);
    items[0] = GalleryItem(id: 'video', path: file.path, isPhoto: false);
    await pumpViewer(tester, initialId: 'video');
    await tester.tap(find.byTooltip(MediaViewStrings.play));
    await tester.pump();
    expect(videos.playing, {0});
    await shareCurrent(tester);
    expect(videos.playing, isEmpty);
    expect((shareCalls.single.arguments as Map)['mimeTypes'], ['video/mp4']);
    expect((shareCalls.single.arguments as Map)['paths'], [file.path]);
    await tester.tap(find.byTooltip(MediaViewStrings.play));
    await tester.pump();
    await swipe(tester, -1);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(videos.playing, isEmpty);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(videos.disposed, contains(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving a video during initialization disposes it safely', (
    tester,
  ) async {
    final file = File('${directory.path}/slow.mp4')..writeAsBytesSync([1]);
    items[0] = GalleryItem(id: 'slow', path: file.path, isPhoto: false);
    videos.delayInitialization = true;
    await precachePhotos(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaViewScreen(items: items, initialItemId: 'slow'),
      ),
    );
    await tester.pump();
    await tester.drag(
      find.byKey(const Key('media_pager')),
      const Offset(-600, 0),
    );
    await tester.pump(const Duration(seconds: 1));
    videos.initialize(0);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(videos.disposed, contains(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('deletes the swiped-to item and keeps browsing remaining items', (
    tester,
  ) async {
    final deleted = <String>[];
    await precachePhotos(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaViewScreen(
          items: items,
          initialItemId: '0',
          onDeleteItem: (item) async => deleted.add(item.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await swipe(tester, -1);
    await tester.tap(find.byTooltip(MediaViewStrings.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, MediaViewStrings.delete));
    await tester.pumpAndSettle();
    expect(deleted, ['1']);
    expect(find.text('2 / 2'), findsOneWidget);
    await swipe(tester, 1);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'missing file reports a share error without invoking the share sheet',
    (tester) async {
      File(items.first.path).deleteSync();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaViewScreen(
            items: items,
            initialItemId: '0',
            sharingService: sharingService,
          ),
        ),
      );
      await shareCurrent(tester);
      expect(shareCalls, isEmpty);
      expect(find.text(MediaViewStrings.shareFailed), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
