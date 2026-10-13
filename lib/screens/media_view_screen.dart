import 'package:flutter/material.dart';

import '../constants/media_view_strings.dart';
import '../models/gallery_item.dart';
import '../services/background_media_processing_service.dart';
import '../services/media_sharing_service.dart';
import '../theme/app_theme.dart';
import '../widgets/media_viewer.dart';

class MediaViewScreen extends StatefulWidget {
  const MediaViewScreen({
    super.key,
    required this.items,
    required this.initialItemId,
    this.onDeleteItem,
    this.sharingService,
  });

  final List<GalleryItem> items;
  final String initialItemId;
  final Future<void> Function(GalleryItem item)? onDeleteItem;
  final MediaSharingService? sharingService;

  @override
  State<MediaViewScreen> createState() => _MediaViewScreenState();
}

class _MediaViewScreenState extends State<MediaViewScreen> {
  late final List<GalleryItem> _items;
  late final PageController _pageController;
  late final MediaSharingService _sharingService;
  late final ValueNotifier<String?> _activeItemId;
  final _shareButtonKey = GlobalKey();
  late int _currentIndex;
  bool _photoZoomed = false;
  bool _isSharing = false;
  bool _isDeleting = false;

  bool get _busy => _isSharing || _isDeleting;

  @override
  void initState() {
    super.initState();
    _items = widget.items
        .where((item) => item.status == GalleryItemStatus.success)
        .toList();
    _currentIndex = _items.indexWhere(
      (item) => item.id == widget.initialItemId,
    );
    if (_currentIndex < 0) {
      throw ArgumentError('The initial item must be a completed gallery item.');
    }
    _pageController = PageController(initialPage: _currentIndex);
    _activeItemId = ValueNotifier(widget.initialItemId);
    _sharingService = widget.sharingService ?? MediaSharingService();
  }

  @override
  void dispose() {
    _activeItemId.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    if (index >= _items.length) return;
    setState(() {
      _currentIndex = index;
      _photoZoomed = false;
    });
    _activeItemId.value = _items[index].id;
  }

  Future<void> _shareCurrentItem() async {
    if (_busy || _items.isEmpty) return;
    final item = _items[_currentIndex];
    final box =
        _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _isSharing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await _sharingService.share(item, origin: origin);
    } catch (error) {
      debugPrint('Media sharing failed: $error');
      if (mounted) _showError(MediaViewStrings.shareFailed);
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _deleteCurrentItem() async {
    if (_busy || _items.isEmpty) return;
    final item = _items[_currentIndex];
    setState(() => _isDeleting = true);
    try {
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text(MediaViewStrings.delete),
          content: const Text(MediaViewStrings.confirmDelete),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(MediaViewStrings.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                MediaViewStrings.delete,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      );
      if (shouldDelete != true) return;
      await (widget.onDeleteItem ??
          BackgroundMediaProcessingService.deleteItem)(item);
      if (!mounted) return;
      setState(() {
        final deletedIndex = _items.indexWhere(
          (candidate) => candidate.id == item.id,
        );
        _items.removeAt(deletedIndex);
        if (deletedIndex < _currentIndex) {
          _currentIndex--;
        }
        _currentIndex = _items.isEmpty
            ? 0
            : _currentIndex.clamp(0, _items.length - 1);
        _photoZoomed = false;
      });
      _activeItemId.value = _items.isEmpty ? null : _items[_currentIndex].id;
      if (_items.isEmpty) {
        Navigator.pop(context);
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
      });
    } catch (error) {
      debugPrint('Media deletion failed: $error');
      if (mounted) _showError(MediaViewStrings.deleteFailed);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: Text('${_currentIndex + 1} / ${_items.length}'),
        actions: [
          IconButton(
            key: _shareButtonKey,
            tooltip: MediaViewStrings.share,
            icon: const Icon(Icons.share_outlined),
            onPressed: _busy ? null : _shareCurrentItem,
          ),
          IconButton(
            tooltip: MediaViewStrings.delete,
            icon: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            onPressed: _busy ? null : _deleteCurrentItem,
          ),
        ],
      ),
      body: PageView.builder(
        key: const Key('media_pager'),
        controller: _pageController,
        itemCount: _items.length,
        physics: _busy || _photoZoomed
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        onPageChanged: _onPageChanged,
        findChildIndexCallback: (key) {
          final index = _items.indexWhere((item) => ValueKey(item.id) == key);
          return index < 0 ? null : index;
        },
        itemBuilder: (context, index) {
          final item = _items[index];
          return item.isPhoto
              ? PhotoMediaPage(
                  key: ValueKey(item.id),
                  item: item,
                  onZoomChanged: (zoomed) {
                    if (index == _currentIndex && zoomed != _photoZoomed) {
                      setState(() => _photoZoomed = zoomed);
                    }
                  },
                )
              : VideoMediaPage(
                  key: ValueKey(item.id),
                  item: item,
                  activeItemId: _activeItemId,
                  playbackAllowed: !_busy,
                );
        },
      ),
    );
  }
}
