# Gallery navigation and sharing

The media viewer opens at the tapped item and follows the gallery's display
order (newest first). Processing and failed entries are excluded from paging.
Swipe left for the next item and right for the previous one. When a photo is
zoomed, horizontal gestures pan that photo; returning to normal size enables
page swipes again.

Only the active video owns an initialized player. An active-item notifier stops
and disposes the previous player even if Flutter retains its offscreen page.
Sharing, delete confirmation, and application backgrounding pause playback.

The share action opens the system share sheet with the current JPEG or MP4,
including its MIME type and a popover origin for iPad. It validates that the
file exists and is not empty. Dismissal leaves the media viewer open. No app or
recipient is selected automatically. The implementation uses
[share_plus file sharing](https://pub.dev/packages/share_plus).

Deletion targets the selected item's ID and updates the same gallery notifier.
The viewer continues at the next remaining item, or the previous item at the
end of the list. Deleting the last viewable item returns to the gallery.

Widget tests cover bidirectional paging, zoom interaction, photo/video sharing,
playback shutdown, leaving a video while it initializes, missing files, and
deleting after swiping. A gallery integration test checks display order, skipped
unfinished items, correct removal, and navigation after the final deletion.
