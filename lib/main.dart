import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mesh.dart';

void main() {
  runApp(const BlunderApp());
}

class BlunderApp extends StatelessWidget {
  const BlunderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blunder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4E8DFF),
          brightness: Brightness.dark,
          surface: const Color(0xFF171B23),
        ),
        scaffoldBackgroundColor: const Color(0xFF101319),
        useMaterial3: true,
      ),
      home: const ModelerScreen(),
    );
  }
}

enum EditMode { vertex, face }
enum EditorPage { model, uv }
enum ActiveTool { select, addVertex }

class ModelerScreen extends StatefulWidget {
  const ModelerScreen({super.key});

  @override
  State<ModelerScreen> createState() => _ModelerScreenState();
}

class _ModelerScreenState extends State<ModelerScreen> {
  MeshModel _mesh = MeshModel.starterPlane();
  EditMode _mode = EditMode.vertex;
  EditorPage _page = EditorPage.model;
  ActiveTool _tool = ActiveTool.select;
  final Set<int> _selectedVertices = {};
  int? _selectedFace = 0;
  double _yaw = -0.55;
  double _pitch = 0.68;
  double _zoom = 1;
  double _gestureZoomStart = 1;
  Offset _pan = Offset.zero;
  Offset _gestureAnchor = Offset.zero;
  int _draggingUvCorner = -1;

  void _resetPlane() {
    setState(() {
      _mesh = MeshModel.starterPlane();
      _selectedVertices.clear();
      _selectedFace = 0;
      _tool = ActiveTool.select;
      _page = EditorPage.model;
    });
  }

  void _connectVertices() {
    if (!_mesh.addQuad(_selectedVertices)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select four new, distinct vertices to make a quad.'),
        ),
      );
      return;
    }
    setState(() {
      _selectedFace = _mesh.faces.length - 1;
      _mode = EditMode.face;
      _tool = ActiveTool.select;
    });
  }

  void _deleteFace() {
    final face = _selectedFace;
    if (face == null || !_mesh.removeFace(face)) return;
    setState(() {
      _selectedFace = _mesh.faces.isEmpty
          ? null
          : (face < _mesh.faces.length ? face : _mesh.faces.length - 1);
    });
  }

  void _handleModelTap(Offset point, Size size) {
    if (_tool == ActiveTool.addVertex && _mode == EditMode.vertex) {
      final index = _mesh.addVertex(_worldPosition(point, size));
      setState(() {
        _selectedVertices
          ..clear()
          ..add(index);
        _tool = ActiveTool.select;
      });
      return;
    }

    if (_mode == EditMode.vertex) {
      final hit = _nearestVertex(point, size);
      setState(() {
        if (hit != null) {
          if (!_selectedVertices.add(hit)) _selectedVertices.remove(hit);
        } else {
          _selectedVertices.clear();
        }
      });
    } else {
      setState(() => _selectedFace = _hitFace(point, size));
    }
  }

  Offset _project(Vec3 point, Size size) {
    final cosYaw = math.cos(_yaw);
    final sinYaw = math.sin(_yaw);
    final rotatedX = point.x * cosYaw - point.y * sinYaw;
    final rotatedY = point.x * sinYaw + point.y * cosYaw;
    final vertical = rotatedY * math.cos(_pitch) - point.z * math.sin(_pitch);
    final scale = math.min(size.width, size.height).toDouble() * 0.27 * _zoom;
    return Offset(
      size.width / 2 + _pan.dx + rotatedX * scale,
      size.height / 2 + _pan.dy - vertical * scale,
    );
  }

  Vec3 _worldPosition(Offset screenPoint, Size size) {
    final scale = math.min(size.width, size.height).toDouble() * 0.27 * _zoom;
    final rotatedX = (screenPoint.dx - size.width / 2 - _pan.dx) / scale;
    final rotatedY = -(screenPoint.dy - size.height / 2 - _pan.dy) /
        (scale * math.cos(_pitch));
    return Vec3(
      rotatedX * math.cos(_yaw) + rotatedY * math.sin(_yaw),
      -rotatedX * math.sin(_yaw) + rotatedY * math.cos(_yaw),
      0,
    );
  }

  int? _nearestVertex(Offset point, Size size) {
    int? nearest;
    var nearestDistance = 24.0;
    for (var i = 0; i < _mesh.vertices.length; i++) {
      final distance =
          (_project(_mesh.vertices[i].position, size) - point).distance;
      if (distance < nearestDistance) {
        nearest = i;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  int? _hitFace(Offset point, Size size) {
    for (var faceIndex = _mesh.faces.length - 1;
        faceIndex >= 0;
        faceIndex--) {
      final face = _mesh.faces[faceIndex];
      final path = Path()
        ..addPolygon(
          face.vertices
              .map((index) => _project(_mesh.vertices[index].position, size))
              .toList(),
          true,
        );
      if (path.contains(point)) return faceIndex;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_in_ar_rounded, color: Color(0xFF75A6FF)),
            SizedBox(width: 9),
            Text('Blunder', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _resetPlane,
            icon: const Icon(Icons.add_box_outlined, size: 18),
            label: const Text('New surface'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildToolbar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: wide ? _buildWideWorkspace() : _buildWorkspace(),
              ),
            ),
            _buildBottomBar(wide),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Material(
      color: const Color(0xFF171B23),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SegmentedButton<EditMode>(
              segments: const [
                ButtonSegment(
                  value: EditMode.vertex,
                  icon: Icon(Icons.circle_outlined, size: 17),
                  label: Text('Vertex'),
                ),
                ButtonSegment(
                  value: EditMode.face,
                  icon: Icon(Icons.crop_square_rounded, size: 17),
                  label: Text('Face'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) {
                setState(() {
                  _mode = selection.first;
                  _tool = ActiveTool.select;
                });
              },
            ),
            const SizedBox(width: 10),
            if (_mode == EditMode.vertex) ...[
              _ToolButton(
                label: 'Add vertex',
                icon: Icons.add_circle_outline_rounded,
                selected: _tool == ActiveTool.addVertex,
                onPressed: () => setState(
                  () => _tool = _tool == ActiveTool.addVertex
                      ? ActiveTool.select
                      : ActiveTool.addVertex,
                ),
              ),
              const SizedBox(width: 6),
              FilledButton.tonalIcon(
                onPressed:
                    _selectedVertices.length == 4 ? _connectVertices : null,
                icon: const Icon(Icons.polyline_rounded, size: 18),
                label: const Text('Make quad'),
              ),
            ] else ...[
              _ToolButton(
                label: 'Delete face',
                icon: Icons.delete_outline_rounded,
                onPressed: _selectedFace == null ? null : _deleteFace,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspace() =>
      _page == EditorPage.model ? _buildViewport() : _buildUvEditor();

  Widget _buildWideWorkspace() {
    return Row(
      children: [
        SizedBox(width: 220, child: _buildSidePanel()),
        const SizedBox(width: 12),
        Expanded(
          child: _page == EditorPage.model
              ? _buildViewport()
              : _buildUvEditor(),
        ),
      ],
    );
  }

  Widget _buildSidePanel() {
    return Container(
      decoration: _panelDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _page == EditorPage.model ? 'SCENE' : 'UV MAPPING',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.4,
                  color: Colors.white54,
                ),
          ),
          const SizedBox(height: 14),
          _pageButton(EditorPage.model, Icons.view_in_ar_rounded, 'Model'),
          const SizedBox(height: 6),
          _pageButton(EditorPage.uv, Icons.grid_on_rounded, 'UV layout'),
          const Divider(height: 28),
          Text('Flat surface', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 5),
          Text(
            '${_mesh.vertices.length} vertices  ·  ${_mesh.faces.length} faces',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white60,
                ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _resetPlane,
            icon: const Icon(Icons.add_box_outlined, size: 18),
            label: const Text('New flat surface'),
          ),
          const Spacer(),
          Text(
            _page == EditorPage.model
                ? 'Drag to orbit\nPinch to zoom · two fingers to pan\nTap vertices to select'
                : 'Drag a UV corner to adjust the mapping',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                  height: 1.6,
                ),
          ),
        ],
      ),
    );
  }

  Widget _pageButton(EditorPage page, IconData icon, String label) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: () => setState(() => _page = page),
        icon: Icon(icon, size: 18),
        label: Align(alignment: Alignment.centerLeft, child: Text(label)),
        style: TextButton.styleFrom(
          foregroundColor: _page == page ? Colors.white : Colors.white70,
          backgroundColor:
              _page == page ? const Color(0xFF2A3546) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        ),
      ),
    );
  }

  Widget _buildViewport() {
    return Container(
      decoration: _panelDecoration(),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleModelTap(details.localPosition, size),
            onScaleStart: (details) {
              _gestureAnchor = details.focalPoint;
              _gestureZoomStart = _zoom;
            },
            onScaleUpdate: (details) {
              if (details.pointerCount >= 2) {
                setState(() {
                  _pan += details.focalPoint - _gestureAnchor;
                  _zoom = (_gestureZoomStart * details.scale)
                      .clamp(0.45, 3.5)
                      .toDouble();
                  _gestureAnchor = details.focalPoint;
                });
              } else if (_tool != ActiveTool.addVertex) {
                setState(() {
                  _yaw += details.focalPointDelta.dx * 0.008;
                  _pitch = (_pitch + details.focalPointDelta.dy * 0.008)
                      .clamp(-1.2, 1.2)
                      .toDouble();
                });
              }
            },
            child: CustomPaint(
              size: size,
              painter: _ViewportPainter(
                mesh: _mesh,
                selectedVertices: _selectedVertices,
                selectedFace: _selectedFace,
                project: (point) => _project(point, size),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUvEditor() {
    return Container(
      decoration: _panelDecoration(),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final faceIndex = _selectedFace;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: faceIndex == null
                ? null
                : (details) {
                    final face = _mesh.faces[faceIndex];
                    final origin = _uvOrigin(size);
                    final scale = _uvScale(size);
                    var nearest = -1;
                    var distance = 26.0;
                    for (var i = 0; i < face.uv.length; i++) {
                      final point = origin +
                          Offset(face.uv[i].dx, 1 - face.uv[i].dy) * scale;
                      final candidate =
                          (point - details.localPosition).distance;
                      if (candidate < distance) {
                        nearest = i;
                        distance = candidate;
                      }
                    }
                    _draggingUvCorner = nearest;
                  },
            onPanUpdate: faceIndex == null
                ? null
                : (details) {
                    final corner = _draggingUvCorner;
                    if (corner < 0) return;
                    final origin = _uvOrigin(size);
                    final scale = _uvScale(size);
                    final uv = Offset(
                      (details.localPosition.dx - origin.dx) / scale,
                      1 - (details.localPosition.dy - origin.dy) / scale,
                    );
                    setState(() => _mesh.updateUv(faceIndex, corner, uv));
                  },
            onPanEnd: faceIndex == null ? null : (_) => _draggingUvCorner = -1,
            child: CustomPaint(
              size: size,
              painter: _UvPainter(
                face: faceIndex == null ? null : _mesh.faces[faceIndex],
              ),
            ),
          );
        },
      ),
    );
  }

  Offset _uvOrigin(Size size) => Offset(
        (size.width - _uvScale(size)) / 2,
        (size.height - _uvScale(size)) / 2,
      );

  double _uvScale(Size size) =>
      math.min(size.width, size.height).toDouble() * 0.72;

  Widget _buildBottomBar(bool wide) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF171B23),
        border: Border(top: BorderSide(color: Color(0xFF282E39))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      child: Row(
        children: [
          if (!wide) ...[
            _BottomNavButton(
              label: 'Model',
              icon: Icons.view_in_ar_rounded,
              selected: _page == EditorPage.model,
              onPressed: () => setState(() => _page = EditorPage.model),
            ),
            _BottomNavButton(
              label: 'UVs',
              icon: Icons.grid_on_rounded,
              selected: _page == EditorPage.uv,
              onPressed: () => setState(() => _page = EditorPage.uv),
            ),
            const VerticalDivider(width: 18, indent: 8, endIndent: 8),
          ],
          Expanded(
            child: Text(
              _statusText(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white60,
                  ),
            ),
          ),
          if (wide && _page == EditorPage.model)
            Text(
              'Drag: orbit  ·  Pinch: zoom',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white38,
                  ),
            ),
        ],
      ),
    );
  }

  String _statusText() {
    if (_page == EditorPage.uv) {
      return _selectedFace == null
          ? 'Select a face to edit its UVs'
          : 'Face ${_selectedFace! + 1}  ·  Drag a corner to map';
    }
    if (_tool == ActiveTool.addVertex) {
      return 'Tap the surface to place a vertex';
    }
    if (_mode == EditMode.vertex) {
      return '${_selectedVertices.length}/4 vertices selected';
    }
    return _selectedFace == null
        ? 'No face selected'
        : 'Face ${_selectedFace! + 1} selected';
  }

  BoxDecoration _panelDecoration() => BoxDecoration(
        color: const Color(0xFF171B23),
        border: Border.all(color: const Color(0xFF282E39)),
        borderRadius: BorderRadius.circular(14),
      );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? const Color(0xFF283955) : null,
      ),
    );
  }
}

class _BottomNavButton extends StatelessWidget {
  const _BottomNavButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: selected ? const Color(0xFF94B9FF) : Colors.white60,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}

class _ViewportPainter extends CustomPainter {
  _ViewportPainter({
    required this.mesh,
    required this.selectedVertices,
    required this.selectedFace,
    required this.project,
  });

  final MeshModel mesh;
  final Set<int> selectedVertices;
  final int? selectedFace;
  final Offset Function(Vec3 point) project;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF29303A)
      ..strokeWidth = 1;
    for (var i = -6; i <= 6; i++) {
      canvas.drawLine(
        project(Vec3(i / 3, -2, -0.02)),
        project(Vec3(i / 3, 2, -0.02)),
        gridPaint,
      );
      canvas.drawLine(
        project(Vec3(-2, i / 3, -0.02)),
        project(Vec3(2, i / 3, -0.02)),
        gridPaint,
      );
    }

    for (var i = 0; i < mesh.faces.length; i++) {
      final face = mesh.faces[i];
      final path = Path()
        ..addPolygon(
          face.vertices
              .map((index) => project(mesh.vertices[index].position))
              .toList(),
          true,
        );
      canvas.drawPath(
        path,
        Paint()
          ..color = i == selectedFace
              ? const Color(0x664E8DFF)
              : const Color(0x553B87C6)
          ..style = PaintingStyle.fill,
      );
    }

    final edgePaint = Paint()
      ..color = const Color(0xFF8DB6FF)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    for (final face in mesh.faces) {
      final points = face.vertices
          .map((index) => project(mesh.vertices[index].position))
          .toList();
      canvas.drawPath(Path()..addPolygon(points, true), edgePaint);
    }

    for (var i = 0; i < mesh.vertices.length; i++) {
      final point = project(mesh.vertices[i].position);
      final selected = selectedVertices.contains(i);
      canvas.drawCircle(
        point,
        selected ? 7 : 5,
        Paint()..color = selected ? const Color(0xFFFFC45C) : Colors.white,
      );
      canvas.drawCircle(
        point,
        selected ? 7 : 5,
        Paint()
          ..color = const Color(0xFF101319)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }

    if (mesh.vertices.isEmpty) {
      _drawText(
        canvas,
        'Tap “New flat surface” to get started',
        size.center(Offset.zero),
        Colors.white54,
        centered: true,
      );
    }
    _drawAxis(canvas);
  }

  void _drawAxis(Canvas canvas) {
    const origin = Offset(37, 43);
    final paint = Paint()..strokeWidth = 2;
    canvas.drawLine(
      origin,
      origin + const Offset(25, 0),
      paint..color = const Color(0xFFE16C6C),
    );
    canvas.drawLine(
      origin,
      origin + const Offset(0, -25),
      paint..color = const Color(0xFF63C48D),
    );
    _drawText(canvas, 'X', origin + const Offset(28, -8), Colors.white70);
    _drawText(canvas, 'Y', origin + const Offset(-8, -37), Colors.white70);
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position,
    Color color, {
    bool centered = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      centered
          ? position - Offset(painter.width / 2, painter.height / 2)
          : position,
    );
  }

  @override
  bool shouldRepaint(covariant _ViewportPainter oldDelegate) => true;
}

class _UvPainter extends CustomPainter {
  const _UvPainter({required this.face});

  final MeshFace? face;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height).toDouble() * 0.72;
    final origin = Offset((size.width - scale) / 2, (size.height - scale) / 2);
    final rect = Rect.fromLTWH(origin.dx, origin.dy, scale, scale);
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFF202733)
        ..style = PaintingStyle.fill,
    );
    final grid = Paint()
      ..color = const Color(0xFF343D4B)
      ..strokeWidth = 1;
    for (var i = 0; i <= 10; i++) {
      final offset = scale * i / 10;
      canvas.drawLine(
        Offset(origin.dx + offset, origin.dy),
        Offset(origin.dx + offset, origin.dy + scale),
        grid,
      );
      canvas.drawLine(
        Offset(origin.dx, origin.dy + offset),
        Offset(origin.dx + scale, origin.dy + offset),
        grid,
      );
    }
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFF6A778C)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    final selectedFace = face;
    if (selectedFace == null) {
      _drawLabel(
        canvas,
        'Create or select a face to edit its UVs',
        size.center(Offset.zero),
      );
      return;
    }

    final points = selectedFace.uv
        .map((uv) => origin + Offset(uv.dx, 1 - uv.dy) * scale)
        .toList();
    canvas.drawPath(
      Path()..addPolygon(points, true),
      Paint()
        ..color = const Color(0x664E8DFF)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      Path()..addPolygon(points, true),
      Paint()
        ..color = const Color(0xFF8DB6FF)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    for (final point in points) {
      canvas.drawCircle(point, 9, Paint()..color = const Color(0xFFFFC45C));
      canvas.drawCircle(
        point,
        9,
        Paint()
          ..color = const Color(0xFF101319)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
    _drawLabel(canvas, '0 — 1 UV space', Offset(size.width / 2, rect.bottom + 22));
  }

  void _drawLabel(Canvas canvas, String text, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _UvPainter oldDelegate) => true;
}
