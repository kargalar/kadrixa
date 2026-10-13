export '../models/gallery_item.dart';
export '../utils/gallery_hero_tag.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gallery_item.dart';
import '../services/background_media_processing_service.dart';
import '../utils/gallery_hero_tag.dart';
import 'media_view_screen.dart';

class GalleryScreen extends StatelessWidget {
  const GalleryScreen({
    super.key,
    required this.itemsNotifier,
    this.onDeleteItem,
  });

  final ValueNotifier<List<GalleryItem>> itemsNotifier;
  final Future<void> Function(GalleryItem item)? onDeleteItem;

  Future<void> _deleteItem(BuildContext context, GalleryItem item) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete item'),
        content: const Text(
          'Permanently delete this item and its local app file?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;

    await _removeItem(item);
  }

  Future<void> _removeItem(GalleryItem item) async {
    await (onDeleteItem ?? BackgroundMediaProcessingService.deleteItem)(item);
    final currentItems = List<GalleryItem>.from(itemsNotifier.value)
      ..removeWhere((candidate) => candidate.id == item.id);
    itemsNotifier.value = currentItems;
  }

  Future<void> _handleTap(BuildContext context, GalleryItem item) async {
    switch (item.status) {
      case GalleryItemStatus.processing:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Media is being processed. Please wait...'),
            duration: Duration(seconds: 1),
          ),
        );
        return;
      case GalleryItemStatus.failed:
        final message =
            item.errorMessage ??
            'An unknown error occurred while processing media.';
        await Clipboard.setData(ClipboardData(text: message));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error message copied to clipboard.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      case GalleryItemStatus.success:
        final viewableItems = itemsNotifier.value.reversed
            .where((candidate) => candidate.status == GalleryItemStatus.success)
            .toList();
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => MediaViewScreen(
              items: viewableItems,
              initialItemId: item.id,
              onDeleteItem: _removeItem,
            ),
          ),
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: const Text('Gallery'),
        elevation: 0,
      ),
      body: ValueListenableBuilder<List<GalleryItem>>(
        valueListenable: itemsNotifier,
        builder: (context, items, _) {
          final reversedItems = List<GalleryItem>.from(items.reversed);
          if (reversedItems.isEmpty) {
            return const _EmptyGallery();
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: reversedItems.length,
            itemBuilder: (context, index) {
              final item = reversedItems[index];
              return _GalleryGridItem(
                item: item,
                onTap: () => _handleTap(context, item),
                onLongPress: () => _deleteItem(context, item),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          Icon(
            Icons.photo_library_outlined,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            size: 64,
          ),
          Text(
            'No media yet',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryGridItem extends StatelessWidget {
  const _GalleryGridItem({
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  final GalleryItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isProcessing = item.status == GalleryItemStatus.processing;
    final isFailed = item.status == GalleryItemStatus.failed;

    return GestureDetector(
      key: ValueKey<String>('gallery-item-${item.id}'),
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isProcessing)
              const _ProcessingTile()
            else if (isFailed)
              const _FailedTile()
            else
              Hero(
                tag: galleryHeroTag(item.id),
                child: _MediaThumbnail(item: item),
              ),
            if (!item.isPhoto && !isProcessing && !isFailed)
              const _VideoBadge(),
          ],
        ),
      ),
    );
  }
}

class _ProcessingTile extends StatelessWidget {
  const _ProcessingTile();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            const CircularProgressIndicator(),
            Text(
              'Processing...',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedTile extends StatelessWidget {
  const _FailedTile();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
              size: 32,
            ),
            Text(
              'Hata',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            Text(
              'Tap to copy',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onErrorContainer.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaThumbnail extends StatelessWidget {
  const _MediaThumbnail({required this.item});

  final GalleryItem item;

  @override
  Widget build(BuildContext context) {
    final thumbnailPath = item.thumbnailPath;
    if (thumbnailPath != null && File(thumbnailPath).existsSync()) {
      return Image.file(
        File(thumbnailPath),
        fit: item.isPhoto ? BoxFit.cover : BoxFit.contain,
      );
    }
    if (item.isPhoto &&
        item.status == GalleryItemStatus.success &&
        File(item.path).existsSync()) {
      return Image.file(File(item.path), fit: BoxFit.cover);
    }
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        item.isPhoto ? Icons.photo : Icons.videocam,
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
        size: 40,
      ),
    );
  }
}

class _VideoBadge extends StatelessWidget {
  const _VideoBadge();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 6,
      right: 6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 2,
            children: [
              Icon(
                Icons.play_arrow,
                color: Theme.of(context).colorScheme.onSurface,
                size: 14,
              ),
              Text(
                'Video',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
