import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mesh.dart';
import 'model_io.dart';

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

enum ActiveTool { select, addVertex, move }

enum ViewPreset { free, front, back, right, left, top, bottom }

enum MeshAxis { x, y, z }

enum ViewStyle { solid, textured, wireframe }

enum _UnsavedChoice { save, discard, cancel }

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
  const ModelerScreen({super.key});

  @override
  State<ModelerScreen> createState() => _ModelerScreenState();
}

class _ModelerScreenState extends State<ModelerScreen> {
  final List<SceneObject> _objects = [
    SceneObject('Mesh_1', MeshModel.starterPlane()),
  ];
  int _activeObjectIndex = 0;
  MeshModel get _mesh => _objects[_activeObjectIndex].mesh;

  EditMode _mode = EditMode.vertex;
  EditorPage _page = EditorPage.model;
  ActiveTool _tool = ActiveTool.select;
  ViewPreset _viewPreset = ViewPreset.free;
  MeshAxis? _lockedAxis;
  final Set<int> _selectedVertices = {};
  int? _selectedFace = 0;
  final Map<ViewPreset, ui.Image> _referenceImages = {};
  double _yaw = -0.55;
  double _pitch = 0.68;
  double _zoom = 1;
  static const double _minZoom = 0.035;
  static const double _maxZoom = 12;
  double _gestureZoomStart = 1;
  double _referenceOpacity = 0.35;
  Offset _pan = Offset.zero;
  Offset _gestureAnchor = Offset.zero;
  int _draggingUvCorner = -1;
  ViewStyle _viewStyle = ViewStyle.solid;
  String? _currentFilePath;
  bool _isDirty = false;
  bool _isSaving = false;

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
      _selectedFace = _mesh.faces.isEmpty ? null : 0;
      _tool = ActiveTool.select;
      _lockedAxis = null;
    });
  }

  void _setView(ViewPreset preset) {
    setState(() {
      _viewPreset = preset;
      _pan = Offset.zero;
      _zoom = 1;
    });
  }

  _ViewBasis _viewBasis() {
    switch (_viewPreset) {
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
        final cosYaw = math.cos(_yaw);
        final sinYaw = math.sin(_yaw);
        final cosPitch = math.cos(_pitch);
        final sinPitch = math.sin(_pitch);
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

  void _moveSelectedAlongAxis(Offset screenDelta, Size size) {
    final axis = _lockedAxis;
    if (axis == null) return;
    final selected = _verticesToMove;
    if (selected.isEmpty) return;
    final basis = _viewBasis();
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
    final scale = math.min(size.width, size.height).toDouble() * 0.27 * _zoom;
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
    if (key == LogicalKeyboardKey.keyD &&
        HardwareKeyboard.instance.isShiftPressed) {
      _duplicateIfRequested();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyX) {
      _lockAxis(MeshAxis.x);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyY) {
      _lockAxis(MeshAxis.y);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyZ) {
      _lockAxis(MeshAxis.z);
      return KeyEventResult.handled;
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
      _mode = EditMode.face;
      _tool = ActiveTool.select;
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
      _isDirty = true;
    });
  }

  void _handleModelTap(Offset point, Size size) {
    if (_tool == ActiveTool.addVertex && _mode == EditMode.vertex) {
      final index = _mesh.addVertex(_worldPosition(point, size));
      setState(() {
        _selectedVertices.add(index);
        _isDirty = true;
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
    final basis = _viewBasis();
    final horizontal = _dot(point, basis.right);
    final vertical = _dot(point, basis.up);
    final scale = math.min(size.width, size.height).toDouble() * 0.27 * _zoom;
    return Offset(
      size.width / 2 + _pan.dx + horizontal * scale,
      size.height / 2 + _pan.dy - vertical * scale,
    );
  }

  Vec3 _worldPosition(Offset screenPoint, Size size) {
    final scale = math.min(size.width, size.height).toDouble() * 0.27 * _zoom;
    final basis = _viewBasis();
    final horizontal = (screenPoint.dx - size.width / 2 - _pan.dx) / scale;
    final vertical = -(screenPoint.dy - size.height / 2 - _pan.dy) / scale;
    return Vec3(
      basis.right.x * horizontal + basis.up.x * vertical,
      basis.right.y * horizontal + basis.up.y * vertical,
      basis.right.z * horizontal + basis.up.z * vertical,
    );
  }

  double _zoomForWheel(double scrollDelta) =>
      (_zoom * math.exp(-scrollDelta * 0.0015))
          .clamp(_minZoom, _maxZoom)
          .toDouble();

  void _zoomBy(double factor) {
    setState(() {
      _zoom = (_zoom * factor).clamp(_minZoom, _maxZoom).toDouble();
    });
  }

  void _fitScene(Size size) {
    final points = _objects
        .expand((object) => object.mesh.vertices)
        .map((vertex) => vertex.position)
        .toList();
    if (points.isEmpty) return;
    final basis = _viewBasis();
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
      _zoom = (math.min(size.width / spanX, size.height / spanY) * 0.78 / scale)
          .clamp(_minZoom, _maxZoom)
          .toDouble();
      _pan = Offset(
        size.width / 2 - ((minX + maxX) / 2) * scale * _zoom,
        size.height / 2 + ((minY + maxY) / 2) * scale * _zoom,
      );
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
    try {
      final imported = await ModelIo.readPky(file.path);
      final loadedObjects = <SceneObject>[];
      for (final object in imported) {
        var texturePath = object.texturePath;
        if (texturePath != null && !File(texturePath).isAbsolute) {
          texturePath = '${File(file.path).parent.path}\\$texturePath';
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
        _selectedFace = _mesh.faces.isEmpty ? null : 0;
        _tool = ActiveTool.select;
        _lockedAxis = null;
        _currentFilePath = file.path;
        _isDirty = false;
        _page = EditorPage.model;
      });
      _showMessage('Opened ${File(file.path).uri.pathSegments.last}');
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
      _selectedFace = 0;
      _tool = ActiveTool.select;
      _lockedAxis = null;
      _currentFilePath = null;
      _isDirty = false;
      _page = EditorPage.model;
      _zoom = 1;
      _pan = Offset.zero;
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
    for (var faceIndex = _mesh.faces.length - 1; faceIndex >= 0; faceIndex--) {
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
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 18,
          leadingWidth: 48,
          leading: PopupMenuButton<String>(
            tooltip: 'File menu',
            icon: const Icon(Icons.menu_rounded),
            onSelected: (value) {
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
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'new', child: Text('New scene')),
              const PopupMenuItem(value: 'open', child: Text('Open .pky…')),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'save',
                child: Text(_isSaving ? 'Saving…' : 'Save scene'),
              ),
              const PopupMenuItem(
                  value: 'saveAs', child: Text('Save scene as…')),
              const PopupMenuItem(value: 'export', child: Text('Export .obj…')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'exit', child: Text('Exit')),
            ],
          ),
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.view_in_ar_rounded, color: Color(0xFF75A6FF)),
              SizedBox(width: 9),
              Text('Blunder', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Add mesh',
              onPressed: _addMesh,
              icon: const Icon(Icons.add_box_outlined),
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
              if (_selectedVertices.isNotEmpty)
                _ToolButton(
                  label: 'Duplicate',
                  icon: Icons.control_point_duplicate_rounded,
                  onPressed: _duplicateSelection,
                ),
              FilledButton.tonalIcon(
                onPressed:
                    _selectedVertices.length == 4 ? _connectVertices : null,
                icon: const Icon(Icons.polyline_rounded, size: 18),
                label: const Text('Make quad'),
              ),
            ] else ...[
              _ToolButton(
                label: 'Duplicate',
                icon: Icons.control_point_duplicate_rounded,
                onPressed: _selectedFace == null ? null : _duplicateSelection,
              ),
              _ToolButton(
                label: 'Delete face',
                icon: Icons.delete_outline_rounded,
                onPressed: _selectedFace == null ? null : _deleteFace,
              ),
            ],
            const SizedBox(width: 8),
            _ToolButton(
              label: _tool == ActiveTool.move ? 'Moving' : 'Move (M)',
              icon: Icons.open_with_rounded,
              selected: _tool == ActiveTool.move,
              onPressed: _toggleMoveTool,
            ),
            if (_tool == ActiveTool.move)
              for (final axis in MeshAxis.values)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: _axisButton(axis),
                ),
            const SizedBox(width: 10),
            const VerticalDivider(width: 1, indent: 6, endIndent: 6),
            const SizedBox(width: 8),
            for (final view in ViewPreset.values)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _viewButton(view),
              ),
            const SizedBox(width: 6),
            _ToolButton(
              label: 'Reference image',
              icon: Icons.image_outlined,
              onPressed: _loadReferenceImage,
            ),
            const SizedBox(width: 8),
            if (_page == EditorPage.model)
              SegmentedButton<ViewStyle>(
                segments: const [
                  ButtonSegment(
                    value: ViewStyle.solid,
                    tooltip: 'Solid render',
                    icon: Icon(Icons.circle_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: ViewStyle.textured,
                    tooltip: 'Texture preview',
                    icon: Icon(Icons.texture_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: ViewStyle.wireframe,
                    tooltip: 'Wireframe',
                    icon: Icon(Icons.grid_4x4_rounded, size: 16),
                  ),
                ],
                selected: {_viewStyle},
                onSelectionChanged: (selection) =>
                    setState(() => _viewStyle = selection.first),
              )
            else ...[
              _ToolButton(
                label: _meshTextureLabel(),
                icon: Icons.texture_rounded,
                onPressed: _loadTexture,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _meshTextureLabel() {
    final texture = _objects[_activeObjectIndex].texturePath;
    return texture == null
        ? 'Choose texture'
        : File(texture).uri.pathSegments.last;
  }

  Widget _axisButton(MeshAxis axis) {
    final color = switch (axis) {
      MeshAxis.x => const Color(0xFFE16C6C),
      MeshAxis.y => const Color(0xFF63C48D),
      MeshAxis.z => const Color(0xFF6D9EFF),
    };
    return OutlinedButton(
      onPressed: () => _lockAxis(axis),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor:
            _lockedAxis == axis ? color.withValues(alpha: 0.18) : null,
        minimumSize: const Size(42, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: Text(axis.name.toUpperCase()),
    );
  }

  Widget _viewButton(ViewPreset view) {
    return OutlinedButton(
      onPressed: () => _setView(view),
      style: OutlinedButton.styleFrom(
        foregroundColor:
            _viewPreset == view ? const Color(0xFF9FBEFF) : Colors.white70,
        backgroundColor: _viewPreset == view ? const Color(0xFF283955) : null,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: Text(_viewName(view)),
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
      _page == EditorPage.model ? _buildViewport() : _buildUvEditor();

  Widget _buildWideWorkspace() {
    return Row(
      children: [
        SizedBox(width: 220, child: _buildSidePanel()),
        const SizedBox(width: 12),
        Expanded(
          child:
              _page == EditorPage.model ? _buildViewport() : _buildUvEditor(),
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

  Widget _buildViewport() {
    return Container(
      decoration: _panelDecoration(),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                setState(() => _zoom = _zoomForWheel(event.scrollDelta.dy));
              }
            },
            child: GestureDetector(
              key: const ValueKey('modelViewport'),
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) =>
                  _handleModelTap(details.localPosition, size),
              onScaleStart: (details) {
                _gestureAnchor = details.focalPoint;
                _gestureZoomStart = _zoom;
              },
              onScaleUpdate: (details) {
                if (details.pointerCount >= 2) {
                  setState(() {
                    _pan += details.focalPoint - _gestureAnchor;
                    _zoom = (_gestureZoomStart * details.scale)
                        .clamp(_minZoom, _maxZoom)
                        .toDouble();
                    _gestureAnchor = details.focalPoint;
                  });
                } else if (_tool == ActiveTool.move && _lockedAxis != null) {
                  _moveSelectedAlongAxis(details.focalPointDelta, size);
                } else if (_tool != ActiveTool.addVertex &&
                    _tool != ActiveTool.move) {
                  setState(() {
                    _viewPreset = ViewPreset.free;
                    _yaw += details.focalPointDelta.dx * 0.008;
                    _pitch = (_pitch + details.focalPointDelta.dy * 0.008)
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
                      selectedFace: _selectedFace,
                      project: (point) => _project(point, size),
                      basis: _viewBasis(),
                      referenceImage: _referenceImages[_viewPreset],
                      referenceOpacity: _referenceOpacity,
                      viewStyle: _viewStyle,
                      fade: ((_zoom - _minZoom) / 0.18).clamp(0.0, 1.0),
                      showVertices: _mode == EditMode.vertex ||
                          _viewStyle == ViewStyle.wireframe,
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: _zoomControls(size),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _zoomControls(Size size) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE6171B23),
        border: Border.all(color: const Color(0xFF394252)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Zoom in',
            visualDensity: VisualDensity.compact,
            onPressed: () => _zoomBy(1.25),
            icon: const Icon(Icons.add),
          ),
          Text(
            '${(_zoom * 100).round()}%',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          IconButton(
            tooltip: 'Zoom out',
            visualDensity: VisualDensity.compact,
            onPressed: () => _zoomBy(0.8),
            icon: const Icon(Icons.remove),
          ),
          IconButton(
            tooltip: 'Frame all meshes',
            visualDensity: VisualDensity.compact,
            onPressed: () => _fitScene(size),
            icon: const Icon(Icons.fit_screen_rounded),
          ),
        ],
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
    if (_tool == ActiveTool.move) {
      return _lockedAxis == null
          ? '${_viewName(_viewPreset)} view · choose X, Y, or Z, then drag'
          : '${_viewName(_viewPreset)} view · Move along '
              '${_lockedAxis!.name.toUpperCase()} · drag';
    }
    if (_mode == EditMode.vertex) {
      return '${_viewName(_viewPreset)} view · '
          '${_selectedVertices.length}/4 vertices selected';
    }
    return _selectedFace == null
        ? '${_viewName(_viewPreset)} view · No face selected'
        : '${_viewName(_viewPreset)} view · Face ${_selectedFace! + 1} selected';
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
    required this.meshes,
    required this.textures,
    required this.activeMeshIndex,
    required this.selectedVertices,
    required this.selectedFace,
    required this.project,
    required this.basis,
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
  final int? selectedFace;
  final Offset Function(Vec3 point) project;
  final _ViewBasis basis;
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
    final normalOffset = Vec3(
      basis.normal.x * -0.02,
      basis.normal.y * -0.02,
      basis.normal.z * -0.02,
    );
    for (var i = -6; i <= 6; i++) {
      canvas.drawLine(
        project(Vec3(
          basis.right.x * i / 3 + basis.up.x * -2 + normalOffset.x,
          basis.right.y * i / 3 + basis.up.y * -2 + normalOffset.y,
          basis.right.z * i / 3 + basis.up.z * -2 + normalOffset.z,
        )),
        project(Vec3(
          basis.right.x * i / 3 + basis.up.x * 2 + normalOffset.x,
          basis.right.y * i / 3 + basis.up.y * 2 + normalOffset.y,
          basis.right.z * i / 3 + basis.up.z * 2 + normalOffset.z,
        )),
        gridPaint,
      );
      canvas.drawLine(
        project(Vec3(
          basis.right.x * -2 + basis.up.x * i / 3 + normalOffset.x,
          basis.right.y * -2 + basis.up.y * i / 3 + normalOffset.y,
          basis.right.z * -2 + basis.up.z * i / 3 + normalOffset.z,
        )),
        project(Vec3(
          basis.right.x * 2 + basis.up.x * i / 3 + normalOffset.x,
          basis.right.y * 2 + basis.up.y * i / 3 + normalOffset.y,
          basis.right.z * 2 + basis.up.z * i / 3 + normalOffset.z,
        )),
        gridPaint,
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
      final selected = active && faceIndex == selectedFace;
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
      const [0, 1, 2],
      const [0, 2, 3],
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
