import 'package:flutter/material.dart';

class TimeburstSettings {
  final double intervalSeconds;
  final int totalDurationSeconds;

  TimeburstSettings({
    required this.intervalSeconds,
    required this.totalDurationSeconds,
  });

  int get totalPhotos => totalDurationSeconds == -1
      ? -1
      : (totalDurationSeconds / intervalSeconds).floor();

  // Assuming 30 fps for the final video
  double get estimatedVideoDuration =>
      totalPhotos == -1 ? -1.0 : totalPhotos / 30.0;
}

class TimeburstSettingsDialog extends StatefulWidget {
  final TimeburstSettings initialSettings;
  final ValueChanged<TimeburstSettings> onApply;

  const TimeburstSettingsDialog({
    super.key,
    required this.initialSettings,
    required this.onApply,
  });

  @override
  State<TimeburstSettingsDialog> createState() =>
      _TimeburstSettingsDialogState();
}

class _TimeburstSettingsDialogState extends State<TimeburstSettingsDialog> {
  late double _selectedInterval;
  late int _selectedDuration;

  final List<double> _intervals = [0.5, 1.0, 2.0, 3.0, 5.0, 10.0];
  final List<int> _durations = [
    60, // 1m
    300, // 5m
    600, // 10m
    900, // 15m
    1800, // 30m
    3600, // 1sa
    7200, // 2sa
    18000, // 5sa
    36000, // 10sa
    86400, // 24sa
    -1, // Durdurulana kadar
  ];

  @override
  void initState() {
    super.initState();
    _selectedInterval = widget.initialSettings.intervalSeconds;
    _selectedDuration = widget.initialSettings.totalDurationSeconds;
  }

  String _formatDuration(int seconds) {
    if (seconds == -1) return 'Unlimited';
    if (seconds < 60) return '$seconds sn';
    if (seconds < 3600) {
      final m = seconds ~/ 60;
      return '$m dk';
    }
    final h = seconds ~/ 3600;
    return '$h sa';
  }

  String _formatInterval(double interval) {
    if (interval == interval.roundToDouble()) {
      return '${interval.toInt()}s';
    }
    return '${interval}s';
  }

  String _formatDetailedDuration(double totalSeconds) {
    if (totalSeconds <= 0) return "0 sn";
    if (totalSeconds < 60) {
      return "${totalSeconds.toStringAsFixed(1).replaceAll('.0', '')} sn";
    }

    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    double seconds = totalSeconds % 60;

    List<String> parts = [];
    if (hours > 0) parts.add("$hours sa");
    if (minutes > 0) parts.add("$minutes dk");
    if (seconds > 0) {
      String secStr = seconds.toStringAsFixed(1).replaceAll('.0', '');
      parts.add("$secStr sn");
    }

    return parts.join(" ");
  }

  @override
  Widget build(BuildContext context) {
    final settings = TimeburstSettings(
      intervalSeconds: _selectedInterval,
      totalDurationSeconds: _selectedDuration,
    );

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "TIMEBURST AYARLARI",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          Text(
            "Capture interval",
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _intervals.map((interval) {
                final isSelected = _selectedInterval == interval;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(_formatInterval(interval)),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedInterval = interval;
                        });
                      }
                    },
                    selectedColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          Text(
            "Total capture time",
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _durations.map((duration) {
                final isSelected = _selectedDuration == duration;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(_formatDuration(duration)),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedDuration = duration;
                        });
                      }
                    },
                    selectedColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 32),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Estimated video duration",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      settings.estimatedVideoDuration == -1.0
                          ? "Unlimited"
                          : _formatDetailedDuration(
                              settings.estimatedVideoDuration,
                            ),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "Total photos",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      settings.totalPhotos == -1
                          ? "Unlimited"
                          : "${settings.totalPhotos} Kare",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                widget.onApply(settings);
                Navigator.pop(context);
              },
              child: const Text("UYGULA"),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
