import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

/// Represents a single continuous stroke drawn on the whiteboard.
class _DrawnLine {
  final List<Offset> points;
  final Color color;
  final double width;

  _DrawnLine(this.points, this.color, this.width);
}

/// Defines the available drawing modes.
enum DrawingMode { freehand, straightLine }

/// Represents a movable robot marker on the strategy field.
class _RobotMarker {
  final String label;
  final Color color;
  Offset position;
  bool visible;
  bool traceEnabled;
  List<Offset> tracePoints;

  _RobotMarker({
    required this.label,
    required this.color,
    required this.position,
    this.visible = true,
    this.traceEnabled = false,
  }) : tracePoints = [position];
}

/// A page providing an interactive whiteboard over an FTC field background for strategy planning.
class StrategyWhiteboardPage extends StatefulWidget {
  const StrategyWhiteboardPage({super.key});

  @override
  State<StrategyWhiteboardPage> createState() => _StrategyWhiteboardPageState();
}

class _StrategyWhiteboardPageState extends State<StrategyWhiteboardPage> {
  // Drawing state
  final List<_DrawnLine> _lines = [];
  Color _selectedColor = Colors.blue;
  final double _strokeWidth = 4.0;
  DrawingMode _drawingMode = DrawingMode.freehand;
  
  // GlobalKey to accurately calculate local coordinates within the field container.
  final GlobalKey _fieldKey = GlobalKey();

  // Robot markers state (Red and Blue alliances)
  final List<_RobotMarker> _robots = [
    _RobotMarker(label: 'R1', color: Colors.red, position: const Offset(50, 50)),
    _RobotMarker(label: 'R2', color: Colors.red.shade900, position: const Offset(50, 150)),
    _RobotMarker(label: 'B1', color: Colors.blue, position: const Offset(250, 50)),
    _RobotMarker(label: 'B2', color: Colors.blue.shade900, position: const Offset(250, 150)),
  ];

  // The line currently being drawn by the user.
  _DrawnLine? _currentLine;

  // Constants for scaling (FTC field is 144x144 inches).
  static const double _fieldInches = 144.0;
  static const double _robotInches = 22.0;

  /// Clears all drawings and robot traces from the whiteboard.
  void _clear() {
    setState(() {
      _lines.clear();
      _currentLine = null;
      for (var r in _robots) {
        r.tracePoints = [r.position];
      }
    });
  }

  /// Removes the last drawn segment from the board.
  void _undo() {
    if (_lines.isNotEmpty) {
      setState(() {
        _lines.removeLast();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: const TopAppBar(
        title: "Strategy Whiteboard",
        showThemeToggle: true,
        showLogout: true,
      ),
      body: Column(
        children: [
          // The main interactive area containing the field and drawing layers.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Calculate scale based on available screen space.
                  final size = math.min(constraints.maxWidth, constraints.maxHeight);
                  final scale = size / _fieldInches;
                  final robotSize = _robotInches * scale;

                  return Center(
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Container(
                        key: _fieldKey,
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.dividerColor, width: 2),
                          borderRadius: BorderRadius.circular(8),
                          image: const DecorationImage(
                            image: AssetImage('files/images/decode_background.png'),
                            fit: BoxFit.contain,
                          ),
                        ),
                        child: Stack(
                          children: [
                            // Layer 1: Movement traces left by robot markers.
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _TracePainter(robots: _robots),
                              ),
                            ),
                            
                            // Layer 2: User drawing layer (freehand or straight lines).
                            Positioned.fill(
                              child: GestureDetector(
                                onPanStart: (details) {
                                  setState(() {
                                    _currentLine = _DrawnLine(
                                      [details.localPosition],
                                      _selectedColor,
                                      _strokeWidth,
                                    );
                                  });
                                },
                                onPanUpdate: (details) {
                                  setState(() {
                                    if (_currentLine != null) {
                                      if (_drawingMode == DrawingMode.freehand) {
                                        _currentLine!.points.add(details.localPosition);
                                      } else {
                                        // In straight line mode, we only update the end point.
                                        if (_currentLine!.points.length < 2) {
                                          _currentLine!.points.add(details.localPosition);
                                        } else {
                                          _currentLine!.points[1] = details.localPosition;
                                        }
                                      }
                                    }
                                  });
                                },
                                onPanEnd: (details) {
                                  setState(() {
                                    if (_currentLine != null) {
                                      _lines.add(_currentLine!);
                                      _currentLine = null;
                                    }
                                  });
                                },
                                child: CustomPaint(
                                  painter: _WhiteboardPainter(
                                    lines: _lines,
                                    currentLine: _currentLine,
                                  ),
                                  size: Size.infinite,
                                ),
                              ),
                            ),
                            
                            // Layer 3: Interactive robot markers.
                            for (int i = 0; i < _robots.length; i++)
                              if (_robots[i].visible)
                                _buildRobotMarker(i, robotSize),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          
          // Bottom toolbar for tools, colors, and robot toggles.
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tool selection (Draw modes, Colors, Undo/Clear)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _modeButton(Icons.edit, DrawingMode.freehand, "Freehand"),
                      _modeButton(Icons.show_chart, DrawingMode.straightLine, "Straight Line"),
                      const VerticalDivider(),
                      _colorButton(Colors.red),
                      _colorButton(Colors.blue),
                      _colorButton(Colors.green),
                      _colorButton(Colors.orange),
                      _colorButton(Colors.white),
                      const VerticalDivider(),
                      IconButton(icon: const Icon(Icons.undo), onPressed: _undo, tooltip: "Undo"),
                      IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clear, tooltip: "Clear Board"),
                    ],
                  ),
                ),
                const Divider(height: 8),
                // Robot visibility and trace toggles
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (int i = 0; i < _robots.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => setState(() => _robots[i].visible = !_robots[i].visible),
                                    child: Chip(
                                      label: Text(_robots[i].label),
                                      backgroundColor: _robots[i].visible ? _robots[i].color.withOpacity(0.3) : Colors.grey.withOpacity(0.1),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(_robots[i].traceEnabled ? Icons.gesture : Icons.gesture_outlined, size: 18),
                                    onPressed: () => setState(() => _robots[i].traceEnabled = !_robots[i].traceEnabled),
                                    color: _robots[i].traceEnabled ? _robots[i].color : Colors.grey,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: "Toggle Trace",
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const Text("Tip: Drag robots to move them across the field.", style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTabSelected: (_) {},
        items: const [],
      ),
    );
  }

  /// Builds a draggable robot marker widget.
  Widget _buildRobotMarker(int i, double robotSize) {
    final robot = _robots[i];
    
    return Positioned(
      left: robot.position.dx - robotSize / 2,
      top: robot.position.dy - robotSize / 2,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            robot.position += details.delta;
            // Record position for the trace if enabled.
            if (robot.traceEnabled) {
              robot.tracePoints.add(robot.position);
            }
          });
        },
        child: Container(
          width: robotSize,
          height: robotSize,
          decoration: BoxDecoration(
            color: robot.color.withOpacity(0.8),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 4,
                offset: const Offset(2, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              robot.label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: robotSize * 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Helper to build a mode selection button.
  Widget _modeButton(IconData icon, DrawingMode mode, String tooltip) {
    bool isSelected = _drawingMode == mode;
    return IconButton(
      icon: Icon(icon),
      onPressed: () => setState(() => _drawingMode = mode),
      color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
      tooltip: tooltip,
    );
  }

  /// Helper to build a color selection button.
  Widget _colorButton(Color color) {
    bool isSelected = _selectedColor == color;
    return GestureDetector(
      onTap: () => setState(() => _selectedColor = color),
      child: Container(
        width: 24,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: isSelected ? Colors.grey : Colors.transparent, width: 2),
        ),
      ),
    );
  }
}

/// CustomPainter responsible for rendering the drawings on the whiteboard.
class _WhiteboardPainter extends CustomPainter {
  final List<_DrawnLine> lines;
  final _DrawnLine? currentLine;

  _WhiteboardPainter({required this.lines, this.currentLine});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Draw all completed segments.
    for (final line in lines) {
      paint.color = line.color;
      paint.strokeWidth = line.width;
      _drawLine(canvas, line.points, paint);
    }

    // Draw the segment currently being created.
    if (currentLine != null) {
      paint.color = currentLine!.color;
      paint.strokeWidth = currentLine!.width;
      _drawLine(canvas, currentLine!.points, paint);
    }
  }

  /// Helper to draw a path from a list of points.
  void _drawLine(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.isEmpty) return;
    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WhiteboardPainter oldDelegate) => true;
}

/// CustomPainter responsible for rendering the robot movement traces.
class _TracePainter extends CustomPainter {
  final List<_RobotMarker> robots;
  _TracePainter({required this.robots});

  @override
  void paint(Canvas canvas, Size size) {
    for (var robot in robots) {
      if (robot.tracePoints.length < 2) continue;
      
      final paint = Paint()
        ..color = robot.color.withOpacity(0.5)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      path.moveTo(robot.tracePoints.first.dx, robot.tracePoints.first.dy);
      for (int i = 1; i < robot.tracePoints.length; i++) {
        path.lineTo(robot.tracePoints[i].dx, robot.tracePoints[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TracePainter oldDelegate) => true;
}
