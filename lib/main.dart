import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mesh.dart';
import 'model_io.dart';

void main(List<String> args) {
  String? initialPkyPath;
  for (final argument in args) {
    if (argument.toLowerCase().endsWith('.pky')) {
      initialPkyPath = argument;
      break;
    }
  }
  runApp(BlunderApp(initialPkyPath: initialPkyPath));
}

class BlunderApp extends StatelessWidget {
  const BlunderApp({super.key, this.initialPkyPath});

  final String? initialPkyPath;

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
      home: ModelerScreen(initialPkyPath: initialPkyPath),
    );
  }
}

enum EditMode { vertex, face }

enum EditorPage { model, uv }

enum ActiveTool { select, addVertex, strip, move }

enum ViewPreset { free, front, back, right, left, top, bottom }

enum MeshAxis { x, y, z }

enum ViewStyle { solid, textured, wireframe }

enum _UnsavedChoice { save, discard, cancel }

class ViewportState {
  ViewportState(this.preset);

  ViewPreset preset;
  double yaw = -0.55;
  double pitch = 0.68;
  double zoom = 1;
  Offset pan = Offset.zero;
}

class SceneObject {
  SceneObject(
    this.name,
    this.mesh, {
    this.texturePath,
    this.textureImage,
  });

  final String name;
  final MeshModel mesh;
  String? texturePath;
  ui.Image? textureImage;
}

class _ViewBasis {
  const _ViewBasis(this.right, this.up, this.normal);

  final Vec3 right;
  final Vec3 up;
  final Vec3 normal;
}

class ModelerScreen extends StatefulWidget {
  const ModelerScreen({super.key, this.initialPkyPath});

  final String? initialPkyPath;

  @override
  State<ModelerScreen> createState() => _ModelerScreenState();
}

class _ModelerScreenState extends State<ModelerScreen> {
  final List<SceneObject> _objects = [
    SceneObject('Mesh_1', MeshModel.starterPlane()),
  ];
  final List<ViewportState> _viewports = [
    ViewportState(ViewPreset.free),
    ViewportState(ViewPreset.front),
    ViewportState(ViewPreset.left),
    ViewportState(ViewPreset.top),
  ];
  final Map<String, MenuController> _menuControllers = {};
  int _activeViewportIndex = 0;
  int _visibleViewportCount = 1;
  bool _isSidePanelVisible = true;
  int _activeObjectIndex = 0;
  MeshModel get _mesh => _objects[_activeObjectIndex].mesh;

  EditMode _mode = EditMode.vertex;
  EditorPage _page = EditorPage.model;
  ActiveTool _tool = ActiveTool.select;
  ViewportState get _activeViewport => _viewports[_activeViewportIndex];
  ViewPreset get _viewPreset => _activeViewport.preset;
  set _viewPreset(ViewPreset value) => _activeViewport.preset = value;
  MeshAxis? _lockedAxis;
  final Set<int> _selectedVertices = {};
  final Set<int> _selectedFaces = {};
  int? _selectedFace = 0;
  final List<int> _stripEdge = [];
  final Map<ViewPreset, ui.Image> _referenceImages = {};
  double get _yaw => _activeViewport.yaw;
  set _yaw(double value) => _activeViewport.yaw = value;
  double get _pitch => _activeViewport.pitch;
  set _pitch(double value) => _activeViewport.pitch = value;
  static const double _minZoom = 0.035;
  static const double _maxZoom = 12;
  double _gestureZoomStart = 1;
  double _referenceOpacity = 0.35;
  Offset _gestureAnchor = Offset.zero;
  int _draggingUvCorner = -1;
  ViewStyle _viewStyle = ViewStyle.solid;
  String? _currentFilePath;
  bool _isDirty = false;
  bool _isSaving = false;
  bool _awaitingRotationAxis = false;
  MeshAxis? _rotationAxis;
  String _rotationDegrees = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Platform.isWindows && kReleaseMode) _registerPkyAssociation();
      final path = widget.initialPkyPath;
      if (path != null) _loadScenePath(path);
    });
  }

  @override
  void dispose() {
    for (final image in _referenceImages.values) {
      image.dispose();
    }
    for (final object in _objects) {
      object.textureImage?.dispose();
    }
    super.dispose();
  }

  void _resetPlane() {
    _objects[_activeObjectIndex].textureImage?.dispose();
    setState(() {
      _objects[_activeObjectIndex] = SceneObject(
        _objects[_activeObjectIndex].name,
        MeshModel.starterPlane(),
      );
      _selectedVertices.clear();
      _selectedFaces.clear();
      _selectedFace = 0;
      _tool = ActiveTool.select;
      _lockedAxis = null;
      _page = EditorPage.model;
      _isDirty = true;
    });
  }

  void _addMesh() {
    setState(() {
      final mesh = MeshModel.starterPlane();
      mesh.moveVertices(
        List.generate(mesh.vertices.length, (index) => index),
        Vec3(_objects.length * 3, 0, 0),
      );
      _objects.add(
        SceneObject('Mesh_${_objects.length + 1}', mesh),
      );
      _activeObjectIndex = _objects.length - 1;
      _selectedVertices.clear();
      _selectedFaces.clear();
      _selectedFace = 0;
      _tool = ActiveTool.select;
      _lockedAxis = null;
      _isDirty = true;
    });
  }

  void _selectMesh(int index) {
    if (index == _activeObjectIndex) return;
    setState(() {
      _activeObjectIndex = index;
      _selectedVertices.clear();
      _selectedFaces.clear();
      _selectedFace = _mesh.faces.isEmpty ? null : 0;
      _tool = ActiveTool.select;
      _lockedAxis = null;
    });
  }

  void _setView(ViewPreset preset) {
    setState(() {
      _viewPreset = preset;
      _activeViewport.pan = Offset.zero;
      _activeViewport.zoom = 1;
    });
  }

  void _setViewportCount(int count) {
    setState(() {
      _visibleViewportCount = count.clamp(1, 4);
      _activeViewportIndex = 0;
      if (count == 1) {
        _viewports[0].preset = ViewPreset.free;
      } else {
        _viewports[0].preset = ViewPreset.front;
        _viewports[1].preset = ViewPreset.left;
        if (count == 4) {
          _viewports[2].preset = ViewPreset.free;
          _viewports[3].preset = ViewPreset.top;
        }
      }
    });
  }

  void _activateViewport(int index) {
    if (index == _activeViewportIndex) return;
    setState(() => _activeViewportIndex = index);
  }

  _ViewBasis _viewBasis([ViewportState? viewport]) {
    final view = viewport ?? _activeViewport;
    switch (view.preset) {
      case ViewPreset.front:
        return const _ViewBasis(
          Vec3(1, 0, 0),
          Vec3(0, 0, 1),
          Vec3(0, 1, 0),
        );
      case ViewPreset.back:
        return const _ViewBasis(
          Vec3(-1, 0, 0),
          Vec3(0, 0, 1),
          Vec3(0, -1, 0),
        );
      case ViewPreset.right:
        return const _ViewBasis(
          Vec3(0, 1, 0),
          Vec3(0, 0, 1),
          Vec3(1, 0, 0),
        );
      case ViewPreset.left:
        return const _ViewBasis(
          Vec3(0, -1, 0),
          Vec3(0, 0, 1),
          Vec3(-1, 0, 0),
        );
      case ViewPreset.top:
        return const _ViewBasis(
          Vec3(1, 0, 0),
          Vec3(0, 1, 0),
          Vec3(0, 0, 1),
        );
      case ViewPreset.bottom:
        return const _ViewBasis(
          Vec3(-1, 0, 0),
          Vec3(0, 1, 0),
          Vec3(0, 0, -1),
        );
      case ViewPreset.free:
        final cosYaw = math.cos(view.yaw);
        final sinYaw = math.sin(view.yaw);
        final cosPitch = math.cos(view.pitch);
        final sinPitch = math.sin(view.pitch);
        return _ViewBasis(
          Vec3(cosYaw, -sinYaw, 0),
          Vec3(sinYaw * cosPitch, cosYaw * cosPitch, -sinPitch),
          Vec3(sinYaw * sinPitch, cosYaw * sinPitch, cosPitch),
        );
    }
  }

  Vec3 _axisVector(MeshAxis axis) => switch (axis) {
        MeshAxis.x => const Vec3(1, 0, 0),
        MeshAxis.y => const Vec3(0, 1, 0),
        MeshAxis.z => const Vec3(0, 0, 1),
      };

  double _dot(Vec3 first, Vec3 second) =>
      first.x * second.x + first.y * second.y + first.z * second.z;

  void _toggleMoveTool() {
    setState(() {
      _tool = _tool == ActiveTool.move ? ActiveTool.select : ActiveTool.move;
      _lockedAxis = null;
    });
  }

  void _lockAxis(MeshAxis axis) {
    setState(() {
      _tool = ActiveTool.move;
      _lockedAxis = axis;
    });
  }

  void _duplicateSelection() {
    if (_mode == EditMode.vertex && _selectedVertices.isNotEmpty) {
      final duplicated = _mesh.duplicateVertices(_selectedVertices);
      if (duplicated.isEmpty) return;
      setState(() {
        _selectedVertices
          ..clear()
          ..addAll(duplicated);
        _tool = ActiveTool.move;
        _lockedAxis = null;
        _isDirty = true;
      });
      return;
    }
    final face = _selectedFace;
    if (_mode == EditMode.face && face != null) {
      final duplicatedFace = _mesh.duplicateFace(face);
      if (duplicatedFace == null) return;
      setState(() {
        _selectedFace = duplicatedFace;
        _selectedFaces
          ..clear()
          ..add(duplicatedFace);
        _tool = ActiveTool.move;
        _lockedAxis = null;
        _isDirty = true;
      });
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Select a vertex or face to duplicate.')),
    );
  }

  Set<int> get _verticesToMove {
    if (_mode == EditMode.face) {
      final face = _selectedFace;
      if (face != null && face >= 0 && face < _mesh.faces.length) {
        return _mesh.faces[face].vertices.toSet();
      }
      return {};
    }
    return _selectedVertices;
  }

  void _moveSelectedAlongAxis(
    Offset screenDelta,
    Size size,
    ViewportState viewport,
  ) {
    final axis = _lockedAxis;
    if (axis == null) return;
    final selected = _verticesToMove;
    if (selected.isEmpty) return;
    final basis = _viewBasis(viewport);
    final axisVector = _axisVector(axis);
    var screenAxis = Offset(
      _dot(axisVector, basis.right),
      -_dot(axisVector, basis.up),
    );
    var lengthSquared =
        screenAxis.dx * screenAxis.dx + screenAxis.dy * screenAxis.dy;
    if (lengthSquared < 0.02) {
      screenAxis = const Offset(0, -1);
      lengthSquared = 1;
    }
    final unitsPerPixel =
        screenAxis.dx * screenDelta.dx + screenAxis.dy * screenDelta.dy;
    final scale =
        math.min(size.width, size.height).toDouble() * 0.27 * viewport.zoom;
    final amount = unitsPerPixel / lengthSquared / scale;
    if (amount.abs() < 1e-9) return;
    final delta = axisVector;
    setState(() {
      _mesh.moveVertices(
        selected,
        Vec3(delta.x * amount, delta.y * amount, delta.z * amount),
      );
      _isDirty = true;
    });
  }

  void _duplicateIfRequested() => _duplicateSelection();

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_awaitingRotationAxis) {
      final axis = switch (key) {
        LogicalKeyboardKey.keyX => MeshAxis.x,
        LogicalKeyboardKey.keyY => MeshAxis.y,
        LogicalKeyboardKey.keyZ => MeshAxis.z,
        _ => null,
      };
      if (axis != null) {
        _awaitingRotationAxis = false;
        _rotationAxis = axis;
        _rotationDegrees = '';
        setState(() {});
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _awaitingRotationAxis = false;
        setState(() {});
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }
    if (_rotationAxis != null) {
      if (key == LogicalKeyboardKey.escape) {
        _rotationAxis = null;
        _rotationDegrees = '';
        setState(() {});
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        final degrees = double.tryParse(_rotationDegrees);
        final axis = _rotationAxis!;
        _rotationAxis = null;
        _rotationDegrees = '';
        if (degrees != null && degrees.isFinite) {
          _rotateSelection(axis, degrees);
        } else {
          _showMessage('Enter a valid rotation angle before pressing Enter.');
        }
        setState(() {});
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.backspace) {
        _rotationDegrees = _rotationDegrees.isEmpty
            ? ''
            : _rotationDegrees.substring(0, _rotationDegrees.length - 1);
        setState(() {});
        return KeyEventResult.handled;
      }
      final label = event.character;
      if (label != null &&
          RegExp(r'^[0-9.\-]$').hasMatch(label) &&
          !(_rotationDegrees.contains('.') && label == '.')) {
        _rotationDegrees += label;
        setState(() {});
      }
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed) {
      if (key == LogicalKeyboardKey.keyS) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          _saveScene(saveAs: true);
        } else {
          _saveScene();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyO) {
        _openScene();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyN) {
        _newScene();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyE) {
        _exportObj();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.keyM) {
      _toggleMoveTool();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR) {
      _awaitingRotationAxis = true;
      _showMessage('Press X, Y, or Z, type degrees, then press Enter.');
      setState(() {});
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyD &&
        HardwareKeyboard.instance.isShiftPressed) {
      _duplicateIfRequested();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyX) {
      if (_tool == ActiveTool.move) {
        _lockAxis(MeshAxis.x);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.keyY) {
      if (_tool == ActiveTool.move) {
        _lockAxis(MeshAxis.y);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.keyZ) {
      if (_tool == ActiveTool.move) {
        _lockAxis(MeshAxis.z);
        return KeyEventResult.handled;
      }
    }
    final view = switch (key) {
      LogicalKeyboardKey.numpad1 ||
      LogicalKeyboardKey.digit1 =>
        ViewPreset.front,
      LogicalKeyboardKey.numpad3 ||
      LogicalKeyboardKey.digit3 =>
        ViewPreset.right,
      LogicalKeyboardKey.numpad7 || LogicalKeyboardKey.digit7 => ViewPreset.top,
      LogicalKeyboardKey.numpad9 ||
      LogicalKeyboardKey.digit9 =>
        ViewPreset.back,
      LogicalKeyboardKey.numpad5 ||
      LogicalKeyboardKey.digit5 =>
        ViewPreset.free,
      _ => null,
    };
    if (view != null) {
      _setView(view);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.numpad2 ||
        key == LogicalKeyboardKey.numpad4 ||
        key == LogicalKeyboardKey.numpad6 ||
        key == LogicalKeyboardKey.numpad8) {
      setState(() {
        _viewPreset = ViewPreset.free;
        if (key == LogicalKeyboardKey.numpad2) _pitch -= 0.18;
        if (key == LogicalKeyboardKey.numpad8) _pitch += 0.18;
        if (key == LogicalKeyboardKey.numpad4) _yaw -= 0.18;
        if (key == LogicalKeyboardKey.numpad6) _yaw += 0.18;
        _pitch = _pitch.clamp(-1.45, 1.45).toDouble();
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _loadReferenceImage() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Reference images',
          extensions: ['png', 'jpg', 'jpeg', 'bmp', 'webp'],
        ),
      ],
    );
    if (file == null) return;
    final bytes = await File(file.path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() {
      _referenceImages.remove(_viewPreset)?.dispose();
      _referenceImages[_viewPreset] = frame.image;
    });
  }

  void _removeReferenceImage() {
    setState(() => _referenceImages.remove(_viewPreset)?.dispose());
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
      _selectedFaces
        ..clear()
        ..add(_selectedFace!);
      _mode = EditMode.face;
      _tool = ActiveTool.select;
      _isDirty = true;
    });
  }

  void _mergeSelectedTriangles() {
    final merged = _mesh.mergeTriangles(_selectedFaces);
    if (merged == null) {
      _showMessage('Select two adjacent triangular faces to make a quad.');
      return;
    }
    setState(() {
      _selectedFace = merged;
      _selectedFaces
        ..clear()
        ..add(merged);
      _mode = EditMode.face;
      _isDirty = true;
    });
  }

  void _toggleStripTool() {
    setState(() {
      if (_tool == ActiveTool.strip) {
        _tool = ActiveTool.select;
        _stripEdge.clear();
        return;
      }
      _tool = ActiveTool.strip;
      _stripEdge
        ..clear()
        ..addAll(_selectedVertices.length == 2
            ? (_selectedVertices.toList()..sort())
            : const []);
    });
  }

  void _addStripPoint(Offset point, Size size, ViewportState viewport) {
    final vertex = _mesh.addVertex(_worldPosition(point, size, viewport));
    if (_stripEdge.length < 2) {
      setState(() {
        _stripEdge.add(vertex);
        _selectedVertices
          ..clear()
          ..addAll(_stripEdge);
        _isDirty = true;
      });
      return;
    }
    if (!_mesh.addTriangle([_stripEdge[0], _stripEdge[1], vertex])) {
      _mesh.vertices.removeLast();
      _showMessage('That point would create a duplicate or flat triangle.');
      return;
    }
    setState(() {
      _stripEdge
        ..removeAt(0)
        ..add(vertex);
      _selectedVertices
        ..clear()
        ..addAll(_stripEdge);
      _selectedFace = _mesh.faces.length - 1;
      _selectedFaces
        ..clear()
        ..add(_selectedFace!);
      _isDirty = true;
    });
  }

  Set<int> get _verticesToRotate {
    if (_mode == EditMode.face) {
      if (_selectedFaces.isNotEmpty) {
        return _selectedFaces
            .where((index) => index >= 0 && index < _mesh.faces.length)
            .expand((index) => _mesh.faces[index].vertices)
            .toSet();
      }
      if (_selectedFace != null && _selectedFace! < _mesh.faces.length) {
        return _mesh.faces[_selectedFace!].vertices.toSet();
      }
      return Set<int>.from(
          List.generate(_mesh.vertices.length, (index) => index));
    }
    return _selectedVertices.isEmpty
        ? Set<int>.from(List.generate(_mesh.vertices.length, (index) => index))
        : _selectedVertices;
  }

  void _rotateSelection(MeshAxis axis, double degrees) {
    if (!_mesh.rotateVertices(
      _verticesToRotate,
      axis.index,
      degrees,
    )) {
      _showMessage('Select vertices, a face, or a mesh to rotate.');
      return;
    }
    setState(() => _isDirty = true);
  }

  Future<void> _showRotateDialog() async {
    final degrees = TextEditingController(text: '90');
    var axis = MeshAxis.x;
    final result = await showDialog<(MeshAxis, double)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rotate selection'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<MeshAxis>(
                segments: const [
                  ButtonSegment(value: MeshAxis.x, label: Text('X')),
                  ButtonSegment(value: MeshAxis.y, label: Text('Y')),
                  ButtonSegment(value: MeshAxis.z, label: Text('Z')),
                ],
                selected: {axis},
                onSelectionChanged: (selection) =>
                    setDialogState(() => axis = selection.first),
              ),
              TextField(
                controller: degrees,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(signed: true),
                decoration: const InputDecoration(
                  labelText: 'Degrees',
                  suffixText: '°',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(degrees.text);
                if (value != null && value.isFinite) {
                  Navigator.pop(context, (axis, value));
                }
              },
              child: const Text('Rotate'),
            ),
          ],
        ),
      ),
    );
    degrees.dispose();
    if (result != null) _rotateSelection(result.$1, result.$2);
  }

  Future<void> _mirrorActiveMesh() async {
    final axis = await showDialog<MeshAxis>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Mirror active mesh'),
        children: [
          for (final axis in MeshAxis.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, axis),
              child: Text('Mirror across ${axis.name.toUpperCase()} axis'),
            ),
        ],
      ),
    );
    if (axis == null || !_mesh.mirror(axis.index)) return;
    setState(() {
      _selectedVertices.clear();
      _selectedFaces.clear();
      _selectedFace = _mesh.faces.isEmpty ? null : 0;
      _isDirty = true;
    });
  }

  Future<void> _deleteActiveMesh() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete active mesh?'),
        content: Text('Delete "${_objects[_activeObjectIndex].name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = _objects[_activeObjectIndex];
    removed.textureImage?.dispose();
    setState(() {
      if (_objects.length == 1) {
        _objects[0] = SceneObject(removed.name, MeshModel.empty());
      } else {
        _objects.removeAt(_activeObjectIndex);
        _activeObjectIndex = math.min(_activeObjectIndex, _objects.length - 1);
      }
      _selectedVertices.clear();
      _selectedFaces.clear();
      _selectedFace = _mesh.faces.isEmpty ? null : 0;
      _isDirty = true;
    });
  }

  void _deleteFace() {
    final face = _selectedFace;
    if (face == null || !_mesh.removeFace(face)) return;
    setState(() {
      _selectedFace = _mesh.faces.isEmpty
          ? null
          : (face < _mesh.faces.length ? face : _mesh.faces.length - 1);
      _selectedFaces
        ..clear()
        ..addAll(_selectedFace == null ? const [] : [_selectedFace!]);
      _isDirty = true;
    });
  }

  void _handleModelTap(
    Offset point,
    Size size,
    ViewportState viewport,
  ) {
    if (_tool == ActiveTool.strip && _mode == EditMode.vertex) {
      _addStripPoint(point, size, viewport);
      return;
    }
    if (_tool == ActiveTool.addVertex && _mode == EditMode.vertex) {
      final index = _mesh.addVertex(_worldPosition(point, size, viewport));
      setState(() {
        _selectedVertices.add(index);
        _isDirty = true;
      });
      return;
    }

    if (_mode == EditMode.vertex) {
      final hit = _nearestVertex(point, size, viewport);
      setState(() {
        if (hit != null) {
          if (!_selectedVertices.add(hit)) _selectedVertices.remove(hit);
        } else {
          _selectedVertices.clear();
        }
      });
    } else {
      final hit = _hitFace(point, size, viewport);
      setState(() {
        if (hit == null) {
          _selectedFace = null;
          _selectedFaces.clear();
        } else {
          if (_selectedFaces.contains(hit)) {
            _selectedFaces.remove(hit);
            _selectedFace = _selectedFaces.isEmpty ? null : _selectedFaces.last;
          } else {
            _selectedFaces.add(hit);
            _selectedFace = hit;
          }
        }
      });
    }
  }

  Offset _project(Vec3 point, Size size, [ViewportState? viewport]) {
    final view = viewport ?? _activeViewport;
    final basis = _viewBasis(view);
    final horizontal = _dot(point, basis.right);
    final vertical = _dot(point, basis.up);
    final scale =
        math.min(size.width, size.height).toDouble() * 0.27 * view.zoom;
    return Offset(
      size.width / 2 + view.pan.dx + horizontal * scale,
      size.height / 2 + view.pan.dy - vertical * scale,
    );
  }

  Vec3 _worldPosition(
    Offset screenPoint,
    Size size,
    ViewportState viewport,
  ) {
    final scale =
        math.min(size.width, size.height).toDouble() * 0.27 * viewport.zoom;
    final basis = _viewBasis(viewport);
    final horizontal =
        (screenPoint.dx - size.width / 2 - viewport.pan.dx) / scale;
    final vertical =
        -(screenPoint.dy - size.height / 2 - viewport.pan.dy) / scale;
    return Vec3(
      basis.right.x * horizontal + basis.up.x * vertical,
      basis.right.y * horizontal + basis.up.y * vertical,
      basis.right.z * horizontal + basis.up.z * vertical,
    );
  }

  double _zoomForWheel(double scrollDelta, double currentZoom) =>
      (currentZoom * math.exp(-scrollDelta * 0.0015))
          .clamp(_minZoom, _maxZoom)
          .toDouble();

  void _zoomBy(double factor, ViewportState viewport, int viewportIndex) {
    _activeViewportIndex = viewportIndex;
    setState(() {
      viewport.zoom =
          (viewport.zoom * factor).clamp(_minZoom, _maxZoom).toDouble();
    });
  }

  void _fitScene(Size size, ViewportState viewport, int viewportIndex) {
    final points = _objects
        .expand((object) => object.mesh.vertices)
        .map((vertex) => vertex.position)
        .toList();
    if (points.isEmpty) return;
    final basis = _viewBasis(viewport);
    final horizontal = points.map((point) => _dot(point, basis.right)).toList();
    final vertical = points.map((point) => _dot(point, basis.up)).toList();
    final minX = horizontal.reduce(math.min);
    final maxX = horizontal.reduce(math.max);
    final minY = vertical.reduce(math.min);
    final maxY = vertical.reduce(math.max);
    final spanX = math.max(maxX - minX, 0.25);
    final spanY = math.max(maxY - minY, 0.25);
    final scale = math.min(size.width, size.height).toDouble() * 0.27;
    setState(() {
      viewport.zoom =
          (math.min(size.width / spanX, size.height / spanY) * 0.78 / scale)
              .clamp(_minZoom, _maxZoom)
              .toDouble();
      viewport.pan = Offset(
        size.width / 2 - ((minX + maxX) / 2) * scale * viewport.zoom,
        size.height / 2 + ((minY + maxY) / 2) * scale * viewport.zoom,
      );
      _activeViewportIndex = viewportIndex;
    });
  }

  List<ModelMeshData> _documentData() => _objects
      .map(
        (object) => ModelMeshData(
          name: object.name,
          mesh: object.mesh,
          texturePath: object.texturePath,
        ),
      )
      .toList();

  Future<void> _saveScene({bool saveAs = false}) async {
    if (_isSaving) return;
    var path = _currentFilePath;
    if (saveAs || path == null) {
      final location = await getSaveLocation(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Blunder project', extensions: ['pky']),
        ],
        suggestedName: 'Blunder_Scene.pky',
        confirmButtonText: 'Save',
      );
      if (location == null) return;
      path = location.path.toLowerCase().endsWith('.pky')
          ? location.path
          : '${location.path}.pky';
    }
    setState(() => _isSaving = true);
    try {
      await ModelIo.writePky(path, _documentData());
      if (!mounted) return;
      setState(() {
        _currentFilePath = path;
        _isDirty = false;
      });
      _showMessage('Saved ${File(path).uri.pathSegments.last}');
    } catch (error) {
      _showMessage('Could not save the scene: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _exportObj() async {
    final location = await getSaveLocation(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Wavefront OBJ', extensions: ['obj']),
      ],
      suggestedName: 'Blunder_Export.obj',
      confirmButtonText: 'Export',
    );
    if (location == null) return;
    final path = location.path.toLowerCase().endsWith('.obj')
        ? location.path
        : '${location.path}.obj';
    try {
      await ModelIo.writeObj(path, _documentData());
      if (mounted) _showMessage('Exported ${File(path).uri.pathSegments.last}');
    } catch (error) {
      if (mounted) _showMessage('Could not export OBJ: $error');
    }
  }

  Future<void> _openScene() async {
    if (!await _confirmUnsavedChanges()) return;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Blunder project', extensions: ['pky']),
      ],
      confirmButtonText: 'Open',
    );
    if (file == null) return;
    await _loadScenePath(file.path);
  }

  Future<void> _loadScenePath(String path) async {
    try {
      final imported = await ModelIo.readPky(path);
      final loadedObjects = <SceneObject>[];
      for (final object in imported) {
        var texturePath = object.texturePath;
        if (texturePath != null && !File(texturePath).isAbsolute) {
          texturePath = '${File(path).parent.path}\\$texturePath';
        }
        final textureImage =
            texturePath != null && await File(texturePath).exists()
                ? await _decodeImage(await File(texturePath).readAsBytes())
                : null;
        loadedObjects.add(
          SceneObject(
            object.name,
            object.mesh,
            texturePath: texturePath,
            textureImage: textureImage,
          ),
        );
      }
      for (final object in _objects) {
        object.textureImage?.dispose();
      }
      setState(() {
        _objects
          ..clear()
          ..addAll(loadedObjects);
        if (_objects.isEmpty) {
          _objects.add(SceneObject('Mesh_1', MeshModel.empty()));
        }
        _activeObjectIndex = 0;
        _selectedVertices.clear();
        _selectedFaces.clear();
        _selectedFace = _mesh.faces.isEmpty ? null : 0;
        _tool = ActiveTool.select;
        _lockedAxis = null;
        _currentFilePath = path;
        _isDirty = false;
        _page = EditorPage.model;
      });
      _showMessage('Opened ${File(path).uri.pathSegments.last}');
    } catch (error) {
      _showMessage('Could not open PKY file: $error');
    }
  }

  Future<bool> _confirmUnsavedChanges() async {
    if (!_isDirty) return true;
    final choice = await showDialog<_UnsavedChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Save changes to this scene before continuing?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _UnsavedChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _UnsavedChoice.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _UnsavedChoice.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (choice == _UnsavedChoice.discard) return true;
    if (choice == _UnsavedChoice.save) {
      await _saveScene();
      return !_isDirty;
    }
    return false;
  }

  Future<void> _newScene() async {
    if (!await _confirmUnsavedChanges()) return;
    for (final object in _objects) {
      object.textureImage?.dispose();
    }
    setState(() {
      _objects
        ..clear()
        ..add(SceneObject('Mesh_1', MeshModel.starterPlane()));
      _activeObjectIndex = 0;
      _selectedVertices.clear();
      _selectedFaces.clear();
      _selectedFace = 0;
      _tool = ActiveTool.select;
      _lockedAxis = null;
      _currentFilePath = null;
      _isDirty = false;
      _page = EditorPage.model;
      _activeViewport.zoom = 1;
      _activeViewport.pan = Offset.zero;
    });
  }

  Future<void> _exitApplication() async {
    if (!await _confirmUnsavedChanges()) return;
    exit(0);
  }

  Future<void> _loadTexture() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Texture images',
          extensions: ['png', 'jpg', 'jpeg', 'bmp', 'webp'],
        ),
      ],
    );
    if (file == null) return;
    try {
      final image = await _decodeImage(await File(file.path).readAsBytes());
      final object = _objects[_activeObjectIndex];
      object.textureImage?.dispose();
      setState(() {
        object.texturePath = file.path;
        object.textureImage = image;
        _isDirty = true;
      });
    } catch (error) {
      if (mounted) _showMessage('Could not load texture: $error');
    }
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  Future<void> _registerPkyAssociation() async {
    final executable = Platform.resolvedExecutable;
    final iconValue = '"$executable",0';
    final commandValue = '"$executable" "%1"';
    final registrations = <(String, String)>[
      (r'Software\Classes\.pky', 'Blunder.PKY'),
      (r'Software\Classes\Blunder.PKY', 'Blunder project'),
      (r'Software\Classes\Blunder.PKY\DefaultIcon', iconValue),
      (r'Software\Classes\Blunder.PKY\shell\open\command', commandValue),
    ];
    try {
      for (final (key, value) in registrations) {
        final result = await Process.run('reg.exe', [
          'add',
          'HKCU\\$key',
          '/ve',
          '/d',
          value,
          '/f',
        ]);
        if (result.exitCode != 0) {
          throw ProcessException(
            'reg.exe',
            ['add', 'HKCU\\$key'],
            '${result.stderr}'.trim(),
            result.exitCode,
          );
        }
      }
    } catch (error) {
      _showMessage('Could not register the .pky file icon: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  int? _nearestVertex(Offset point, Size size, ViewportState viewport) {
    int? nearest;
    var nearestDistance = 24.0;
    for (var i = 0; i < _mesh.vertices.length; i++) {
      final distance =
          (_project(_mesh.vertices[i].position, size, viewport) - point)
              .distance;
      if (distance < nearestDistance) {
        nearest = i;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  int? _hitFace(Offset point, Size size, ViewportState viewport) {
    for (var faceIndex = _mesh.faces.length - 1; faceIndex >= 0; faceIndex--) {
      final face = _mesh.faces[faceIndex];
      final path = Path()
        ..addPolygon(
          face.vertices
              .map((index) =>
                  _project(_mesh.vertices[index].position, size, viewport))
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
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 44,
          titleSpacing: 8,
          leadingWidth: 0,
          leading: const SizedBox.shrink(),
          automaticallyImplyLeading: false,
          title: LayoutBuilder(
            builder: (context, constraints) {
              final fillWidth = constraints.maxWidth >= 700;
              final menuRow = Row(
                mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  _dropMenu(
                    'File',
                    [
                      const PopupMenuItem(
                          value: 'new', child: Text('New scene')),
                      const PopupMenuItem(
                          value: 'open', child: Text('Open .pky…')),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'save',
                        child: Text(_isSaving ? 'Saving…' : 'Save scene'),
                      ),
                      const PopupMenuItem(
                        value: 'saveAs',
                        child: Text('Save scene as…'),
                      ),
                      const PopupMenuItem(
                        value: 'export',
                        child: Text('Export as .obj…'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'exit', child: Text('Exit')),
                    ],
                    (value) {
                      switch (value) {
                        case 'new':
                          _newScene();
                        case 'open':
                          _openScene();
                        case 'save':
                          _saveScene();
                        case 'saveAs':
                          _saveScene(saveAs: true);
                        case 'export':
                          _exportObj();
                        case 'exit':
                          _exitApplication();
                      }
                    },
                  ),
                  _dropMenu(
                    'View',
                    [
                      for (final view in ViewPreset.values)
                        PopupMenuItem(
                          value: 'view_${view.name}',
                          child: Text(_viewName(view)),
                        ),
                    ],
                    (value) => _setView(
                      ViewPreset.values.firstWhere(
                        (view) => 'view_${view.name}' == value,
                      ),
                    ),
                  ),
                  _dropMenu(
                    'Mesh',
                    const [
                      PopupMenuItem(value: 'newMesh', child: Text('New mesh')),
                      PopupMenuItem(value: 'mirror', child: Text('Mirror…')),
                      PopupMenuItem(
                        value: 'rotate',
                        child: Text('Rotate selection…  (R)'),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'deleteMesh',
                        child: Text('Delete active mesh…'),
                      ),
                    ],
                    (value) {
                      switch (value) {
                        case 'newMesh':
                          _addMesh();
                        case 'mirror':
                          _mirrorActiveMesh();
                        case 'rotate':
                          _showRotateDialog();
                        case 'deleteMesh':
                          _deleteActiveMesh();
                      }
                    },
                  ),
                  _dropMenu(
                    'Scene',
                    const [
                      PopupMenuItem(value: 'model', child: Text('Model')),
                      PopupMenuItem(value: 'uv', child: Text('UV Map')),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'solid', child: Text('Solid view')),
                      PopupMenuItem(
                        value: 'textured',
                        child: Text('Textured'),
                      ),
                      PopupMenuItem(
                        value: 'wireframe',
                        child: Text('Wireframe'),
                      ),
                    ],
                    (value) => setState(() {
                      switch (value) {
                        case 'model':
                          _page = EditorPage.model;
                        case 'uv':
                          _page = EditorPage.uv;
                        case 'textured':
                          _page = EditorPage.model;
                          _viewStyle = ViewStyle.textured;
                        case 'solid':
                          _page = EditorPage.model;
                          _viewStyle = ViewStyle.solid;
                        case 'wireframe':
                          _page = EditorPage.model;
                          _viewStyle = ViewStyle.wireframe;
                      }
                    }),
                  ),
                  _dropMenu(
                    'Add',
                    const [
                      PopupMenuItem(
                        value: 'reference',
                        child: Text('Reference image…'),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'layout1',
                        child: Text('Single viewport'),
                      ),
                      PopupMenuItem(
                        value: 'layout2',
                        child: Text('Scene'),
                      ),
                      PopupMenuItem(
                        value: 'layout4',
                        child: Text('Scene: 4 views'),
                      ),
                    ],
                    (value) {
                      switch (value) {
                        case 'reference':
                          _loadReferenceImage();
                        case 'layout1':
                          _setViewportCount(1);
                        case 'layout2':
                          _setViewportCount(2);
                        case 'layout4':
                          _setViewportCount(4);
                      }
                    },
                  ),
                  if (fillWidth) const Spacer() else const SizedBox(width: 4),
                  const SizedBox(width: 5),
                  Container(
                    height: 24,
                    width: 1,
                    color: const Color(0xFF48505E),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                  ),
                  if (_page == EditorPage.model)
                    _buildCompactEditorTools()
                  else
                    IconButton(
                      tooltip: 'Choose texture',
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints.tightFor(width: 30, height: 30),
                      padding: EdgeInsets.zero,
                      onPressed: _loadTexture,
                      icon: const Icon(Icons.texture_rounded, size: 17),
                    ),
                ],
              );
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: fillWidth
                    ? SizedBox(width: constraints.maxWidth, child: menuRow)
                    : menuRow,
              );
            },
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
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
      ),
    );
  }

  Widget _dropMenu(
    String label,
    List<PopupMenuEntry<String>> items,
    ValueChanged<String> onSelected,
  ) {
    final controller = _menuControllers.putIfAbsent(label, MenuController.new);
    final menuChildren = <Widget>[];
    for (final entry in items) {
      if (entry is PopupMenuDivider) {
        menuChildren.add(const Divider(height: 1));
      } else if (entry is PopupMenuItem<String>) {
        final value = entry.value;
        menuChildren.add(
          MenuItemButton(
            onPressed: value == null
                ? null
                : () {
                    controller.close();
                    onSelected(value);
                  },
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 13),
              child: entry.child ?? const SizedBox.shrink(),
            ),
          ),
        );
      }
    }
    return MenuAnchor(
      controller: controller,
      consumeOutsideTap: false,
      menuChildren: menuChildren,
      builder: (context, menuController, child) => Tooltip(
        message: '$label menu',
        child: TextButton(
          onPressed: () {
            if (menuController.isOpen) {
              menuController.close();
            } else {
              menuController.open();
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size(0, 30),
            padding: const EdgeInsets.symmetric(horizontal: 5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              Icon(
                menuController.isOpen
                    ? Icons.arrow_drop_up
                    : Icons.arrow_drop_down,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactEditorTools() {
    final enabled = _mode == EditMode.vertex
        ? _selectedVertices.length == 4
        : _selectedFaces.length == 2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<EditMode>(
          segments: const [
            ButtonSegment(
              value: EditMode.vertex,
              icon: Icon(Icons.circle_outlined, size: 14),
              label: Text('V'),
              tooltip: 'Vertex selection',
            ),
            ButtonSegment(
              value: EditMode.face,
              icon: Icon(Icons.crop_square_rounded, size: 14),
              label: Text('F'),
              tooltip: 'Face selection',
            ),
          ],
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 4),
            ),
            textStyle: WidgetStatePropertyAll(
              TextStyle(fontSize: 11),
            ),
          ),
          selected: {_mode},
          onSelectionChanged: (selection) {
            setState(() {
              _mode = selection.first;
              _tool = ActiveTool.select;
              _stripEdge.clear();
            });
          },
        ),
        _compactTool(
          label: 'Add vertex',
          icon: Icons.add_circle_outline_rounded,
          selected: _tool == ActiveTool.addVertex,
          onPressed: _mode != EditMode.vertex
              ? null
              : () => setState(() {
                    _tool = _tool == ActiveTool.addVertex
                        ? ActiveTool.select
                        : ActiveTool.addVertex;
                    _stripEdge.clear();
                  }),
        ),
        _compactTool(
          label: _tool == ActiveTool.strip ? 'Stop strip' : 'Strip',
          icon: Icons.linear_scale_rounded,
          selected: _tool == ActiveTool.strip,
          onPressed: _mode == EditMode.vertex ? _toggleStripTool : null,
        ),
        _compactTool(
          label:
              _mode == EditMode.face ? 'Merge triangles to quad' : 'Make quad',
          icon: Icons.change_history_rounded,
          onPressed: !enabled
              ? null
              : _mode == EditMode.face
                  ? _mergeSelectedTriangles
                  : _connectVertices,
        ),
        _compactTool(
          label: 'Move (M)',
          icon: Icons.open_with_rounded,
          selected: _tool == ActiveTool.move,
          onPressed: () {
            _toggleMoveTool();
          },
        ),
        if (_tool == ActiveTool.move)
          PopupMenuButton<MeshAxis>(
            tooltip: 'Constrain movement to axis',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            iconSize: 17,
            icon: Icon(
              Icons.straighten_rounded,
              color: _lockedAxis == null ? null : const Color(0xFF9FBEFF),
            ),
            onSelected: _lockAxis,
            itemBuilder: (context) => [
              for (final axis in MeshAxis.values)
                PopupMenuItem(
                  value: axis,
                  child: Text(axis.name.toUpperCase()),
                ),
            ],
          ),
        PopupMenuButton<String>(
          tooltip: 'More editing tools',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 30, height: 30),
          iconSize: 17,
          icon: const Icon(Icons.more_horiz),
          onSelected: (value) {
            switch (value) {
              case 'duplicate':
                _duplicateSelection();
              case 'delete':
                _deleteFace();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'duplicate',
              child: Text('Duplicate selection'),
            ),
            if (_mode == EditMode.face)
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete selected face'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _compactTool({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool selected = false,
  }) {
    return IconButton(
      tooltip: label,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      color: selected ? const Color(0xFF9FBEFF) : null,
      iconSize: 17,
      icon: Icon(icon),
    );
  }

  String _viewName(ViewPreset view) => switch (view) {
        ViewPreset.free => 'Free',
        ViewPreset.front => 'Front',
        ViewPreset.back => 'Back',
        ViewPreset.right => 'Right',
        ViewPreset.left => 'Left',
        ViewPreset.top => 'Top',
        ViewPreset.bottom => 'Bottom',
      };

  Widget _buildWorkspace() =>
      _page == EditorPage.model ? _buildViewportWorkspace() : _buildUvEditor();

  Widget _buildWideWorkspace() {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          width: _isSidePanelVisible ? 220 : 36,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 220,
              maxWidth: 220,
              child: _isSidePanelVisible
                  ? _buildSidePanel()
                  : SizedBox(
                      width: 220,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 36,
                          child: Center(
                            child: IconButton(
                              tooltip: 'Show scene panel',
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  setState(() => _isSidePanelVisible = true),
                              icon: const Icon(Icons.add),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
        SizedBox(width: _isSidePanelVisible ? 12 : 6),
        Expanded(
          child: _page == EditorPage.model
              ? _buildViewportWorkspace()
              : _buildUvEditor(),
        ),
      ],
    );
  }

  Widget _buildViewportWorkspace() {
    if (_visibleViewportCount == 1) return _buildViewport(0);
    final panes = List.generate(
      _visibleViewportCount,
      (index) => _buildViewport(index),
    );
    if (_visibleViewportCount == 2) {
      return Row(
        children: [
          Expanded(child: panes[0]),
          const SizedBox(width: 6),
          Expanded(child: panes[1]),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: panes[0]),
              const SizedBox(width: 6),
              Expanded(child: panes[1]),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Row(
            children: [
              Expanded(child: panes[2]),
              const SizedBox(width: 6),
              Expanded(child: panes[3]),
            ],
          ),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  _page == EditorPage.model ? 'SCENE' : 'UV MAPPING',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.4,
                        color: Colors.white54,
                      ),
                ),
              ),
              IconButton(
                tooltip: 'Hide scene panel',
                visualDensity: VisualDensity.compact,
                constraints:
                    const BoxConstraints.tightFor(width: 28, height: 28),
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _isSidePanelVisible = false),
                icon: const Icon(Icons.chevron_left, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _pageButton(EditorPage.model, Icons.view_in_ar_rounded, 'Model'),
          const SizedBox(height: 6),
          _pageButton(EditorPage.uv, Icons.grid_on_rounded, 'UV layout'),
          if (_page == EditorPage.model) ...[
            const Divider(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'MESHES',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.2,
                          color: Colors.white54,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Add mesh',
                  visualDensity: VisualDensity.compact,
                  onPressed: _addMesh,
                  icon: const Icon(Icons.add, size: 20),
                ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _objects.length,
                itemBuilder: (context, index) {
                  final object = _objects[index];
                  final active = index == _activeObjectIndex;
                  return Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: ListTile(
                      dense: true,
                      selected: active,
                      selectedTileColor: const Color(0xFF283955),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      leading: const Icon(Icons.view_in_ar_rounded, size: 18),
                      title: Text(object.name),
                      subtitle: Text(
                        '${object.mesh.vertices.length} vertices · '
                        '${object.mesh.faces.length} faces',
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: () => _selectMesh(index),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _resetPlane,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Reset active mesh'),
              ),
            ),
            const SizedBox(height: 8),
            if (_referenceImages.containsKey(_viewPreset)) ...[
              Row(
                children: [
                  const Expanded(child: Text('Reference opacity')),
                  IconButton(
                    tooltip: 'Remove reference image',
                    visualDensity: VisualDensity.compact,
                    onPressed: _removeReferenceImage,
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ),
              Slider(
                value: _referenceOpacity,
                onChanged: (value) => setState(() => _referenceOpacity = value),
              ),
            ],
          ] else ...[
            const Divider(height: 28),
            Text('UV MAPPING', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 10),
            Text(
              '${_objects.length} meshes in scene',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white60,
                  ),
            ),
            const Spacer(),
          ],
          Text(
            _page == EditorPage.model
                ? 'Numpad 1 / 3 / 7: front, right, top\n'
                    'Numpad 2 / 4 / 6 / 8: orbit\n'
                    'M, then X / Y / Z: constrained move\n'
                    'Shift+D: duplicate selection'
                : 'Drag a UV corner to adjust the mapping',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                  height: 1.45,
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

  Widget _buildViewport(int viewportIndex) {
    final viewport = _viewports[viewportIndex];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF171B23),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: viewportIndex == _activeViewportIndex
              ? const Color(0xFF4E8DFF)
              : const Color(0xFF282E39),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                _activeViewportIndex = viewportIndex;
                final keyboard = HardwareKeyboard.instance;
                if (keyboard.isLogicalKeyPressed(
                  LogicalKeyboardKey.controlLeft,
                )) {
                  setState(() {
                    viewport.pan += Offset(-event.scrollDelta.dy, 0);
                  });
                } else if (keyboard.isLogicalKeyPressed(
                  LogicalKeyboardKey.shiftLeft,
                )) {
                  setState(() {
                    viewport.pan += Offset(0, -event.scrollDelta.dy);
                  });
                } else {
                  setState(() {
                    viewport.zoom = _zoomForWheel(
                      event.scrollDelta.dy,
                      viewport.zoom,
                    );
                  });
                }
              }
            },
            child: GestureDetector(
              key: ValueKey(
                viewportIndex == 0
                    ? 'modelViewport'
                    : 'modelViewport$viewportIndex',
              ),
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => _activateViewport(viewportIndex),
              onTapUp: (details) =>
                  _handleModelTap(details.localPosition, size, viewport),
              onScaleStart: (details) {
                _activeViewportIndex = viewportIndex;
                _gestureAnchor = details.focalPoint;
                _gestureZoomStart = viewport.zoom;
              },
              onScaleUpdate: (details) {
                if (details.pointerCount >= 2) {
                  setState(() {
                    viewport.pan += details.focalPoint - _gestureAnchor;
                    viewport.zoom = (_gestureZoomStart * details.scale)
                        .clamp(_minZoom, _maxZoom)
                        .toDouble();
                    _gestureAnchor = details.focalPoint;
                  });
                } else if (_tool == ActiveTool.move && _lockedAxis != null) {
                  _moveSelectedAlongAxis(
                    details.focalPointDelta,
                    size,
                    viewport,
                  );
                } else if (_tool != ActiveTool.addVertex &&
                    _tool != ActiveTool.strip &&
                    _tool != ActiveTool.move) {
                  setState(() {
                    viewport.preset = ViewPreset.free;
                    viewport.yaw += details.focalPointDelta.dx * 0.008;
                    viewport.pitch =
                        (viewport.pitch + details.focalPointDelta.dy * 0.008)
                            .clamp(-1.45, 1.45)
                            .toDouble();
                  });
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _ViewportPainter(
                      meshes: _objects.map((object) => object.mesh).toList(),
                      textures: _objects
                          .map((object) => object.textureImage)
                          .toList(),
                      activeMeshIndex: _activeObjectIndex,
                      selectedVertices: _selectedVertices,
                      selectedFaces: _selectedFaces,
                      selectedFace: _selectedFace,
                      project: (point) => _project(point, size, viewport),
                      basis: _viewBasis(viewport),
                      viewPreset: viewport.preset,
                      referenceImage: _referenceImages[viewport.preset],
                      referenceOpacity: _referenceOpacity,
                      viewStyle: _viewStyle,
                      fade: ((viewport.zoom - _minZoom) / 0.18).clamp(0.0, 1.0),
                      showVertices: _mode == EditMode.vertex ||
                          _viewStyle == ViewStyle.wireframe,
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: _zoomControls(size, viewport, viewportIndex),
                  ),
                  Positioned(
                    left: 12,
                    top: 10,
                    child: Text(
                      _viewName(viewport.preset),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white70,
                            backgroundColor: const Color(0xAA171B23),
                          ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 48,
                    child: PopupMenuButton<ViewPreset>(
                      tooltip: 'Change view',
                      icon: const Icon(Icons.visibility_outlined, size: 19),
                      onOpened: () => _activateViewport(viewportIndex),
                      onSelected: (view) {
                        _activateViewport(viewportIndex);
                        _setView(view);
                      },
                      itemBuilder: (context) => [
                        for (final view in ViewPreset.values)
                          PopupMenuItem(
                            value: view,
                            child: Text(_viewName(view)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _zoomControls(
    Size size,
    ViewportState viewport,
    int viewportIndex,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE6171B23),
        border: Border.all(color: const Color(0xFF394252)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Zoom in',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 23, height: 23),
              padding: EdgeInsets.zero,
              iconSize: 15,
              onPressed: () => _zoomBy(1.25, viewport, viewportIndex),
              icon: const Icon(Icons.add),
            ),
            Text(
              '${(viewport.zoom * 100).round()}%',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                  ),
            ),
            IconButton(
              tooltip: 'Zoom out',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 23, height: 23),
              padding: EdgeInsets.zero,
              iconSize: 15,
              onPressed: () => _zoomBy(0.8, viewport, viewportIndex),
              icon: const Icon(Icons.remove),
            ),
            IconButton(
              tooltip: 'Frame all meshes',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 23, height: 23),
              padding: EdgeInsets.zero,
              iconSize: 14,
              onPressed: () => _fitScene(size, viewport, viewportIndex),
              icon: const Icon(Icons.fit_screen_rounded),
            ),
          ],
        ),
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
                    setState(() {
                      _mesh.updateUv(faceIndex, corner, uv);
                      _isDirty = true;
                    });
                  },
            onPanEnd: faceIndex == null ? null : (_) => _draggingUvCorner = -1,
            child: CustomPaint(
              size: size,
              painter: _UvPainter(
                face: faceIndex == null ? null : _mesh.faces[faceIndex],
                texture: _objects[_activeObjectIndex].textureImage,
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
              'Drag: orbit · M then X/Y/Z: move · Shift+D: duplicate',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white38,
                  ),
            ),
        ],
      ),
    );
  }

  String _statusText() {
    if (_awaitingRotationAxis) {
      return 'Rotate: press X, Y, or Z to choose an axis';
    }
    if (_rotationAxis != null) {
      return 'Rotate ${_rotationAxis!.name.toUpperCase()}: '
          '${_rotationDegrees.isEmpty ? 'type degrees' : _rotationDegrees} · Enter';
    }
    if (_page == EditorPage.uv) {
      final texture = _objects[_activeObjectIndex].texturePath;
      return texture == null
          ? 'Choose a texture, then drag UV corners over it'
          : _selectedFace == null
              ? 'Select a face to edit its UVs'
              : 'Face ${_selectedFace! + 1}  ·  Drag a corner to map';
    }
    if (_tool == ActiveTool.addVertex) {
      return 'Tap the surface to place a vertex';
    }
    if (_tool == ActiveTool.strip) {
      return switch (_stripEdge.length) {
        0 => 'Strip: place two starting vertices',
        1 => 'Strip: place the second starting vertex',
        _ => 'Strip: place next vertex to add a triangle',
      };
    }
    if (_tool == ActiveTool.move) {
      return _lockedAxis == null
          ? '${_viewName(_viewPreset)} view · choose X, Y, or Z, then drag'
          : '${_viewName(_viewPreset)} view · Move along '
              '${_lockedAxis!.name.toUpperCase()} · drag';
    }
    if (_mode == EditMode.vertex) {
      return '${_viewName(_viewPreset)} view · '
          '${_selectedVertices.length} vertices selected';
    }
    return _selectedFaces.length > 1
        ? '${_viewName(_viewPreset)} view · '
            '${_selectedFaces.length} faces selected'
        : _selectedFace == null
            ? '${_viewName(_viewPreset)} view · No face selected'
            : '${_viewName(_viewPreset)} view · Face ${_selectedFace! + 1} selected';
  }

  BoxDecoration _panelDecoration() => BoxDecoration(
        color: const Color(0xFF171B23),
        border: Border.all(color: const Color(0xFF282E39)),
        borderRadius: BorderRadius.circular(14),
      );
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
    required this.meshes,
    required this.textures,
    required this.activeMeshIndex,
    required this.selectedVertices,
    required this.selectedFaces,
    required this.selectedFace,
    required this.project,
    required this.basis,
    required this.viewPreset,
    required this.referenceImage,
    required this.referenceOpacity,
    required this.viewStyle,
    required this.fade,
    required this.showVertices,
  });

  final List<MeshModel> meshes;
  final List<ui.Image?> textures;
  final int activeMeshIndex;
  final Set<int> selectedVertices;
  final Set<int> selectedFaces;
  final int? selectedFace;
  final Offset Function(Vec3 point) project;
  final _ViewBasis basis;
  final ViewPreset viewPreset;
  final ui.Image? referenceImage;
  final double referenceOpacity;
  final ViewStyle viewStyle;
  final double fade;
  final bool showVertices;

  double _dot(Vec3 first, Vec3 second) =>
      first.x * second.x + first.y * second.y + first.z * second.z;

  @override
  void paint(Canvas canvas, Size size) {
    final image = referenceImage;
    if (image != null) {
      final source = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final destination = Offset.zero & size;
      final fitted = applyBoxFit(
        BoxFit.contain,
        Size(source.width, source.height),
        size,
      );
      canvas.drawImageRect(
        image,
        Alignment.center.inscribe(fitted.source, source),
        Alignment.center.inscribe(fitted.destination, destination),
        Paint()
          ..color = Colors.white.withValues(alpha: referenceOpacity)
          ..filterQuality = FilterQuality.medium,
      );
    }

    final gridPaint = Paint()
      ..color = const Color(0xFF29303A)
      ..strokeWidth = 1;
    final gridRight =
        viewPreset == ViewPreset.free ? const Vec3(1, 0, 0) : basis.right;
    final gridUp =
        viewPreset == ViewPreset.free ? const Vec3(0, 1, 0) : basis.up;
    final gridNormal =
        viewPreset == ViewPreset.free ? const Vec3(0, 0, 1) : basis.normal;
    final gridOrigin = Vec3(
      gridNormal.x * -0.02,
      gridNormal.y * -0.02,
      gridNormal.z * -0.02,
    );
    for (var i = -20; i <= 20; i++) {
      final offset = i.toDouble();
      final horizontalColor =
          i == 0 ? const Color(0xFF63C48D) : const Color(0xFF29303A);
      final verticalColor =
          i == 0 ? const Color(0xFFE16C6C) : const Color(0xFF29303A);
      canvas.drawLine(
        project(Vec3(
          gridRight.x * offset + gridUp.x * -20 + gridOrigin.x,
          gridRight.y * offset + gridUp.y * -20 + gridOrigin.y,
          gridRight.z * offset + gridUp.z * -20 + gridOrigin.z,
        )),
        project(Vec3(
          gridRight.x * offset + gridUp.x * 20 + gridOrigin.x,
          gridRight.y * offset + gridUp.y * 20 + gridOrigin.y,
          gridRight.z * offset + gridUp.z * 20 + gridOrigin.z,
        )),
        gridPaint..color = horizontalColor,
      );
      canvas.drawLine(
        project(Vec3(
          gridRight.x * -20 + gridUp.x * offset + gridOrigin.x,
          gridRight.y * -20 + gridUp.y * offset + gridOrigin.y,
          gridRight.z * -20 + gridUp.z * offset + gridOrigin.z,
        )),
        project(Vec3(
          gridRight.x * 20 + gridUp.x * offset + gridOrigin.x,
          gridRight.y * 20 + gridUp.y * offset + gridOrigin.y,
          gridRight.z * 20 + gridUp.z * offset + gridOrigin.z,
        )),
        gridPaint..color = verticalColor,
      );
    }

    final edgePaint = Paint()
      ..color = const Color(0xFFB8C5D8).withValues(alpha: fade)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    final faceDraws = <(double, int, int, MeshFace)>[];
    for (var meshIndex = 0; meshIndex < meshes.length; meshIndex++) {
      final mesh = meshes[meshIndex];
      for (var faceIndex = 0; faceIndex < mesh.faces.length; faceIndex++) {
        final face = mesh.faces[faceIndex];
        final depth = face.vertices
                .map((index) =>
                    _dot(mesh.vertices[index].position, basis.normal))
                .reduce((first, second) => first + second) /
            face.vertices.length;
        faceDraws.add((depth, meshIndex, faceIndex, face));
      }
    }
    faceDraws.sort((first, second) => first.$1.compareTo(second.$1));
    for (final (_, meshIndex, faceIndex, face) in faceDraws) {
      final mesh = meshes[meshIndex];
      final active = meshIndex == activeMeshIndex;
      final selected = active &&
          (selectedFaces.contains(faceIndex) ||
              (selectedFaces.isEmpty && faceIndex == selectedFace));
      final points = face.vertices
          .map((index) => project(mesh.vertices[index].position))
          .toList();
      final path = Path()..addPolygon(points, true);
      if (viewStyle == ViewStyle.solid) {
        canvas.drawPath(
          path,
          Paint()
            ..color =
                (selected ? const Color(0xFF8B9BB5) : const Color(0xFF707985))
                    .withValues(alpha: fade),
        );
      } else if (viewStyle == ViewStyle.textured) {
        final texture = textures[meshIndex];
        if (texture != null && face.uv.length == points.length) {
          _drawTexturedFace(canvas, face, points, texture, fade);
        } else {
          canvas.drawPath(
            path,
            Paint()..color = const Color(0xFF707985).withValues(alpha: fade),
          );
        }
        if (selected) {
          canvas.drawPath(
            path,
            Paint()..color = const Color(0x334E8DFF).withValues(alpha: fade),
          );
        }
      }
      if (viewStyle == ViewStyle.wireframe) {
        canvas.drawPath(path, edgePaint);
      } else if (active && selected) {
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFE4B85C).withValues(alpha: fade)
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      }
    }

    if (showVertices) {
      for (var meshIndex = 0; meshIndex < meshes.length; meshIndex++) {
        final mesh = meshes[meshIndex];
        for (var index = 0; index < mesh.vertices.length; index++) {
          final point = project(mesh.vertices[index].position);
          final isActive = meshIndex == activeMeshIndex;
          final isSelected = isActive && selectedVertices.contains(index);
          final radius = isSelected ? 7.0 : 4.5;
          canvas.drawCircle(
            point,
            radius,
            Paint()
              ..color = (isSelected
                      ? const Color(0xFFFFC45C)
                      : const Color(0xFFE3E9F0))
                  .withValues(alpha: fade),
          );
        }
      }
    }

    if (meshes[activeMeshIndex].vertices.isEmpty) {
      _drawText(
        canvas,
        'Add vertices or reset the active mesh to start',
        size.center(Offset.zero),
        Colors.white54,
        centered: true,
      );
    }
    _drawAxis(canvas);
  }

  void _drawTexturedFace(
    Canvas canvas,
    MeshFace face,
    List<Offset> destinationPoints,
    ui.Image image,
    double opacity,
  ) {
    final triangles = [
      for (var corner = 1; corner < face.vertices.length - 1; corner++)
        [0, corner, corner + 1],
    ];
    for (final triangle in triangles) {
      final source = triangle
          .map(
            (index) => Offset(
              face.uv[index].dx * image.width,
              (1 - face.uv[index].dy) * image.height,
            ),
          )
          .toList();
      final destination =
          triangle.map((index) => destinationPoints[index]).toList();
      final transform = _affineTransform(source, destination);
      if (transform == null) continue;
      final clip = Path()..addPolygon(destination, true);
      canvas
        ..save()
        ..clipPath(clip)
        ..transform(transform);
      canvas.drawImage(
        image,
        Offset.zero,
        Paint()
          ..color = Colors.white.withValues(alpha: opacity)
          ..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    }
  }

  Float64List? _affineTransform(List<Offset> source, List<Offset> destination) {
    final x1 = source[0].dx;
    final y1 = source[0].dy;
    final x2 = source[1].dx;
    final y2 = source[1].dy;
    final x3 = source[2].dx;
    final y3 = source[2].dy;
    final determinant = x1 * (y2 - y3) + x2 * (y3 - y1) + x3 * (y1 - y2);
    if (determinant.abs() < 1e-10) return null;
    final u1 = destination[0].dx;
    final u2 = destination[1].dx;
    final u3 = destination[2].dx;
    final v1 = destination[0].dy;
    final v2 = destination[1].dy;
    final v3 = destination[2].dy;
    final a = (u1 * (y2 - y3) + u2 * (y3 - y1) + u3 * (y1 - y2)) / determinant;
    final c = (u1 * (x3 - x2) + u2 * (x1 - x3) + u3 * (x2 - x1)) / determinant;
    final tx = (u1 * (x2 * y3 - x3 * y2) +
            u2 * (x3 * y1 - x1 * y3) +
            u3 * (x1 * y2 - x2 * y1)) /
        determinant;
    final b = (v1 * (y2 - y3) + v2 * (y3 - y1) + v3 * (y1 - y2)) / determinant;
    final d = (v1 * (x3 - x2) + v2 * (x1 - x3) + v3 * (x2 - x1)) / determinant;
    final ty = (v1 * (x2 * y3 - x3 * y2) +
            v2 * (x3 * y1 - x1 * y3) +
            v3 * (x1 * y2 - x2 * y1)) /
        determinant;
    return Float64List.fromList([
      a,
      b,
      0,
      0,
      c,
      d,
      0,
      0,
      0,
      0,
      1,
      0,
      tx,
      ty,
      0,
      1,
    ]);
  }

  void _drawAxis(Canvas canvas) {
    const origin = Offset(46, 53);
    final paint = Paint()..strokeWidth = 2;
    final axes = [
      (MeshAxis.x, const Color(0xFFE16C6C)),
      (MeshAxis.y, const Color(0xFF63C48D)),
      (MeshAxis.z, const Color(0xFF6D9EFF)),
    ];
    for (final (axis, color) in axes) {
      final vector = switch (axis) {
        MeshAxis.x => const Vec3(1, 0, 0),
        MeshAxis.y => const Vec3(0, 1, 0),
        MeshAxis.z => const Vec3(0, 0, 1),
      };
      var direction = Offset(
        vector.x * basis.right.x +
            vector.y * basis.right.y +
            vector.z * basis.right.z,
        -(vector.x * basis.up.x +
            vector.y * basis.up.y +
            vector.z * basis.up.z),
      );
      if (direction.distance < 0.05) {
        direction = Offset.zero;
      } else {
        direction = Offset(
          direction.dx / direction.distance,
          direction.dy / direction.distance,
        );
      }
      final end = direction == Offset.zero ? origin : origin + direction * 30;
      canvas.drawLine(origin, end, paint..color = color);
      _drawText(
        canvas,
        axis.name.toUpperCase(),
        end +
            (direction == Offset.zero
                ? const Offset(-4, -16)
                : const Offset(3, -7)),
        color,
      );
    }
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
  const _UvPainter({required this.face, required this.texture});

  final MeshFace? face;
  final ui.Image? texture;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height).toDouble() * 0.72;
    final origin = Offset((size.width - scale) / 2, (size.height - scale) / 2);
    final rect = Rect.fromLTWH(origin.dx, origin.dy, scale, scale);
    final textureImage = texture;
    if (textureImage != null) {
      canvas.drawImageRect(
        textureImage,
        Rect.fromLTWH(
          0,
          0,
          textureImage.width.toDouble(),
          textureImage.height.toDouble(),
        ),
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    canvas.drawRect(
      rect,
      Paint()
        ..color = textureImage == null
            ? const Color(0xFF202733)
            : const Color(0x33202733)
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
        grid..color = const Color(0x88343D4B),
      );
      canvas.drawLine(
        Offset(origin.dx, origin.dy + offset),
        Offset(origin.dx + scale, origin.dy + offset),
        grid..color = const Color(0x88343D4B),
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
    _drawLabel(
        canvas, '0 — 1 UV space', Offset(size.width / 2, rect.bottom + 22));
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
