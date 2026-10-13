import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../constants/media_view_strings.dart';
import '../models/gallery_item.dart';
import '../utils/gallery_hero_tag.dart';
import '../theme/app_theme.dart';

class PhotoMediaPage extends StatefulWidget {
  const PhotoMediaPage({
    super.key,
    required this.item,
    required this.onZoomChanged,
  });

  final GalleryItem item;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<PhotoMediaPage> createState() => _PhotoMediaPageState();
}

class _PhotoMediaPageState extends State<PhotoMediaPage> {
  static const maxScale = 4.0;
  static const zoomTolerance = 0.01;
  final _transformationController = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    final zoomed =
        _transformationController.value.getMaxScaleOnAxis() > 1 + zoomTolerance;
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
    widget.onZoomChanged(zoomed);
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.item.path);
    if (!file.existsSync()) {
      return const MediaViewMessage(message: MediaViewStrings.missingFile);
    }
    return Center(
      child: Hero(
        tag: galleryHeroTag(widget.item.id),
        child: InteractiveViewer(
          transformationController: _transformationController,
          minScale: 1,
          maxScale: maxScale,
          panEnabled: _zoomed,
          child: Image.file(file, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class VideoMediaPage extends StatefulWidget {
  const VideoMediaPage({
    super.key,
    required this.item,
    required this.activeItemId,
    required this.playbackAllowed,
  });

  final GalleryItem item;
  final ValueListenable<String?> activeItemId;
  final bool playbackAllowed;

  @override
  State<VideoMediaPage> createState() => _VideoMediaPageState();
}

class _VideoMediaPageState extends State<VideoMediaPage>
    with WidgetsBindingObserver {
  static const controlSize = 64.0;
  static const controlIconSize = 36.0;
  static const progressInset = 20.0;
  VideoPlayerController? _controller;
  bool _showControls = true;
  bool _isPlaying = false;
  String? _error;
  bool get _active => widget.activeItemId.value == widget.item.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.activeItemId.addListener(_onActiveItemChanged);
    if (_active) unawaited(_initializeVideo());
  }

  @override
  void didUpdateWidget(VideoMediaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.playbackAllowed) {
      unawaited(_controller?.pause());
    }
  }

  void _onActiveItemChanged() {
    if (_active) {
      unawaited(_initializeVideo());
    } else {
      _releaseController();
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_controller?.pause());
  }

  Future<void> _initializeVideo() async {
    _error = null;
    _showControls = true;
    final file = File(widget.item.path);
    if (!file.existsSync()) {
      _error = MediaViewStrings.missingFile;
      return;
    }
    final controller = VideoPlayerController.file(file);
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted || _controller != controller) return;
      controller.addListener(_onVideoChanged);
      setState(() {});
    } catch (error) {
      if (!mounted || _controller != controller) return;
      debugPrint('Video initialization failed: $error');
      setState(() => _error = MediaViewStrings.videoFailed);
    }
  }

  void _onVideoChanged() {
    final value = _controller?.value;
    if (!mounted || value == null) return;
    if (value.hasError && _error == null) {
      setState(() => _error = MediaViewStrings.videoFailed);
    } else if (value.isPlaying != _isPlaying) {
      setState(() => _isPlaying = value.isPlaying);
    }
  }

  void _releaseController() {
    final controller = _controller;
    _controller = null;
    _isPlaying = false;
    if (controller == null) return;
    controller.removeListener(_onVideoChanged);
    unawaited(controller.pause());
    unawaited(controller.dispose());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.activeItemId.removeListener(_onActiveItemChanged);
    _releaseController();
    super.dispose();
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !widget.playbackAllowed) return;
    unawaited(
      controller.value.isPlaying ? controller.pause() : controller.play(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) return MediaViewMessage(message: _error!);
    if (!_active) return const SizedBox.expand();
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _showControls = !_showControls),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: Hero(
              tag: galleryHeroTag(widget.item.id),
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
          ),
          if (_showControls)
            SizedBox.square(
              dimension: controlSize,
              child: IconButton.filledTonal(
                tooltip: _isPlaying
                    ? MediaViewStrings.pause
                    : MediaViewStrings.play,
                onPressed: widget.playbackAllowed ? _togglePlayPause : null,
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                  ),
                ),
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  size: controlIconSize,
                ),
              ),
            ),
          if (_showControls)
            Positioned(
              bottom: progressInset,
              left: progressInset,
              right: progressInset,
              child: SafeArea(
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: widget.playbackAllowed,
                  colors: VideoProgressColors(
                    playedColor: Theme.of(context).colorScheme.primary,
                    bufferedColor: Theme.of(context).colorScheme.outline,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MediaViewMessage extends StatelessWidget {
  const MediaViewMessage({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
