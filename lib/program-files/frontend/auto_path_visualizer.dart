import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

/// Units for robot dimensions.
enum RobotUnit { inch, cm }

/// Represents a segment of an autonomous path, including movement and pauses.
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

  /// True if the segment represents only a pause at a fixed location.
  bool get isWaitOnly =>
      start == end && startHeading == endHeading && waitMs > 0;
}

/// Metadata for paths saved in Firestore.
class _SavedPathMeta {
  final String id;
  final String name;

  _SavedPathMeta(this.id, this.name);
}

/// Represents a robot's 2D pose (position and orientation).
class _Pose {
  final double x;
  final double y;
  final double heading;

  const _Pose(this.x, this.y, this.heading);
}

/// Helper for playback timing of path segments.
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

/// AutoPathVisualizerPage provides a tool to design, visualize, and simulate autonomous paths.
/// Paths can be saved to Firestore and exported as text or code snippets.
class AutoPathVisualizerPage extends StatefulWidget {
  const AutoPathVisualizerPage({super.key});

  @override
  State<AutoPathVisualizerPage> createState() =>
      _AutoPathVisualizerPageState();
}

class _AutoPathVisualizerPageState extends State<AutoPathVisualizerPage>
    with SingleTickerProviderStateMixin {
  // Input controllers for robot and path parameters.
  final TextEditingController _robotLengthController =
  TextEditingController(text: '16');
  final TextEditingController _robotWidthController =
  TextEditingController(text: '16');

  final TextEditingController _startXController =
  TextEditingController(text: '56');
  final TextEditingController _startYController =
  TextEditingController(text: '8');

  final TextEditingController _endXController =
  TextEditingController(text: '56');
  final TextEditingController _endYController =
  TextEditingController(text: '36');

  final TextEditingController _startHeadingController =
  TextEditingController(text: '90');
  final TextEditingController _endHeadingController =
  TextEditingController(text: '180');

  final TextEditingController _pathNameController =
  TextEditingController(text: 'Path 1');

  final TextEditingController _segmentNameController =
  TextEditingController(text: 'Segment 1');
  int _segmentNameCounter = 1;

  RobotUnit _robotUnit = RobotUnit.inch;

  // Current visual robot state on the field.
  double _robotFieldX = 56;
  double _robotFieldY = 8;
  double _robotHeadingDeg = 90;

  final List<Offset> _pathPoints = [];
  final List<_PathSegment> _segments = [];

  final List<_SavedPathMeta> _savedPaths = [];
  String? _selectedPathId;

  Color _robotColor = const Color(0xFF1976D2);
  Color _lineColor = const Color(0xFFFFC107);

  static const double _fieldInches = 144.0;

  // Animation controller for path playback.
  late final AnimationController _playController;
  bool _isPlaying = false;
  final List<_PlaybackEntry> _playEntries = [];
  double _playTotalTimeSec = 0.0;

  @override
  void initState() {
    super.initState();
    _loadSavedPaths();
    _playController = AnimationController(vsync: this)
      ..addListener(_onPlayTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          if (mounted) {
            setState(() {
              _isPlaying = false;
              _playController.value = 0.0;
            });
          } else {
            _isPlaying = false;
            _playController.value = 0.0;
          }
        }
      });
  }

  @override
  void dispose() {
    _playController.dispose();
    _robotLengthController.dispose();
    _robotWidthController.dispose();
    _startXController.dispose();
    _startYController.dispose();
    _endXController.dispose();
    _endYController.dispose();
    _startHeadingController.dispose();
    _endHeadingController.dispose();
    _pathNameController.dispose();
    _segmentNameController.dispose();
    super.dispose();
  }

  /// Helper to get the robot length in inches regardless of selected unit.
  double _robotLengthInInches() {
    final raw = double.tryParse(_robotLengthController.text) ?? 16;
    if (_robotUnit == RobotUnit.inch) return raw;
    return raw / 2.54;
  }

  /// Increments and returns the default segment name.
  String _consumeSegmentName() {
    final raw = _segmentNameController.text.trim();
    final name = raw.isEmpty ? 'Segment $_segmentNameCounter' : raw;
    _segmentNameCounter++;
    _segmentNameController.text = 'Segment $_segmentNameCounter';
    return name;
  }

  void _resetSegmentNameCounter() {
    _segmentNameCounter = 1;
    _segmentNameController.text = 'Segment 1';
  }

  /// Rebuilds the list of coordinates used to draw the path line on the field.
  void _updatePathFromSegments({Offset? previewEnd}) {
    _pathPoints.clear();

    if (_segments.isEmpty) {
      if (previewEnd != null) {
        final sx = double.tryParse(_startXController.text) ?? _robotFieldX;
        final sy = double.tryParse(_startYController.text) ?? _robotFieldY;
        final start = Offset(
          sx.clamp(0.0, _fieldInches),
          sy.clamp(0.0, _fieldInches),
        );
        _pathPoints
          ..add(start)
          ..add(previewEnd);
      }
      return;
    }

    _pathPoints.add(_segments.first.start);
    for (final s in _segments) {
      if (!s.isWaitOnly) {
        _pathPoints.add(s.end);
      }
    }

    if (previewEnd != null) {
      _pathPoints.add(previewEnd);
    }
  }

  /// Adds a new movement segment to the path based on the current UI fields.
  void _addLineFromFields() {
    final sx = double.tryParse(_startXController.text) ?? _robotFieldX;
    final sy = double.tryParse(_startYController.text) ?? _robotFieldY;
    final ex = double.tryParse(_endXController.text) ?? _robotFieldX;
    final ey = double.tryParse(_endYController.text) ?? _robotFieldY;

    final startHeading =
        double.tryParse(_startHeadingController.text) ?? _robotHeadingDeg;
    final endHeading =
        double.tryParse(_endHeadingController.text) ?? startHeading;
    const double waitMs = 0.0;

    final name = _consumeSegmentName();

    final start = Offset(
      sx.clamp(0.0, _fieldInches),
      sy.clamp(0.0, _fieldInches),
    );
    final end = Offset(
      ex.clamp(0.0, _fieldInches),
      ey.clamp(0.0, _fieldInches),
    );

    setState(() {
      _segments.add(_PathSegment(
        name: name,
        start: start,
        end: end,
        startHeading: startHeading,
        endHeading: endHeading,
        waitMs: waitMs,
      ));

      _robotFieldX = end.dx;
      _robotFieldY = end.dy;
      _robotHeadingDeg = endHeading;

      _startXController.text = end.dx.toStringAsFixed(3);
      _startYController.text = end.dy.toStringAsFixed(3);
      _startHeadingController.text = endHeading.toStringAsFixed(0);

      _updatePathFromSegments();
    });
  }

  /// Opens a dialog to add a wait (pause) segment at the robot's current position.
  Future<void> _addWaitAtCurrentRobotPosition() async {
    final TextEditingController waitController =
    TextEditingController(text: '1000');

    final millis = await showDialog<double?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add wait'),
          content: SizedBox(
            width: 260,
            child: TextField(
              controller: waitController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: false,
              ),
              decoration: const InputDecoration(
                labelText: 'Wait time (ms)',
              ),
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(null),
            ),
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                final v = double.tryParse(waitController.text) ?? 0.0;
                Navigator.of(context).pop(v <= 0 ? null : v);
              },
            ),
          ],
        );
      },
    );

    if (millis == null || !mounted) return;

    final pos = Offset(_robotFieldX, _robotFieldY);
    final heading = _robotHeadingDeg;
    final name = _consumeSegmentName();

    setState(() {
      _segments.add(
        _PathSegment(
          name: name,
          start: pos,
          end: pos,
          startHeading: heading,
          endHeading: heading,
          waitMs: millis,
        ),
      );
      _updatePathFromSegments();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
        Text('Added wait of ${millis.toStringAsFixed(0)} ms at current pose'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Clears the current path and resets parameters to defaults.
  void _resetPath() {
    setState(() {
      _segments.clear();
      _pathPoints.clear();

      _robotFieldX = 56;
      _robotFieldY = 8;
      _robotHeadingDeg = 90;

      _startXController.text = '56';
      _startYController.text = '8';
      _endXController.text = '56';
      _endYController.text = '36';
      _startHeadingController.text = '90';
      _endHeadingController.text = '180';

      _robotColor = const Color(0xFF1976D2);
      _lineColor = const Color(0xFFFFC107);

      _resetSegmentNameCounter();
    });
  }

  /// Removes the most recently added segment.
  void _undoLastSegment() {
    if (_segments.isEmpty) return;
    setState(() {
      _segments.removeLast();
      _rebuildFromSegments();
      _segmentNameCounter = _segments.length + 1;
      _segmentNameController.text = 'Segment $_segmentNameCounter';
    });
  }

  /// Synchronizes UI state based on the current segments in the path.
  void _rebuildFromSegments() {
    if (_segments.isEmpty) {
      _pathPoints.clear();
      return;
    }

    _updatePathFromSegments();

    final last = _segments.last;

    _robotFieldX = last.end.dx;
    _robotFieldY = last.end.dy;
    _robotHeadingDeg = last.endHeading;

    _endXController.text = last.end.dx.toStringAsFixed(3);
    _endYController.text = last.end.dy.toStringAsFixed(3);
    _endHeadingController.text = last.endHeading.toStringAsFixed(0);

    _startXController.text = last.end.dx.toStringAsFixed(3);
    _startYController.text = last.end.dy.toStringAsFixed(3);
    _startHeadingController.text = last.endHeading.toStringAsFixed(0);
  }

  /// Generates a human-readable summary and Java-like code snippets for the path.
  String _buildRouteText() {
    _updatePathFromSegments();

    final buffer = StringBuffer();

    buffer.writeln('Polyline points (X,Y in inches):');
    for (int i = 0; i < _pathPoints.length; i++) {
      final p = _pathPoints[i];
      buffer.writeln(
        '${i + 1}: ${p.dx.toStringAsFixed(3)}, ${p.dy.toStringAsFixed(3)}',
      );
    }
    buffer.writeln('');

    buffer.writeln('Segments (with names):');
    if (_segments.isEmpty) {
      buffer.writeln('  <no segments>');
    } else {
      for (int i = 0; i < _segments.length; i++) {
        final s = _segments[i];
        final idx = i + 1;
        if (s.isWaitOnly) {
          buffer.writeln(
            '$idx. ${s.name} : WAIT ${s.waitMs.toStringAsFixed(0)} ms at '
                '(${s.start.dx.toStringAsFixed(3)}, '
                '${s.start.dy.toStringAsFixed(3)}, '
                '${s.startHeading.toStringAsFixed(1)}°)',
          );
        } else {
          buffer.writeln(
            '$idx. ${s.name} : '
                '(${s.start.dx.toStringAsFixed(3)}, '
                '${s.start.dy.toStringAsFixed(3)}, '
                '${s.startHeading.toStringAsFixed(1)}°)  ->  '
                '(${s.end.dx.toStringAsFixed(3)}, '
                '${s.end.dy.toStringAsFixed(3)}, '
                '${s.endHeading.toStringAsFixed(1)}°)',
          );
        }
      }
    }
    buffer.writeln('');

    buffer.writeln('Generated pose code:');
    final poses = _collectUniquePoses();
    for (int i = 0; i < poses.length; i++) {
      final p = poses[i];
      final name = 'pose${i + 1}';
      buffer.writeln(
        'pose $name = new pose(${p.x.toStringAsFixed(3)}, '
            '${p.y.toStringAsFixed(3)}, '
            '${p.heading.toStringAsFixed(1)});',
      );
    }

    return buffer.toString();
  }

  /// Extracts all unique poses found in the path segments.
  List<_Pose> _collectUniquePoses() {
    final List<_Pose> result = [];

    bool exists(_Pose p) {
      return result.any((e) =>
      (e.x - p.x).abs() < 1e-3 &&
          (e.y - p.y).abs() < 1e-3 &&
          (e.heading - p.heading).abs() < 1e-2);
    }

    for (final s in _segments) {
      final startPose = _Pose(s.start.dx, s.start.dy, s.startHeading);
      if (!exists(startPose)) result.add(startPose);

      final endPose = _Pose(s.end.dx, s.end.dy, s.endHeading);
      if (!exists(endPose)) result.add(endPose);
    }

    if (result.isEmpty) {
      result.add(_Pose(_robotFieldX, _robotFieldY, _robotHeadingDeg));
    }

    return result;
  }

  /// Copies the generated route information to the device clipboard.
  Future<void> _copyRouteToClipboard() async {
    final text = _buildRouteText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Route copied to clipboard')),
    );
  }

  /// Displays the generated path summary in a scrollable dialog.
  void _showRouteTextDialog() {
    final text = _buildRouteText();
    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Route TXT export'),
          content: SizedBox(
            width: 500,
            height: 400,
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Route text copied to clipboard'),
                  ),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy'),
            ),
          ],
        );
      },
    );
  }

  /// Loads the list of saved autonomous paths from Firestore.
  Future<void> _loadSavedPaths() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('autoPaths')
          .orderBy('createdAt', descending: true)
          .get();

      setState(() {
        _savedPaths
          ..clear()
          ..addAll(snap.docs.map((doc) {
            final data = doc.data();
            final name = (data['name'] ?? 'Unnamed path') as String;
            return _SavedPathMeta(doc.id, name);
          }));
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading saved paths: $e')),
      );
    }
  }

  /// Saves or updates the current path configuration in Firestore.
  Future<void> _saveCurrentPathToFirebase() async {
    if (_segments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No segments to save')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not logged in')),
      );
      return;
    }

    final name = _pathNameController.text.trim().isEmpty
        ? 'Unnamed path'
        : _pathNameController.text.trim();

    final double robotLength =
        double.tryParse(_robotLengthController.text) ?? 16.0;

    final double robotWidth =
        double.tryParse(_robotWidthController.text) ?? 16.0;

    final segmentsData = _segments.map((s) {
      return {
        'name': s.name,
        'start': {'x': s.start.dx, 'y': s.start.dy},
        'end': {'x': s.end.dx, 'y': s.end.dy},
        'startHeading': s.startHeading,
        'endHeading': s.endHeading,
        'waitMs': s.waitMs,
      };
    }).toList();

    final colRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('autoPaths');

    try {
      String? docId = _selectedPathId;

      final mapToSave = {
        'name': name,
        'segments': segmentsData,
        'robotColor': _robotColor.value,
        'lineColor': _lineColor.value,
        'robotLength': robotLength,
        'robotWidth': robotWidth,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (docId != null) {
        await colRef.doc(docId).update(mapToSave);
      } else {
        final newDoc = await colRef.add({
          ...mapToSave,
          'createdAt': FieldValue.serverTimestamp(),
        });
        docId = newDoc.id;
        _selectedPathId = docId;
      }

      await _loadSavedPaths();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Path saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving path: $e')),
      );
    }
  }

  /// Fetches a specific path configuration from Firestore and hydrates the state.
  Future<void> _loadPathById(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('autoPaths')
          .doc(id)
          .get();

      if (!doc.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Path not found')),
        );
        return;
      }

      final data = doc.data()!;
      final name = (data['name'] ?? 'Unnamed path') as String;
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
        final dynamic waitMsField = raw['waitMs'];
        final dynamic waitSecField = raw['waitSeconds'];
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

      setState(() {
        _pathNameController.text = name;
        _segments
          ..clear()
          ..addAll(newSegments);
        _selectedPathId = id;

        _robotColor = robotColorValue != null
            ? Color(robotColorValue)
            : const Color(0xFF1976D2);
        _lineColor = lineColorValue != null
            ? Color(lineColorValue)
            : const Color(0xFFFFC107);

        _rebuildFromSegments();

        _segmentNameCounter = _segments.length + 1;
        _segmentNameController.text = 'Segment $_segmentNameCounter';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading path: $e')),
      );
    }
  }

  /// Prepares the timeline entries for path playback animation.
  void _preparePlaybackEntries() {
    _playEntries.clear();
    _playTotalTimeSec = 0.0;

    if (_segments.isEmpty) return;

    const double speedInchesPerSec = 20.0;
    const double interSegmentPauseSec = 0.20;

    double tCursor = 0.0;

    for (int i = 0; i < _segments.length; i++) {
      final s = _segments[i];
      final isWait = s.isWaitOnly;
      double length = (s.end - s.start).distance;
      double dur;

      if (isWait) {
        dur = (s.waitMs > 0) ? s.waitMs / 1000.0 : 0.0;
        length = 0.0;
      } else {
        if (length <= 0) {
          dur = 0.0;
        } else {
          dur = length / speedInchesPerSec;
        }
      }

      final entry = _PlaybackEntry(
        segment: s,
        startTime: tCursor,
        endTime: tCursor + dur,
        isWait: isWait,
        length: length,
      );
      _playEntries.add(entry);
      tCursor += dur;

      // Add a brief artificial pause between movement segments for realism.
      if (!isWait && i < _segments.length - 1) {
        final pauseSeg = _PathSegment(
          name: '${s.name}_pause',
          start: s.end,
          end: s.end,
          startHeading: s.endHeading,
          endHeading: s.endHeading,
          waitMs: interSegmentPauseSec * 1000.0,
        );

        final pauseEntry = _PlaybackEntry(
          segment: pauseSeg,
          startTime: tCursor,
          endTime: tCursor + interSegmentPauseSec,
          isWait: true,
          length: 0.0,
        );

        _playEntries.add(pauseEntry);
        tCursor += interSegmentPauseSec;
      }
    }

    _playTotalTimeSec = tCursor;
  }

  /// Starts the path playback animation from the beginning.
  void _startPlayback() {
    if (_segments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No segments to play')),
      );
      return;
    }

    _preparePlaybackEntries();
    if (_playTotalTimeSec <= 0 || _playEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Path is too short to play')),
      );
      return;
    }

    final firstSeg = _segments.first;
    setState(() {
      _robotFieldX = firstSeg.start.dx;
      _robotFieldY = firstSeg.start.dy;
      _robotHeadingDeg = firstSeg.startHeading;
    });

    _playController.stop();
    _playController.reset();
    _playController.duration =
        Duration(milliseconds: (_playTotalTimeSec * 1000).round());

    setState(() => _isPlaying = true);
    _playController.forward();
  }

  /// Updates the robot's pose on the field based on current animation progress.
  void _onPlayTick() {
    if (!_isPlaying || _playTotalTimeSec <= 0 || _playEntries.isEmpty) {
      return;
    }

    final tSec = _playController.value * _playTotalTimeSec;

    // Identify which segment is active at the current timestamp.
    _PlaybackEntry entry = _playEntries.last;
    for (final e in _playEntries) {
      if (tSec >= e.startTime && tSec <= e.endTime) {
        entry = e;
        break;
      }
    }

    final s = entry.segment;
    final double duration = entry.endTime - entry.startTime;

    Offset pos;
    double heading;

    if (entry.isWait || duration <= 0) {
      pos = s.start;
      heading = s.startHeading;
    } else {
      double local = (tSec - entry.startTime) / duration;
      local = local.clamp(0.0, 1.0);

      // Apply ease-in-out curve for smooth visual movement.
      final eased = Curves.easeInOut.transform(local);

      pos = Offset(
        s.start.dx + (s.end.dx - s.start.dx) * eased,
        s.start.dy + (s.end.dy - s.start.dy) * eased,
      );
      heading =
          s.startHeading + (s.endHeading - s.startHeading) * eased;
    }

    setState(() {
      _robotFieldX = pos.dx;
      _robotFieldY = pos.dy;
      _robotHeadingDeg = heading;
    });
  }

  void _togglePlayback() {
    _startPlayback();
  }

  /// Opens an interactive color picker dialog.
  Future<void> _pickColor({
    required Color initial,
    required ValueChanged<Color> onColorPicked,
    required String title,
  }) async {
    Color temp = initial;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: temp,
              onColorChanged: (c) {
                temp = c;
              },
              enableAlpha: false,
              labelTypes: const [],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                onColorPicked(temp);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyColor = theme.textTheme.bodyMedium?.color ?? Colors.white;
    final sectionLabelStyle = theme.textTheme.bodySmall?.copyWith(
      color: bodyColor.withOpacity(0.8),
      fontWeight: FontWeight.bold,
    );
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: const TopAppBar(
        title: "Autopath visualizer",
        showThemeToggle: true,
        showLogout: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Virtual Field Rendering Area
                  SizedBox(
                    width: double.infinity,
                    height:
                    constraints.maxWidth,
                    child: LayoutBuilder(
                      builder: (context, fieldConstraints) {
                        double fieldSizePx =
                            fieldConstraints.maxWidth * 0.9;
                        if (fieldSizePx > fieldConstraints.maxHeight) {
                          fieldSizePx = fieldConstraints.maxHeight;
                        }

                        final scale = fieldSizePx / _fieldInches;

                        final robotLengthInches = _robotLengthInInches();
                        final robotSizePx = robotLengthInches * scale;

                        final fieldLeft =
                            (fieldConstraints.maxWidth - fieldSizePx) / 2.0;
                        final fieldTop =
                            (fieldConstraints.maxHeight - fieldSizePx) / 2.0;

                        final robotCenterX =
                            fieldLeft + _robotFieldX * scale;
                        final robotCenterY =
                            fieldTop + (_fieldInches - _robotFieldY) * scale;

                        final robotLeft = robotCenterX - robotSizePx / 2;
                        final robotTop = robotCenterY - robotSizePx / 2;

                        return Stack(
                          children: [
                            // Field Layer (Background + Path line)
                            Positioned(
                              left: fieldLeft,
                              top: fieldTop,
                              width: fieldSizePx,
                              height: fieldSizePx,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Image.asset(
                                      'files/images/decode_background.png',
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: Container(
                                      color: Colors.black.withOpacity(0.12),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _PathPainter(
                                        points: _pathPoints,
                                        fieldInches: _fieldInches,
                                        pathColor: _lineColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Interactive Robot Marker Layer
                            Positioned(
                              left: robotLeft,
                              top: robotTop,
                              child: GestureDetector(
                                onPanUpdate: (details) {
                                  setState(() {
                                    final scaleLocal = scale;
                                    final dxField =
                                        details.delta.dx / scaleLocal;
                                    final dyField =
                                        -details.delta.dy / scaleLocal;

                                    _robotFieldX += dxField;
                                    _robotFieldY += dyField;

                                    double halfRobot =
                                        _robotLengthInInches() / 2.0;
                                    if (halfRobot > _fieldInches / 2) {
                                      halfRobot = _fieldInches / 2;
                                    }
                                    final minCoord = halfRobot;
                                    final maxCoord =
                                        _fieldInches - halfRobot;

                                    _robotFieldX = _robotFieldX
                                        .clamp(minCoord, maxCoord);
                                    _robotFieldY = _robotFieldY
                                        .clamp(minCoord, maxCoord);

                                    _endXController.text =
                                        _robotFieldX.toStringAsFixed(3);
                                    _endYController.text =
                                        _robotFieldY.toStringAsFixed(3);

                                    final current =
                                    Offset(_robotFieldX, _robotFieldY);
                                    _updatePathFromSegments(
                                        previewEnd: current);
                                  });
                                },
                                child: Transform.rotate(
                                  angle:
                                  -_robotHeadingDeg * math.pi / 180.0,
                                  child: Container(
                                    width: robotSizePx,
                                    height: robotSizePx,
                                    decoration: BoxDecoration(
                                      color: _robotColor,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: _robotColor.darken(0.15),
                                        width: 2,
                                      ),
                                    ),
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: Container(
                                        margin:
                                        const EdgeInsets.only(top: 4),
                                        width: robotSizePx * 0.2,
                                        height: robotSizePx * 0.15,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                          BorderRadius.circular(4),
                                        ),
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

                  // Configuration Controls Panel
                  Container(
                    width: double.infinity,
                    color: isDark
                        ? const Color(0xFF101010)
                        : Colors.grey.shade100,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: DefaultTextStyle(
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: bodyColor,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Canvas Options', style: sectionLabelStyle),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: _LabeledTextField(
                                  label: 'Robot Length',
                                  controller: _robotLengthController,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 80,
                                child: _UnitSelector(
                                  value: _robotUnit,
                                  onChanged: (unit) {
                                    setState(() {
                                      _robotUnit = unit;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _LabeledTextField(
                                  label: 'Robot Width',
                                  controller: _robotWidthController,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          Row(
                            children: [
                              _ColorChip(
                                label: 'Robot color',
                                color: _robotColor,
                                onTap: () => _pickColor(
                                  initial: _robotColor,
                                  onColorPicked: (c) =>
                                      setState(() => _robotColor = c),
                                  title: 'Select robot color',
                                ),
                              ),
                              const SizedBox(width: 10),
                              _ColorChip(
                                label: 'Line color',
                                color: _lineColor,
                                onTap: () => _pickColor(
                                  initial: _lineColor,
                                  onColorPicked: (c) =>
                                      setState(() => _lineColor = c),
                                  title: 'Select line color',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          Text('Current Robot Position',
                              style: sectionLabelStyle),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: _ReadOnlyField(
                                  label: 'X (in)',
                                  value: _robotFieldX.toStringAsFixed(3),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _ReadOnlyField(
                                  label: 'Y (in)',
                                  value: _robotFieldY.toStringAsFixed(3),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _ReadOnlyField(
                                  label: 'Heading (°)',
                                  value: _robotHeadingDeg.toStringAsFixed(0),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          Text('Start Point', style: sectionLabelStyle),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: _LabeledTextField(
                                  label: 'X',
                                  controller: _startXController,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _LabeledTextField(
                                  label: 'Y',
                                  controller: _startYController,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _LabeledTextField(
                                  label: 'Start Heading (°)',
                                  controller: _startHeadingController,
                                  onChanged: (value) {
                                    final v = double.tryParse(value);
                                    if (v == null) return;
                                    setState(() {
                                      _robotHeadingDeg = v;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          Text('Path', style: sectionLabelStyle),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 36,
                                  child: TextField(
                                    controller: _pathNameController,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                      filled: true,
                                      fillColor: isDark
                                          ? const Color(0xFF1E1E1E)
                                          : Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius:
                                        BorderRadius.circular(10),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                        BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: theme.dividerColor,
                                          width: 1,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                        BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: theme.colorScheme.primary,
                                          width: 1.6,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _lineColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _selectedPathId,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    filled: true,
                                    fillColor: isDark
                                        ? const Color(0xFF1E1E1E)
                                        : Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius:
                                      BorderRadius.circular(10),
                                    ),
                                  ),
                                  hint: const Text('Load saved path'),
                                  items: _savedPaths
                                      .map(
                                        (p) => DropdownMenuItem(
                                      value: p.id,
                                      child: Text(p.name),
                                    ),
                                  )
                                      .toList(),
                                  onChanged: (id) {
                                    if (id != null) {
                                      _loadPathById(id);
                                    }
                                  },
                                ),
                              ),
                              IconButton(
                                onPressed: _loadSavedPaths,
                                icon: const Icon(Icons.refresh),
                                tooltip: 'Refresh paths',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          Text('Segment name', style: sectionLabelStyle),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 36,
                            child: TextField(
                              controller: _segmentNameController,
                              style: theme.textTheme.bodyMedium,
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding:
                                const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                filled: true,
                                fillColor: isDark
                                    ? const Color(0xFF1E1E1E)
                                    : Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: theme.dividerColor,
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.primary,
                                    width: 1.6,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          Text('End Point', style: sectionLabelStyle),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: _LabeledTextField(
                                  label: 'X',
                                  controller: _endXController,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _LabeledTextField(
                                  label: 'Y',
                                  controller: _endYController,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _DropdownField(
                                  label: 'Type',
                                  value: 'Linear',
                                  items: const ['Linear', 'Spline'],
                                  onChanged: (_) {},
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _LabeledTextField(
                                  label: 'End Heading (°)',
                                  controller: _endHeadingController,
                                  onChanged: (value) {
                                    final v = double.tryParse(value);
                                    if (v == null) return;
                                    setState(() {
                                      _robotHeadingDeg = v;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: _addLineFromFields,
                                icon: const Icon(Icons.add),
                                label: const Text('Add Line'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                  theme.colorScheme.primary,
                                  foregroundColor:
                                  theme.colorScheme.onPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _addWaitAtCurrentRobotPosition,
                                icon: const Icon(Icons.timer),
                                label: const Text('Add Wait'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                  theme.colorScheme.primary,
                                  foregroundColor:
                                  theme.colorScheme.onPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _togglePlayback,
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Play'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                  theme.colorScheme.primary,
                                  foregroundColor:
                                  theme.colorScheme.onPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _segments.isEmpty
                                    ? null
                                    : _undoLastSegment,
                                icon: const Icon(Icons.undo),
                                label: const Text('Undo'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                  theme.colorScheme.primary,
                                  foregroundColor:
                                  theme.colorScheme.onPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _segments.isEmpty &&
                                    _pathPoints.isEmpty
                                    ? null
                                    : _resetPath,
                                icon: const Icon(Icons.restart_alt),
                                label: const Text('Reset'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                  theme.colorScheme.primary,
                                  foregroundColor:
                                  theme.colorScheme.onPrimary,
                                ),
                              ),
                            ],
                          ),

                          if (_segments.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text('Segments', style: sectionLabelStyle),
                            const SizedBox(height: 6),
                            ListView.builder(
                              shrinkWrap: true,
                              physics:
                              const NeverScrollableScrollPhysics(),
                              itemCount: _segments.length,
                              itemBuilder: (context, index) {
                                final s = _segments[index];
                                if (s.isWaitOnly) {
                                  return Text(
                                    '${s.name} (Segment ${index + 1}): '
                                        'WAIT ${s.waitMs.toStringAsFixed(0)} ms',
                                    style: theme.textTheme.bodySmall,
                                  );
                                }
                                return Text(
                                  '${s.name} (Segment ${index + 1}): '
                                      '(${s.start.dx.toStringAsFixed(1)}, '
                                      '${s.start.dy.toStringAsFixed(1)}, '
                                      '${s.startHeading.toStringAsFixed(0)}°)'
                                      '  →  '
                                      '(${s.end.dx.toStringAsFixed(1)}, '
                                      '${s.end.dy.toStringAsFixed(1)}, '
                                      '${s.endHeading.toStringAsFixed(0)}°)',
                                  style: theme.textTheme.bodySmall,
                                );
                              },
                            ),
                          ],

                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: _segments.isEmpty
                                    ? null
                                    : _saveCurrentPathToFirebase,
                                icon: const Icon(Icons.cloud_upload),
                                label: const Text('Save to Firebase'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                  theme.colorScheme.primary,
                                  foregroundColor:
                                  theme.colorScheme.onPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: (_pathPoints.isEmpty &&
                                    _segments.isEmpty)
                                    ? null
                                    : _copyRouteToClipboard,
                                icon: const Icon(Icons.copy),
                                label: const Text('Copy route'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                  theme.colorScheme.primary,
                                  foregroundColor:
                                  theme.colorScheme.onPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: (_pathPoints.isEmpty &&
                                    _segments.isEmpty)
                                    ? null
                                    : _showRouteTextDialog,
                                icon: const Icon(Icons.description),
                                label: const Text('Show TXT'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                  theme.colorScheme.primary,
                                  foregroundColor:
                                  theme.colorScheme.onPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTabSelected: (_) {},
        items: const [],
      ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ColorChip({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.black.withOpacity(0.3),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

extension ColorDarken on Color {
  /// Returns a darkened version of the current color.
  Color darken([double amount = 0.1]) {
    final hsl = HSLColor.fromColor(this);
    final hslDark =
    hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}

/// Custom painter to draw the autonomous path line on the virtual field.
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
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

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
  bool shouldRepaint(covariant _PathPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.pathColor != pathColor ||
        oldDelegate.fieldInches != fieldInches;
  }
}

/// UI component for selecting robot dimension units.
class _UnitSelector extends StatelessWidget {
  final RobotUnit value;
  final ValueChanged<RobotUnit> onChanged;

  const _UnitSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyColor = theme.textTheme.bodyMedium?.color ?? Colors.white;
    final bool isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Unit',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: bodyColor.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.dividerColor,
              width: 1,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<RobotUnit>(
              value: value,
              isExpanded: true,
              icon: Icon(
                Icons.arrow_drop_down,
                color: bodyColor.withOpacity(0.8),
              ),
              items: const [
                DropdownMenuItem(
                  value: RobotUnit.inch,
                  child: Text('inch'),
                ),
                DropdownMenuItem(
                  value: RobotUnit.cm,
                  child: Text('cm'),
                ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// UI component for a text input field with a label.
class _LabeledTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  const _LabeledTextField({
    required this.label,
    required this.controller,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyColor = theme.textTheme.bodyMedium?.color ?? Colors.white;
    final bool isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: bodyColor.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 40,
          child: TextField(
            controller: controller,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
            onChanged: onChanged,
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              filled: true,
              fillColor:
              isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: theme.dividerColor,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 1.6,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// UI component for displaying fixed data with a label.
class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyField({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyColor = theme.textTheme.bodyMedium?.color ?? Colors.white;
    final bool isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: bodyColor.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.dividerColor,
              width: 1,
            ),
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
          ),
        ),
      ],
    );
  }
}

/// UI component for a dropdown selection menu with a label.
class _DropdownField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyColor = theme.textTheme.bodyMedium?.color ?? Colors.white;
    final bool isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: bodyColor.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.dividerColor,
              width: 1,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: Icon(
                Icons.arrow_drop_down,
                color: bodyColor.withOpacity(0.8),
              ),
              dropdownColor:
              isDark ? const Color(0xFF1E1E1E) : Colors.white,
              items: items
                  .map(
                    (e) => DropdownMenuItem(
                  value: e,
                  child: Text(
                    e,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
