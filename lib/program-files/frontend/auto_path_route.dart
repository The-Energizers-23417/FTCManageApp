import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Represents a single movement or wait action in an autonomous path.
class _PathSegment {
  final String name;
  final Offset start;
  final Offset end;
  final double startHeading;
  final double endHeading;
  final double waitMs;

  _PathSegment({
    required this.name,
    required this.start,
    required this.end,
    required this.startHeading,
    required this.endHeading,
    required this.waitMs,
  });

  /// Returns true if this segment is purely a pause without movement.
  bool get isWaitOnly =>
      start == end && startHeading == endHeading && waitMs > 0;
}

/// Helper for managing the timing of a segment during playback animation.
class _PlaybackEntry {
  final _PathSegment segment;
  final double startTime;
  final double endTime;
  final bool isWait;
  final double length;

  const _PlaybackEntry({
    required this.segment,
    required this.startTime,
    required this.endTime,
    required this.isWait,
    required this.length,
  });
}

/// Data model for a saved autonomous path.
class _ViewPath {
  final String id;
  final String name;
  final List<_PathSegment> segments;
  final Color robotColor;
  final Color lineColor;
  final double robotLength;
  final double robotWidth;

  _ViewPath({
    required this.id,
    required this.name,
    required this.segments,
    required this.robotColor,
    required this.lineColor,
    required this.robotLength,
    required this.robotWidth,
  });
}

/// AutoPathRoutePage allows users to view and playback their saved autonomous routes.
class AutoPathRoutePage extends StatefulWidget {
  final String title;
  const AutoPathRoutePage({super.key, this.title = "Autopath Route"});

  @override
  State<AutoPathRoutePage> createState() => _AutoPathRoutePageState();
}

class _AutoPathRoutePageState extends State<AutoPathRoutePage>
    with SingleTickerProviderStateMixin {
  // FTC Field size is typically 144x144 inches.
  static const double _fieldInches = 144.0;

  List<_ViewPath> _paths = [];
  String? _selectedPathId;

  final List<_PathSegment> _segments = [];
  final List<Offset> _pathPoints = [];

  // Current robot pose on the virtual field.
  double _robotFieldX = 56;
  double _robotFieldY = 8;
  double _robotHeadingDeg = 90;

  double _robotLengthInches = 16.0;
  double _robotWidthInches = 16.0;

  Color _robotColor = const Color(0xFF1976D2);
  Color _lineColor = const Color(0xFFFFC107);

  // Animation playback control.
  late final AnimationController _playController;
  bool _isPlaying = false;
  final List<_PlaybackEntry> _playEntries = [];
  double _playTotalTimeSec = 0.0;

  @override
  void initState() {
    super.initState();
    _playController = AnimationController(vsync: this)
      ..addListener(_onPlayTick)
      ..addStatusListener(
            (status) {
          if (status == AnimationStatus.completed ||
              status == AnimationStatus.dismissed) {
            if (!mounted) return;
            setState(() {
              _isPlaying = false;
            });
          }
        },
      );

    _loadPathsFromFirebase();
  }

  @override
  void dispose() {
    _playController.dispose();
    super.dispose();
  }

  /// Synchronizes autonomous paths from the user's Firestore collection.
  Future<void> _loadPathsFromFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('autoPaths')
          .orderBy('createdAt', descending: true)
          .get();

      final List<_ViewPath> loaded = [];

      for (final doc in snap.docs) {
        final data = doc.data();
        final name = (data['name'] ?? 'Unnamed Path') as String;

        final robotLengthVal =
            (data['robotLength'] as num?)?.toDouble() ?? 16.0;
        final robotWidthVal =
            (data['robotWidth'] as num?)?.toDouble() ?? 16.0;

        final segList = (data['segments'] as List<dynamic>? ?? []);
        final newSegments = <_PathSegment>[];

        for (final raw in segList) {
          if (raw is! Map<String, dynamic>) continue;

          final startMap = (raw['start'] as Map<String, dynamic>? ?? {});
          final endMap = (raw['end'] as Map<String, dynamic>? ?? {});

          final sx = (startMap['x'] as num?)?.toDouble() ?? 0;
          final sy = (startMap['y'] as num?)?.toDouble() ?? 0;
          final ex = (endMap['x'] as num?)?.toDouble() ?? 0;
          final ey = (endMap['y'] as num?)?.toDouble() ?? 0;

          final sh = (raw['startHeading'] as num?)?.toDouble() ?? 0;
          final eh = (raw['endHeading'] as num?)?.toDouble() ?? sh;

          double waitMs = 0.0;
          final waitMsField = raw['waitMs'];
          final waitSecField = raw['waitSeconds'];

          if (waitMsField is num) {
            waitMs = waitMsField.toDouble();
          } else if (waitSecField is num) {
            waitMs = waitSecField.toDouble() * 1000.0;
          }

          final segName =
              (raw['name'] as String?) ?? 'Segment ${newSegments.length + 1}';

          newSegments.add(
            _PathSegment(
              name: segName,
              start: Offset(sx, sy),
              end: Offset(ex, ey),
              startHeading: sh,
              endHeading: eh,
              waitMs: waitMs,
            ),
          );
        }

        final robotColorValue = data['robotColor'] as int?;
        final lineColorValue = data['lineColor'] as int?;

        loaded.add(
          _ViewPath(
            id: doc.id,
            name: name,
            segments: newSegments,
            robotColor:
            robotColorValue != null ? Color(robotColorValue) : Colors.blue,
            lineColor:
            lineColorValue != null ? Color(lineColorValue) : Colors.orange,
            robotLength: robotLengthVal,
            robotWidth: robotWidthVal,
          ),
        );
      }

      loaded.sort((a, b) => a.name.compareTo(b.name));

      setState(() {
        _paths = loaded;
      });

      if (_paths.isNotEmpty) {
        _selectPath(_paths.first.id);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading routes: $e')),
      );
    }
  }

  /// Sets the currently active path and prepares it for visualization.
  void _selectPath(String id) {
    final match = _paths.firstWhere((p) => p.id == id, orElse: () => _paths[0]);

    _selectedPathId = match.id;

    _segments
      ..clear()
      ..addAll(match.segments);

    _robotColor = match.robotColor;
    _lineColor = match.lineColor;
    _robotLengthInches = match.robotLength;
    _robotWidthInches = match.robotWidth;

    _rebuildFromSegments();
    _preparePlaybackEntries();
    setState(() {});
  }

  /// Extracts coordinates from segments to build the static path line.
  void _updatePathFromSegments() {
    _pathPoints.clear();
    if (_segments.isEmpty) return;

    _pathPoints.add(_segments.first.start);
    for (final s in _segments) {
      if (!s.isWaitOnly) _pathPoints.add(s.end);
    }
  }

  /// Resets the robot to the starting position of the path.
  void _rebuildFromSegments() {
    _updatePathFromSegments();

    if (_segments.isEmpty) {
      _robotFieldX = 56;
      _robotFieldY = 8;
      _robotHeadingDeg = 90;
      return;
    }

    final first = _segments.first;

    _robotFieldX = first.start.dx;
    _robotFieldY = first.start.dy;
    _robotHeadingDeg = first.startHeading;
  }

  /// Prepares the timeline entries for smooth animation playback.
  void _preparePlaybackEntries() {
    _playEntries.clear();
    _playTotalTimeSec = 0.0;

    if (_segments.isEmpty) return;

    // Movement speed for animation (inches per second).
    const double speed = 40.0;
    double t = 0.0;

    for (final s in _segments) {
      final isWait = s.isWaitOnly;
      final length = (s.end - s.start).distance;
      double dur;

      if (isWait) {
        dur = s.waitMs / 1000.0;
      } else {
        dur = length > 0 ? length / speed : 0.0;
      }

      _playEntries.add(
        _PlaybackEntry(
          segment: s,
          startTime: t,
          endTime: t + dur,
          isWait: isWait,
          length: length,
        ),
      );

      t += dur;
    }

    _playTotalTimeSec = t;

    _playController.stop();
    _playController.reset();

    if (_playTotalTimeSec > 0) {
      _playController.duration =
          Duration(milliseconds: (_playTotalTimeSec * 1000).round());
    }
  }

  /// Updates the robot's pose based on the current playback progress.
  void _onPlayTick() {
    if (_playTotalTimeSec <= 0 || _playEntries.isEmpty) return;

    final tSec = _playController.value * _playTotalTimeSec;

    _PlaybackEntry entry = _playEntries.last;
    for (final e in _playEntries) {
      if (tSec >= e.startTime && tSec <= e.endTime) {
        entry = e;
        break;
      }
    }

    final s = entry.segment;

    Offset pos;
    double heading;

    if (entry.isWait || entry.endTime <= entry.startTime) {
      pos = s.start;
      heading = s.startHeading;
    } else {
      final local =
          (tSec - entry.startTime) / (entry.endTime - entry.startTime);
      pos = Offset(
        s.start.dx + (s.end.dx - s.start.dx) * local,
        s.start.dy + (s.end.dy - s.start.dy) * local,
      );
      heading =
          s.startHeading + (s.endHeading - s.startHeading) * local;
    }

    setState(() {
      _robotFieldX = pos.dx;
      _robotFieldY = pos.dy;
      _robotHeadingDeg = heading;
    });
  }

  /// Starts the path animation.
  void _play() {
    if (_segments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No segments to play')),
      );
      return;
    }

    _preparePlaybackEntries();

    if (_playTotalTimeSec <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Path is too short to play')),
      );
      return;
    }

    final first = _segments.first;
    setState(() {
      _robotFieldX = first.start.dx;
      _robotFieldY = first.start.dy;
      _robotHeadingDeg = first.startHeading;
      _isPlaying = true;
    });

    _playController.stop();
    _playController.reset();
    _playController.forward();
  }

  /// Resets the animation to the beginning.
  void _resetPlayback() {
    _playController.stop();
    _playController.value = 0;
    _isPlaying = false;
    _rebuildFromSegments();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSegments = _segments.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              "View and playback your saved Autopath routes.",
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: "Select route",
                      border: OutlineInputBorder(),
                    ),
                    value: _selectedPathId,
                    items: _paths
                        .map(
                          (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.name),
                      ),
                    )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) _selectPath(value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: "Reload from Firebase",
                  onPressed: _loadPathsFromFirebase,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (hasSegments)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Segments: ${_segments.length}   •   Points: ${_pathPoints.length}   •   Robot: ${_robotLengthInches}\" x ${_robotWidthInches}\"",
                  style: theme.textTheme.bodySmall,
                ),
              ),

            const SizedBox(height: 16),

            // Virtual Field View
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  double fieldSizePx = constraints.maxWidth * 0.9;
                  if (fieldSizePx > constraints.maxHeight) {
                    fieldSizePx = constraints.maxHeight;
                  }

                  final scale = fieldSizePx / _fieldInches;

                  final robotLengthPx = _robotLengthInches * scale;
                  final robotWidthPx = _robotWidthInches * scale;

                  final leftOffset =
                      (constraints.maxWidth - fieldSizePx) / 2;
                  final topOffset =
                      (constraints.maxHeight - fieldSizePx) / 2;

                  final robotCenterX = leftOffset + _robotFieldX * scale;
                  final robotCenterY =
                      topOffset + (_fieldInches - _robotFieldY) * scale;

                  final robotLeft = robotCenterX - robotWidthPx / 2;
                  final robotTop = robotCenterY - robotLengthPx / 2;

                  return Stack(
                    children: [
                      // Field Background and Path
                      Positioned(
                        left: leftOffset,
                        top: topOffset,
                        width: fieldSizePx,
                        height: fieldSizePx,
                        child: Stack(
                          children: [
                            Image.asset(
                              'files/images/decode_background.png',
                              fit: BoxFit.contain,
                              width: fieldSizePx,
                              height: fieldSizePx,
                            ),
                            Container(
                              color: Colors.black.withOpacity(0.12),
                            ),
                            CustomPaint(
                              painter: _PathPainter(
                                points: _pathPoints,
                                fieldInches: _fieldInches,
                                pathColor: _lineColor,
                              ),
                              size: Size(fieldSizePx, fieldSizePx),
                            ),
                          ],
                        ),
                      ),

                      // Animated Robot Marker
                      if (hasSegments)
                        Positioned(
                          left: robotLeft,
                          top: robotTop,
                          child: Transform.rotate(
                            angle: -_robotHeadingDeg * math.pi / 180,
                            child: Container(
                              width: robotWidthPx,
                              height: robotLengthPx,
                              decoration: BoxDecoration(
                                color: _robotColor,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: _robotColor.withOpacity(0.7),
                                  width: 2,
                                ),
                              ),
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: Container(
                                  width: robotWidthPx * 0.25,
                                  height: robotLengthPx * 0.15,
                                  margin: const EdgeInsets.only(top: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Playback Controls
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: hasSegments ? _play : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("Play"),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Slider(
                    value:
                    _playTotalTimeSec == 0 ? 0 : _playController.value,
                    onChanged: (value) {
                      if (!hasSegments || _playTotalTimeSec == 0) return;
                      setState(() {
                        _isPlaying = false;
                        _playController.value = value;
                        _onPlayTick();
                      });
                    },
                  ),
                ),
                IconButton(
                  tooltip: "Reset playback",
                  onPressed: hasSegments ? _resetPlayback : null,
                  icon: const Icon(Icons.restart_alt),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter to draw the static autonomous path on the field.
class _PathPainter extends CustomPainter {
  final List<Offset> points;
  final double fieldInches;
  final Color pathColor;

  _PathPainter({
    required this.points,
    required this.fieldInches,
    required this.pathColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paint = Paint()
      ..color = pathColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final path = Path();

    for (int i = 0; i < points.length; i++) {
      final p = points[i];

      final x = (p.dx / fieldInches) * size.width;
      final y = size.height - (p.dy / fieldInches) * size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PathPainter old) =>
      old.points != points ||
          old.pathColor != pathColor ||
          old.fieldInches != fieldInches;
}
