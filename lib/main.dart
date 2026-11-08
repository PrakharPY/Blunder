import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'atlas_generator.dart';
import 'mesh.dart';
import 'model_io.dart';
import 'rv_io.dart';

const String _appVersion = '1.1';

void main(List<String> args) {
  String? initialPkyPath;
  for (final argument in args) {
    final extension = argument.toLowerCase();
    if (extension.endsWith('.pky') || extension.endsWith('.pkg')) {
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
      title: 'Blunder v$_appVersion',
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

enum ActiveTool { select, addVertex, addSurface, strip, move, hand }

enum ViewPreset { free, front, back, right, left, top, bottom }

enum MeshAxis { x, y, z }

enum ViewStyle { solid, textured, wireframe }

enum _UnsavedChoice { save, discard, cancel }

enum _UvEditTool {
  idle,
  boxSelect,
  move,
  awaitStretchAxis,
  stretch,
  awaitMirrorAxis,
  mirrorPending,
  rotate,
}

class _SceneObjectSnapshot {
  const _SceneObjectSnapshot({
    required this.name,
    required this.mesh,
    required this.texturePath,
    required this.textureImage,
    required this.groupName,
    required this.visible,
    required this.rvCoordinateScale,
    required this.rvCoordinateOrigin,
    required this.rvTextureAnimations,
    required this.rvTextures,
    required this.rvTexturePaths,
  });

  final String name;
  final MeshModel mesh;
  final String? texturePath;
  final ui.Image? textureImage;
  final String? groupName;
  final bool visible;
  final double? rvCoordinateScale;
  final Vec3? rvCoordinateOrigin;
  final List<Uint8List> rvTextureAnimations;
  final Map<int, ui.Image> rvTextures;
  final Map<int, String> rvTexturePaths;
}

class _ViewportSnapshot {
  const _ViewportSnapshot({
    required this.preset,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.pan,
    required this.referencePan,
  });

  final ViewPreset preset;
  final double yaw;
  final double pitch;
  final double zoom;
  final Offset pan;
  final Offset referencePan;
}

class _EditorSnapshot {
  const _EditorSnapshot({
    required this.objects,
    required this.viewports,
    required this.visibleViewportCount,
    required this.activeViewportIndex,
    required this.activeObjectIndex,
    required this.selectedMeshIndices,
    required this.mode,
    required this.page,
    required this.tool,
    required this.selectedVertices,
    required this.selectedFaces,
    required this.selectedFace,
    required this.referenceImages,
    required this.viewStyle,
    required this.isDirty,
  });

  final List<_SceneObjectSnapshot> objects;
  final List<_ViewportSnapshot> viewports;
  final int visibleViewportCount;
  final int activeViewportIndex;
  final int activeObjectIndex;
  final Set<int> selectedMeshIndices;
  final EditMode mode;
  final EditorPage page;
  final ActiveTool tool;
  final Set<int> selectedVertices;
  final Set<int> selectedFaces;
  final int? selectedFace;
  final Map<int, ui.Image> referenceImages;
  final ViewStyle viewStyle;
  final bool isDirty;
}

class ViewportState {
  ViewportState(this.preset);

  ViewPreset preset;
  double yaw = -0.55;
  double pitch = 0.68;
  double zoom = 1;
  Offset pan = Offset.zero;
  Offset referencePan = Offset.zero;
}

class SceneObject {
  SceneObject(
    this.name,
    this.mesh, {
    this.texturePath,
    this.textureImage,
    this.groupName,
    this.visible = true,
    this.rvCoordinateScale,
    this.rvCoordinateOrigin,
    this.rvTextureAnimations = const [],
    this.rvTextures = const {},
    this.rvTexturePaths = const {},
  });

  String name;
  final MeshModel mesh;
  String? texturePath;
  ui.Image? textureImage;
  String? groupName;
  bool visible;
  double? rvCoordinateScale;
  Vec3? rvCoordinateOrigin;
  List<Uint8List> rvTextureAnimations;
  Map<int, ui.Image> rvTextures;
  Map<int, String> rvTexturePaths;
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
  bool _isAtlasPanelVisible = true;
  bool _isRvPanelVisible = true;
  bool _isGeneratingAtlas = false;
  bool _atlasAutoFit = true;
  int _atlasMaxSize = 2048;
  int _atlasPadding = 8;
  double _atlasDensity = 1;
  AtlasShape _atlasShape = AtlasShape.square;
  int _activeObjectIndex = 0;
  final Set<int> _selectedMeshIndices = {0};
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
  final Set<int> _rvHighlightedFaces = {};
  int _rvFlagToSelect = rvFlagInvisible;
  int? _selectedFace = 0;
  final List<int> _stripEdge = [];
  final Map<int, ui.Image> _referenceImages = {};
  final Set<String> _collapsedMeshGroups = {};
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
  _UvEditTool _uvEditTool = _UvEditTool.idle;
  final Set<(int, int)> _selectedUvs = {};
  Map<(int, int), Offset> _uvTransformStart = {};
  Map<(int, int), Offset> _uvGestureStartUvs = {};
  Offset? _uvGestureStart;
  Offset? _uvSelectionStart;
  Offset? _uvSelectionEnd;
  int _uvTransformAxis = 0;
  bool _uvSelectionReadyToMove = false;
  String _uvRotationDegrees = '';
  final TextEditingController _uvRotationController = TextEditingController();
  ViewStyle _viewStyle = ViewStyle.solid;
  String? _currentFilePath;
  bool _isDirty = false;
  bool _isSaving = false;
  MeshAxis? _rotationAxis;
  MeshAxis _selectedAxis = MeshAxis.x;
  String _rotationDegrees = '';
  final List<_EditorSnapshot> _undoHistory = [];
  final List<_EditorSnapshot> _redoHistory = [];
  bool _boxSelectActive = false;
  Offset? _boxSelectionStart;
  Offset? _boxSelectionEnd;
  Offset? _surfaceSelectionStart;
  Offset? _surfaceSelectionEnd;
  bool _scaleActive = false;
  String _scaleFactorText = '';
  List<Vec3> _scaleStartPositions = [];
  Offset? _scaleStartPointer;
  bool _scaleStartDirty = false;
  static const int _historyLimit = 100;
  final ValueNotifier<int> _fpsValue = ValueNotifier<int>(0);
  int _fpsFrameCount = 0;
  int? _fpsWindowStartMicros;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_recordFrameTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Platform.isWindows && kReleaseMode) _registerPkyAssociation();
      final path = widget.initialPkyPath;
      if (path != null) _loadScenePath(path);
    });
  }

  Future<void> _renameMeshGroup(String groupName) async {
    final members =
        _objects.where((object) => object.groupName == groupName).toList();
    if (members.isEmpty) return;
    final controller = TextEditingController(text: groupName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename mesh group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Group name'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    final trimmed = name?.trim();
    if (trimmed == null ||
        trimmed.isEmpty ||
        !mounted ||
        members.any((object) => !_objects.contains(object))) {
      return;
    }
    _recordUndo();
    setState(() {
      for (final object in members) {
        object.groupName = trimmed;
      }
      if (_collapsedMeshGroups.remove(groupName)) {
        _collapsedMeshGroups.add(trimmed);
      }
      _isDirty = true;
    });
  }

  String _uniqueMeshGroupName(String preferred) {
    final names = _objects.map((object) => object.groupName).toSet();
    if (!names.contains(preferred)) return preferred;
    var suffix = 2;
    while (names.contains('${preferred}_$suffix')) {
      suffix++;
    }
    return '${preferred}_$suffix';
  }

  Future<void> _duplicateMeshGroup(String groupName) async {
    final sources =
        _objects.where((object) => object.groupName == groupName).toList();
    if (sources.isEmpty) return;
    final totalFaces = sources.fold<int>(
        0, (total, object) => total + object.mesh.faces.length);
    if (!_canAddFaces(totalFaces)) return;
    final groupCopyName = _uniqueMeshGroupName('${groupName}_copy');
    final copies = <SceneObject>[];
    for (final source in sources) {
      final mesh = MeshModel.fromData(
        source.mesh.vertices.map((vertex) => vertex.position),
        source.mesh.faces.map(MeshFace.copyOf),
        smoothShading: source.mesh.smoothShading,
      );
      mesh.moveVertices(
        List.generate(mesh.vertices.length, (index) => index),
        const Vec3(1.5, 0, 0),
      );
      copies.add(
        SceneObject(
          _uniqueMeshName('${source.name}_copy'),
          mesh,
          texturePath: source.texturePath,
          textureImage: source.textureImage,
          groupName: groupCopyName,
          rvCoordinateScale: source.rvCoordinateScale,
          rvCoordinateOrigin: source.rvCoordinateOrigin,
          rvTextureAnimations: source.rvTextureAnimations,
          rvTextures: Map.of(source.rvTextures),
          rvTexturePaths: Map.of(source.rvTexturePaths),
        ),
      );
    }
    _recordUndo();
    setState(() {
      _objects.addAll(copies);
      _activeObjectIndex = _objects.length - copies.length;
      _selectedMeshIndices
        ..clear()
        ..addAll(List.generate(
            copies.length, (index) => _activeObjectIndex + index));
      _selectedVertices.clear();
      _selectedFaces.clear();
      _selectedFace = _mesh.faces.isEmpty ? null : 0;
      _isDirty = true;
    });
  }

  void _recordFrameTimings(List<FrameTiming> timings) {
    int? measuredFps;
    for (final timing in timings) {
      final timestamp =
          timing.timestampInMicroseconds(ui.FramePhase.rasterFinish);
      final start = _fpsWindowStartMicros;
      if (start == null) {
        _fpsWindowStartMicros = timestamp;
        _fpsFrameCount = 1;
        continue;
      }

      _fpsFrameCount++;
      final elapsed = timestamp - start;
      if (elapsed >= Duration.microsecondsPerSecond) {
        measuredFps =
            (_fpsFrameCount * Duration.microsecondsPerSecond / elapsed).round();
        _fpsWindowStartMicros = timestamp;
        _fpsFrameCount = 0;
      }
    }
    if (measuredFps != null) _fpsValue.value = measuredFps;
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_recordFrameTimings);
    _fpsValue.dispose();
    final images = <ui.Image>{
      ..._referenceImages.values,
      for (final object in _objects)
        if (object.textureImage != null) object.textureImage!,
      for (final object in _objects) ...object.rvTextures.values,
      for (final snapshot in [..._undoHistory, ..._redoHistory]) ...[
        ...snapshot.referenceImages.values,
        for (final object in snapshot.objects)
          if (object.textureImage != null) object.textureImage!,
        for (final object in snapshot.objects) ...object.rvTextures.values,
      ],
    };
    for (final image in images) {
      image.dispose();
    }
    _uvRotationController.dispose();
    super.dispose();
  }

  void _resetPlane() {
    _recordUndo();
    setState(() {
      final object = _objects[_activeObjectIndex];
      _objects[_activeObjectIndex] = SceneObject(
        object.name,
        MeshModel.starterPlane(),
        visible: object.visible,
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
    if (!_canAddFaces(1)) return;
    _recordUndo();
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
      _selectedMeshIndices
        ..clear()
        ..add(_activeObjectIndex);
      _selectedVertices.clear();
      _selectedFaces.clear();
      _selectedFace = 0;
      _tool = ActiveTool.select;
      _lockedAxis = null;
      _isDirty = true;
    });
  }

  bool _canAddFaces(int additionalFaces) {
    final total = _objects.fold<int>(
      0,
      (count, object) => count + object.mesh.faces.length,
    );
    if (total + additionalFaces <= ModelIo.maxFaceCount) return true;
    _showMessage('A scene can contain at most 100,000 faces.');
    return false;
  }

  void _addPrimitive(String shape) {
    final mesh = switch (shape) {
      'Cube' => MeshModel.cube(),
      'Cylinder' => MeshModel.cylinder(),
      'Circle' => MeshModel.circle(),
      _ => MeshModel.rectangle(),
    };
    if (_objects.fold<int>(
                0, (total, object) => total + object.mesh.faces.length) +
            mesh.faces.length >
        ModelIo.maxFaceCount) {
      _showMessage('A scene can contain at most 100,000 faces.');
      return;
    }
    _recordUndo();
    mesh.moveVertices(
      List.generate(mesh.vertices.length, (index) => index),
      Vec3(_objects.length * 3, 0, 0),
    );
    setState(() {
      _objects.add(SceneObject('${shape}_${_objects.length + 1}', mesh));
      _activeObjectIndex = _objects.length - 1;
      _selectedMeshIndices
        ..clear()
        ..add(_activeObjectIndex);
      _selectedVertices.clear();
      _selectedFaces.clear();
      _rvHighlightedFaces.clear();
      _selectedFace = mesh.faces.isEmpty ? null : 0;
      _tool = ActiveTool.select;
      _lockedAxis = null;
      _page = EditorPage.model;
      _isDirty = true;
    });
  }

  void _toggleShading() {
    _recordUndo();
    setState(() {
      _mesh.smoothShading = !_mesh.smoothShading;
      _isDirty = true;
    });
    _showMessage(
      '${_mesh.smoothShading ? 'Smooth' : 'Flat'} shading applied to '
      '${_objects[_activeObjectIndex].name}.',
    );
  }

  Set<int> get _facesForUvMapping {
    if (_mode == EditMode.face && _selectedFaces.isNotEmpty) {
      return _selectedFaces
          .where((index) => index >= 0 && index < _mesh.faces.length)
          .toSet();
    }
    if (_page == EditorPage.uv && _selectedUvs.isNotEmpty) {
      return _selectedUvs.map((uv) => uv.$1).toSet();
    }
    if (_mode == EditMode.face &&
        _selectedFace != null &&
        _selectedFace! < _mesh.faces.length) {
      return {_selectedFace!};
    }
    return {};
  }

  Future<void> _openUvMappingOptions() async {
    final option = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('UV mapping'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'project'),
            child: const ListTile(
              leading: Icon(Icons.view_in_ar_rounded),
              title: Text('Project from view'),
              subtitle: Text('Map selected faces from the active viewport.'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'smart'),
            child: const ListTile(
              leading: Icon(Icons.auto_fix_high),
              title: Text('Smart UV unwrap'),
              subtitle: Text('Pack selected faces into separate UV tiles.'),
            ),
          ),
        ],
      ),
    );
    if (!mounted || option == null) return;
    final selected = _facesForUvMapping;
    final faceIndices = selected.isEmpty
        ? List<int>.generate(_mesh.faces.length, (index) => index)
        : selected.toList();
    if (faceIndices.isEmpty) {
      _showMessage('Add or select faces before mapping UVs.');
      return;
    }
    _recordUndo();
    final changed = option == 'project'
        ? _mesh.projectUvFromView(
            faceIndices,
            _viewBasis(_activeViewport).right,
            _viewBasis(_activeViewport).up,
          )
        : _mesh.smartUvRemap(faceIndices);
    if (!changed) {
      _undoHistory.removeLast();
      _showMessage('Could not create UVs for the selected faces.');
      return;
    }
    setState(() {
      _isDirty = true;
      _page = EditorPage.uv;
    });
    _showMessage(
      option == 'project'
          ? 'Projected ${faceIndices.length} face(s) from the current view.'
          : 'Unwrapped ${faceIndices.length} face(s) into UV tiles.',
    );
  }

  void _selectMesh(int index, {bool toggle = false}) {
    setState(() {
      final changedActive = index != _activeObjectIndex;
      _activeObjectIndex = index;
      if (changedActive) {
        _selectedVertices.clear();
        _selectedFaces.clear();
        _rvHighlightedFaces.clear();
        _selectedFace = _mesh.faces.isEmpty ? null : 0;
      }
      if (toggle) {
        if (!_selectedMeshIndices.add(index)) {
          _selectedMeshIndices.remove(index);
        }
      } else {
        _selectedMeshIndices
          ..clear()
          ..add(index);
        if (!changedActive) {
          _selectedVertices.clear();
          _selectedFaces.clear();
          _rvHighlightedFaces.clear();
          _selectedFace = _mesh.faces.isEmpty ? null : 0;
        }
        _tool = ActiveTool.select;
        _lockedAxis = null;
      }
    });
  }

  void _toggleMeshVisibility(int index) {
    if (index < 0 || index >= _objects.length) return;
    _recordUndo();
    setState(() {
      final object = _objects[index];
      object.visible = !object.visible;
      if (!object.visible) _selectedMeshIndices.remove(index);
      _isDirty = true;
    });
  }

  Future<void> _joinSelectedMeshes() async {
    final indices = _selectedMeshIndices
        .where((index) => index >= 0 && index < _objects.length)
        .where((index) => _objects[index].visible)
        .toList()
      ..sort();
    if (indices.length < 2) {
      _showMessage('Select at least two visible meshes to join.');
      return;
    }
    var name = 'JoinedMesh';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join meshes'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New mesh name'),
          onChanged: (value) => name = value,
          onSubmitted: (_) => Navigator.pop(context, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    final trimmedName = name.trim();
    if (accepted != true || !mounted) return;
    if (trimmedName.isEmpty ||
        _objects.asMap().entries.any(
              (entry) =>
                  !indices.contains(entry.key) &&
                  entry.value.name.toLowerCase() == trimmedName.toLowerCase(),
            )) {
      _showMessage('Enter a unique, non-empty mesh name.');
      return;
    }

    final sources = indices.map((index) => _objects[index]).toList();
    final merged = MeshModel.join(sources.map((object) => object.mesh));
    final firstIndex = indices.first;
    final mergedIndex =
        firstIndex - indices.takeWhile((index) => index < firstIndex).length;
    final texturePath = sources.first.texturePath;
    final sameTexture = sources.every(
      (object) => object.texturePath == texturePath,
    );
    _recordUndo();
    setState(() {
      _objects
        ..removeWhere((object) => sources.contains(object))
        ..insert(
          mergedIndex,
          SceneObject(
            trimmedName,
            merged,
            texturePath: sameTexture ? texturePath : null,
            textureImage: sameTexture ? sources.first.textureImage : null,
            rvCoordinateScale: sources.every(
              (object) =>
                  object.rvCoordinateScale == sources.first.rvCoordinateScale,
            )
                ? sources.first.rvCoordinateScale
                : null,
            rvCoordinateOrigin: sources.every(
              (object) =>
                  object.rvCoordinateOrigin == sources.first.rvCoordinateOrigin,
            )
                ? sources.first.rvCoordinateOrigin
                : null,
            rvTextureAnimations: sources.first.rvTextureAnimations,
            rvTextures: Map.of(sources.first.rvTextures),
            rvTexturePaths: Map.of(sources.first.rvTexturePaths),
          ),
        );
      _activeObjectIndex = mergedIndex;
      _selectedMeshIndices
        ..clear()
        ..add(mergedIndex);
      _selectedVertices.clear();
      _selectedFaces.clear();
      _rvHighlightedFaces.clear();
      _selectedFace = merged.faces.isEmpty ? null : 0;
      _mode = EditMode.vertex;
      _isDirty = true;
    });
    if (!sameTexture) {
      _showMessage(
          'Joined meshes. Different source textures were not retained.');
    }
  }

  void _setView(ViewPreset preset) {
    setState(() {
      _viewPreset = preset;
      _activeViewport.pan = Offset.zero;
      _activeViewport.zoom = 1;
    });
  }

  void _setViewportCount(int count) {
    if (count != _visibleViewportCount) _recordUndo();
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

  MeshModel _copyMesh(MeshModel mesh) => MeshModel.fromData(
        mesh.vertices.map((vertex) => vertex.position),
        mesh.faces.map(MeshFace.copyOf),
        smoothShading: mesh.smoothShading,
      );

  _EditorSnapshot _captureSnapshot() => _EditorSnapshot(
        objects: [
          for (final object in _objects)
            _SceneObjectSnapshot(
              name: object.name,
              mesh: _copyMesh(object.mesh),
              texturePath: object.texturePath,
              textureImage: object.textureImage,
              groupName: object.groupName,
              visible: object.visible,
              rvCoordinateScale: object.rvCoordinateScale,
              rvCoordinateOrigin: object.rvCoordinateOrigin,
              rvTextureAnimations: [
                for (final animation in object.rvTextureAnimations)
                  Uint8List.fromList(animation),
              ],
              rvTextures: Map.of(object.rvTextures),
              rvTexturePaths: Map.of(object.rvTexturePaths),
            ),
        ],
        viewports: [
          for (final viewport in _viewports)
            _ViewportSnapshot(
              preset: viewport.preset,
              yaw: viewport.yaw,
              pitch: viewport.pitch,
              zoom: viewport.zoom,
              pan: viewport.pan,
              referencePan: viewport.referencePan,
            ),
        ],
        visibleViewportCount: _visibleViewportCount,
        activeViewportIndex: _activeViewportIndex,
        activeObjectIndex: _activeObjectIndex,
        selectedMeshIndices: Set.of(_selectedMeshIndices),
        mode: _mode,
        page: _page,
        tool: _tool,
        selectedVertices: Set.of(_selectedVertices),
        selectedFaces: Set.of(_selectedFaces),
        selectedFace: _selectedFace,
        referenceImages: Map.of(_referenceImages),
        viewStyle: _viewStyle,
        isDirty: _isDirty,
      );

  void _recordUndo() {
    _undoHistory.add(_captureSnapshot());
    if (_undoHistory.length > _historyLimit) _undoHistory.removeAt(0);
    _redoHistory.clear();
  }

  void _restoreSnapshot(_EditorSnapshot snapshot) {
    setState(() {
      _objects
        ..clear()
        ..addAll([
          for (final object in snapshot.objects)
            SceneObject(
              object.name,
              _copyMesh(object.mesh),
              texturePath: object.texturePath,
              textureImage: object.textureImage,
              groupName: object.groupName,
              visible: object.visible,
              rvCoordinateScale: object.rvCoordinateScale,
              rvCoordinateOrigin: object.rvCoordinateOrigin,
              rvTextureAnimations: [
                for (final animation in object.rvTextureAnimations)
                  Uint8List.fromList(animation),
              ],
              rvTextures: Map.of(object.rvTextures),
              rvTexturePaths: Map.of(object.rvTexturePaths),
            ),
        ]);
      for (var index = 0; index < _viewports.length; index++) {
        final state = snapshot.viewports[index];
        final viewport = _viewports[index];
        viewport
          ..preset = state.preset
          ..yaw = state.yaw
          ..pitch = state.pitch
          ..zoom = state.zoom
          ..pan = state.pan
          ..referencePan = state.referencePan;
      }
      _visibleViewportCount = snapshot.visibleViewportCount;
      _activeViewportIndex = snapshot.activeViewportIndex;
      _activeObjectIndex = snapshot.activeObjectIndex;
      _selectedMeshIndices
        ..clear()
        ..addAll(snapshot.selectedMeshIndices);
      _mode = snapshot.mode;
      _page = snapshot.page;
      _tool = snapshot.tool;
      _selectedVertices
        ..clear()
        ..addAll(snapshot.selectedVertices);
      _selectedFaces
        ..clear()
        ..addAll(snapshot.selectedFaces);
      _rvHighlightedFaces.clear();
      _selectedFace = snapshot.selectedFace;
      _referenceImages
        ..clear()
        ..addAll(snapshot.referenceImages);
      _viewStyle = snapshot.viewStyle;
      _isDirty = snapshot.isDirty;
      _lockedAxis = null;
      _boxSelectActive = false;
      _scaleActive = false;
    });
  }

  void _undo() {
    if (_undoHistory.isEmpty) return;
    _redoHistory.add(_captureSnapshot());
    _restoreSnapshot(_undoHistory.removeLast());
  }

  void _redo() {
    if (_redoHistory.isEmpty) return;
    _undoHistory.add(_captureSnapshot());
    _restoreSnapshot(_redoHistory.removeLast());
  }

  void _closeViewport(int index) {
    if (_visibleViewportCount <= 1 ||
        index < 0 ||
        index >= _visibleViewportCount) {
      return;
    }
    _recordUndo();
    setState(() {
      _referenceImages.remove(index);
      for (var source = index + 1; source < _visibleViewportCount; source++) {
        final previous = _viewports[source - 1];
        final next = _viewports[source];
        previous
          ..preset = next.preset
          ..yaw = next.yaw
          ..pitch = next.pitch
          ..zoom = next.zoom
          ..pan = next.pan
          ..referencePan = next.referencePan;
        final image = _referenceImages.remove(source);
        if (image != null) _referenceImages[source - 1] = image;
      }
      _visibleViewportCount--;
      if (_activeViewportIndex == index) {
        _activeViewportIndex = math.min(index, _visibleViewportCount - 1);
      } else if (_activeViewportIndex > index) {
        _activeViewportIndex--;
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
      _lockedAxis = _tool == ActiveTool.move ? _selectedAxis : null;
    });
  }

  void _selectAxis(MeshAxis axis) {
    setState(() {
      _selectedAxis = axis;
      if (_tool == ActiveTool.move) _lockedAxis = axis;
      if (_rotationAxis != null) _rotationAxis = axis;
    });
  }

  void _startMovingOnSelectedAxis() {
    setState(() {
      _tool = ActiveTool.move;
      _lockedAxis = _selectedAxis;
    });
  }

  void _duplicateSelection() {
    if (_mode == EditMode.vertex && _selectedVertices.isNotEmpty) {
      _recordUndo();
      final duplicated = _mesh.duplicateVertices(_selectedVertices);
      if (duplicated.isEmpty) {
        _undoHistory.removeLast();
        return;
      }
      setState(() {
        _selectedVertices
          ..clear()
          ..addAll(duplicated);
        _tool = ActiveTool.move;
        _lockedAxis = _selectedAxis;
        _isDirty = true;
      });
      return;
    }
    final facesToDuplicate = _selectedFaces.isNotEmpty
        ? (_selectedFaces.toList()..sort())
        : (_selectedFace == null ? <int>[] : [_selectedFace!]);
    if (_mode == EditMode.face && facesToDuplicate.isNotEmpty) {
      if (!_canAddFaces(facesToDuplicate.length)) return;
      _recordUndo();
      final duplicatedFaces =
          facesToDuplicate.map(_mesh.duplicateFace).whereType<int>().toList();
      if (duplicatedFaces.isEmpty) {
        _undoHistory.removeLast();
        return;
      }
      setState(() {
        _selectedFace = duplicatedFaces.last;
        _selectedFaces
          ..clear()
          ..addAll(duplicatedFaces);
        _tool = ActiveTool.move;
        _lockedAxis = _selectedAxis;
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
      if (_selectedFaces.isNotEmpty) {
        return _selectedFaces
            .where((index) => index >= 0 && index < _mesh.faces.length)
            .expand((index) => _mesh.faces[index].vertices)
            .toSet();
      }
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

  KeyEventResult _handleUvKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _deleteSelection();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA) {
      _toggleSelectAll();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyB) {
      setState(() {
        _selectedUvs.clear();
        _uvEditTool = _UvEditTool.boxSelect;
        _uvSelectionReadyToMove = false;
        _uvSelectionStart = null;
        _uvSelectionEnd = null;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_uvEditTool != _UvEditTool.idle || _uvSelectionStart != null) {
        _cancelUvEdit();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_uvEditTool == _UvEditTool.rotate) {
        final degrees = double.tryParse(_uvRotationDegrees);
        if (degrees != null && degrees.isFinite) {
          _applyUvRotation(degrees);
        }
        _confirmUvRotation();
        return KeyEventResult.handled;
      }
      if (_uvEditTool != _UvEditTool.idle &&
          _uvEditTool != _UvEditTool.boxSelect &&
          _uvEditTool != _UvEditTool.awaitStretchAxis &&
          _uvEditTool != _UvEditTool.awaitMirrorAxis) {
        setState(() {
          _uvEditTool = _UvEditTool.idle;
          _uvTransformStart = {};
          _uvGestureStartUvs = {};
          _uvGestureStart = null;
          _uvSelectionReadyToMove = false;
        });
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.keyR &&
        _uvEditTool == _UvEditTool.idle &&
        _selectedUvs.isNotEmpty) {
      _startUvRotation();
      return KeyEventResult.handled;
    }
    if (_uvEditTool == _UvEditTool.rotate) {
      if (key == LogicalKeyboardKey.backspace) {
        setState(() {
          _uvRotationDegrees = _uvRotationDegrees.isEmpty
              ? ''
              : _uvRotationDegrees.substring(0, _uvRotationDegrees.length - 1);
          _uvRotationController.text = _uvRotationDegrees;
          final degrees = double.tryParse(_uvRotationDegrees);
          if (degrees != null) _applyUvRotation(degrees);
        });
        return KeyEventResult.handled;
      }
      final character = event.character;
      if (character != null &&
          RegExp(r'^[0-9.\-]$').hasMatch(character) &&
          !(_uvRotationDegrees.contains('.') && character == '.')) {
        setState(() {
          _uvRotationDegrees += character;
          _uvRotationController.text = _uvRotationDegrees;
          final degrees = double.tryParse(_uvRotationDegrees);
          if (degrees != null) _applyUvRotation(degrees);
        });
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS &&
        !HardwareKeyboard.instance.isControlPressed) {
      if (_uvEditTool == _UvEditTool.boxSelect) {
        setState(() => _uvEditTool = _UvEditTool.idle);
      } else if (_uvSelectionReadyToMove &&
          _selectedUvs.isNotEmpty &&
          _uvEditTool == _UvEditTool.idle) {
        setState(() {
          _uvEditTool = _UvEditTool.move;
          _uvSelectionReadyToMove = false;
          _captureUvTransformStart();
        });
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyE &&
        _uvEditTool == _UvEditTool.idle &&
        _selectedUvs.isNotEmpty) {
      setState(() => _uvEditTool = _UvEditTool.awaitStretchAxis);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM &&
        _uvEditTool == _UvEditTool.idle &&
        _selectedUvs.isNotEmpty) {
      setState(() => _uvEditTool = _UvEditTool.awaitMirrorAxis);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyX || key == LogicalKeyboardKey.keyY) {
      final axis = key == LogicalKeyboardKey.keyX ? 0 : 1;
      if (_uvEditTool == _UvEditTool.awaitStretchAxis) {
        setState(() {
          _uvTransformAxis = axis;
          _uvEditTool = _UvEditTool.stretch;
          _captureUvTransformStart();
        });
        return KeyEventResult.handled;
      }
      if (_uvEditTool == _UvEditTool.awaitMirrorAxis) {
        _recordUndo();
        setState(() {
          _uvTransformAxis = axis;
          _captureUvTransformStart();
          _mirrorUvSelection(axis);
          _uvEditTool = _UvEditTool.mirrorPending;
        });
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.handled;
  }

  void _captureUvTransformStart() {
    _uvTransformStart = {
      for (final (faceIndex, cornerIndex) in _selectedUvs)
        (faceIndex, cornerIndex): _mesh.faces[faceIndex].uv[cornerIndex],
    };
    _uvGestureStartUvs = Map.of(_uvTransformStart);
  }

  void _captureUvGestureStart() {
    _uvGestureStartUvs = {
      for (final (faceIndex, cornerIndex) in _selectedUvs)
        (faceIndex, cornerIndex): _mesh.faces[faceIndex].uv[cornerIndex],
    };
  }

  void _confirmUvRotation() {
    setState(() {
      _uvEditTool = _UvEditTool.idle;
      _uvTransformStart = {};
      _uvGestureStartUvs = {};
      _uvGestureStart = null;
      _uvRotationDegrees = '';
      _uvRotationController.clear();
    });
  }

  void _setUvRotationText(String value) {
    setState(() {
      _uvRotationDegrees = value;
      _uvRotationController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
      final degrees = double.tryParse(value);
      if (degrees != null && degrees.isFinite) _applyUvRotation(degrees);
    });
  }

  void _startUvRotation() {
    if (_selectedUvs.isEmpty) return;
    _recordUndo();
    setState(() {
      _uvEditTool = _UvEditTool.rotate;
      _uvRotationDegrees = '';
      _uvRotationController.clear();
      _captureUvTransformStart();
    });
  }

  void _applyUvRotation(double degrees) {
    if (_uvTransformStart.isEmpty) return;
    final radians = degrees * math.pi / 180;
    final center = _uvUvPivot;
    final cosine = math.cos(radians);
    final sine = math.sin(radians);
    for (final entry in _uvTransformStart.entries) {
      final uv = entry.value;
      final x = uv.dx - center.dx;
      final y = uv.dy - center.dy;
      _mesh.faces[entry.key.$1].uv[entry.key.$2] = Offset(
        center.dx + x * cosine - y * sine,
        center.dy + x * sine + y * cosine,
      );
    }
    _isDirty = true;
  }

  void _mirrorUvSelection(int axis) {
    if (_uvTransformStart.isEmpty) return;
    final pivot = _uvTransformStart.values
            .map((uv) => axis == 0 ? uv.dx : uv.dy)
            .reduce((first, second) => first + second) /
        _uvTransformStart.length;
    for (final entry in _uvTransformStart.entries) {
      final uv = entry.value;
      _mesh.faces[entry.key.$1].uv[entry.key.$2] = axis == 0
          ? Offset((2 * pivot - uv.dx).clamp(0.0, 1.0), uv.dy)
          : Offset(uv.dx, (2 * pivot - uv.dy).clamp(0.0, 1.0));
    }
    _isDirty = true;
  }

  void _cancelUvEdit() {
    final cancelSelection = _uvEditTool == _UvEditTool.boxSelect;
    for (final entry in _uvTransformStart.entries) {
      if (entry.key.$1 < _mesh.faces.length &&
          entry.key.$2 < _mesh.faces[entry.key.$1].uv.length) {
        _mesh.faces[entry.key.$1].uv[entry.key.$2] = entry.value;
      }
    }
    setState(() {
      if (cancelSelection) _selectedUvs.clear();
      _uvEditTool = _UvEditTool.idle;
      _uvTransformStart = {};
      _uvGestureStartUvs = {};
      _uvGestureStart = null;
      _uvSelectionStart = null;
      _uvSelectionEnd = null;
      _draggingUvCorner = -1;
      _uvSelectionReadyToMove = false;
      _uvRotationDegrees = '';
      _uvRotationController.clear();
    });
  }

  Offset _uvScreenPoint(Offset uv, Size size) =>
      _uvOrigin(size) + Offset(uv.dx, 1 - uv.dy) * _uvScale(size);

  void _startUvGesture(Offset point, Size size) {
    _uvGestureSize = size;
    if (_uvEditTool == _UvEditTool.move ||
        _uvEditTool == _UvEditTool.stretch ||
        _uvEditTool == _UvEditTool.idle) {
      _recordUndo();
    }
    switch (_uvEditTool) {
      case _UvEditTool.boxSelect:
        setState(() {
          _uvSelectionStart = point;
          _uvSelectionEnd = point;
        });
      case _UvEditTool.move:
      case _UvEditTool.stretch:
      case _UvEditTool.rotate:
        _uvGestureStart = point;
        _captureUvGestureStart();
      case _UvEditTool.idle:
        final faceIndex = _selectedFace;
        if (faceIndex == null || faceIndex >= _mesh.faces.length) return;
        final face = _mesh.faces[faceIndex];
        var nearest = -1;
        var distance = 26.0;
        for (var corner = 0; corner < face.uv.length; corner++) {
          final candidate =
              (_uvScreenPoint(face.uv[corner], size) - point).distance;
          if (candidate < distance) {
            nearest = corner;
            distance = candidate;
          }
        }
        _draggingUvCorner = nearest;
        if (nearest >= 0) {
          setState(() {
            _selectedUvs
              ..clear()
              ..add((faceIndex, nearest));
          });
        }
      case _UvEditTool.awaitStretchAxis:
      case _UvEditTool.awaitMirrorAxis:
      case _UvEditTool.mirrorPending:
        break;
    }
  }

  void _updateUvGesture(Offset point, Size size) {
    if (_uvEditTool == _UvEditTool.boxSelect) {
      setState(() => _uvSelectionEnd = point);
      return;
    }
    if (_uvEditTool == _UvEditTool.awaitStretchAxis ||
        _uvEditTool == _UvEditTool.awaitMirrorAxis ||
        _uvEditTool == _UvEditTool.mirrorPending) {
      return;
    }
    final start = _uvGestureStart;
    if (start == null) {
      final faceIndex = _selectedFace;
      final corner = _draggingUvCorner;
      if (faceIndex == null || corner < 0 || faceIndex >= _mesh.faces.length) {
        return;
      }
      final origin = _uvOrigin(size);
      final scale = _uvScale(size);
      final uv = Offset(
        (point.dx - origin.dx) / scale,
        1 - (point.dy - origin.dy) / scale,
      );
      setState(() {
        _mesh.updateUv(faceIndex, corner, uv);
        _isDirty = true;
      });
      return;
    }
    final scale = _uvScale(size);
    final delta = point - start;
    if (_uvEditTool == _UvEditTool.rotate) {
      final degrees = delta.dx;
      setState(() {
        _uvRotationDegrees = degrees.toStringAsFixed(1);
        _uvRotationController.value = TextEditingValue(
          text: _uvRotationDegrees,
          selection: TextSelection.collapsed(offset: _uvRotationDegrees.length),
        );
        _applyUvRotation(degrees);
      });
      return;
    }
    setState(() {
      for (final entry in _uvGestureStartUvs.entries) {
        final faceIndex = entry.key.$1;
        final cornerIndex = entry.key.$2;
        final uv = entry.value;
        if (faceIndex >= _mesh.faces.length ||
            cornerIndex >= _mesh.faces[faceIndex].uv.length) {
          continue;
        }
        if (_uvEditTool == _UvEditTool.move) {
          _mesh.faces[faceIndex].uv[cornerIndex] = Offset(
            (uv.dx + delta.dx / scale).clamp(0.0, 1.0),
            (uv.dy - delta.dy / scale).clamp(0.0, 1.0),
          );
        } else if (_uvEditTool == _UvEditTool.stretch) {
          final amount =
              _uvTransformAxis == 0 ? delta.dx / scale : -delta.dy / scale;
          final factor = math.max(0.01, 1 + amount);
          _mesh.faces[faceIndex].uv[cornerIndex] = _uvTransformAxis == 0
              ? Offset(
                  (_uvUvPivot.dx + (uv.dx - _uvUvPivot.dx) * factor)
                      .clamp(0.0, 1.0),
                  uv.dy,
                )
              : Offset(
                  uv.dx,
                  (_uvUvPivot.dy + (uv.dy - _uvUvPivot.dy) * factor)
                      .clamp(0.0, 1.0),
                );
        }
      }
      _isDirty = true;
    });
  }

  Offset get _uvUvPivot {
    final values = (_uvEditTool == _UvEditTool.rotate
            ? _uvTransformStart.values
            : _uvGestureStartUvs.values)
        .toList();
    if (values.isEmpty) return Offset.zero;
    return Offset(
      values.map((uv) => uv.dx).reduce((a, b) => a + b) / values.length,
      values.map((uv) => uv.dy).reduce((a, b) => a + b) / values.length,
    );
  }

  void _finishUvGesture() {
    if (_uvEditTool == _UvEditTool.boxSelect) {
      final start = _uvSelectionStart;
      final end = _uvSelectionEnd;
      if (start != null && end != null) {
        final selectionRect = Rect.fromPoints(start, end);
        setState(() {
          _selectedUvs.clear();
          for (var faceIndex = 0; faceIndex < _mesh.faces.length; faceIndex++) {
            for (var corner = 0;
                corner < _mesh.faces[faceIndex].uv.length;
                corner++) {
              if (selectionRect.contains(
                _uvScreenPoint(
                    _mesh.faces[faceIndex].uv[corner], _uvGestureSize),
              )) {
                _selectedUvs.add((faceIndex, corner));
              }
            }
          }
          _uvEditTool = _UvEditTool.idle;
          _uvSelectionStart = null;
          _uvSelectionEnd = null;
          _uvSelectionReadyToMove = true;
        });
      }
    }
    _uvGestureStart = null;
    _draggingUvCorner = -1;
  }

  Size _uvGestureSize = Size.zero;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (HardwareKeyboard.instance.isControlPressed &&
        key == LogicalKeyboardKey.keyZ) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _redo();
      } else {
        _undo();
      }
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed &&
        key == LogicalKeyboardKey.keyY) {
      _redo();
      return KeyEventResult.handled;
    }
    if (_scaleActive && _page == EditorPage.model) {
      return _handleScaleKeyEvent(event);
    }
    if (_page == EditorPage.uv && !HardwareKeyboard.instance.isControlPressed) {
      return _handleUvKeyEvent(event);
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _deleteSelection();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA) {
      _toggleSelectAll();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyB) {
      setState(() {
        _boxSelectActive = true;
        _boxSelectionStart = null;
        _boxSelectionEnd = null;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyU) {
      _openUvMappingOptions();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS &&
        !HardwareKeyboard.instance.isControlPressed) {
      _beginScale();
      return KeyEventResult.handled;
    }
    if (_rotationAxis != null) {
      if (key == LogicalKeyboardKey.escape) {
        _rotationAxis = null;
        _rotationDegrees = '';
        setState(() {});
        return KeyEventResult.handled;
      }
      final axis = switch (key) {
        LogicalKeyboardKey.keyX => MeshAxis.x,
        LogicalKeyboardKey.keyY => MeshAxis.y,
        LogicalKeyboardKey.keyZ => MeshAxis.z,
        _ => null,
      };
      if (axis != null) {
        setState(() {
          _rotationAxis = axis;
          _selectedAxis = axis;
          _rotationDegrees = '';
        });
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
      if (key == LogicalKeyboardKey.keyJ) {
        _joinSelectedMeshes();
        return KeyEventResult.handled;
      }
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
        _exportModel();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.keyM) {
      _toggleMoveTool();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR) {
      _rotationAxis = _selectedAxis;
      _rotationDegrees = '';
      _showMessage(
        'Rotate ${_selectedAxis.name.toUpperCase()}: type degrees, then press Enter.',
      );
      setState(() {});
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyD &&
        HardwareKeyboard.instance.isShiftPressed) {
      _duplicateIfRequested();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyX ||
        key == LogicalKeyboardKey.keyY ||
        key == LogicalKeyboardKey.keyZ) {
      _selectAxis(switch (key) {
        LogicalKeyboardKey.keyX => MeshAxis.x,
        LogicalKeyboardKey.keyY => MeshAxis.y,
        _ => MeshAxis.z,
      });
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
        _pitch = _pitch.clamp(-3.13, 3.13).toDouble();
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleScaleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _applyScaleFactor(1);
      if (_undoHistory.isNotEmpty) _undoHistory.removeLast();
      setState(() {
        _scaleActive = false;
        _scaleFactorText = '';
        _scaleStartPositions = [];
        _scaleStartPointer = null;
        _isDirty = _scaleStartDirty;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      setState(() {
        _scaleActive = false;
        _scaleStartPositions = [];
        _scaleStartPointer = null;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      _scaleFactorText = _scaleFactorText.isEmpty
          ? ''
          : _scaleFactorText.substring(0, _scaleFactorText.length - 1);
      _updateTypedScale();
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (character != null && RegExp(r'^[0-9.]$').hasMatch(character)) {
      if (!(character == '.' && _scaleFactorText.contains('.'))) {
        _scaleFactorText += character;
        _updateTypedScale();
      }
    }
    return KeyEventResult.handled;
  }

  void _beginScale() {
    if (_objects.isEmpty) return;
    _recordUndo();
    _scaleStartPositions =
        _mesh.vertices.map((vertex) => vertex.position).toList();
    _scaleStartDirty = _isDirty;
    _scaleFactorText = '';
    _scaleStartPointer = null;
    setState(() => _scaleActive = true);
  }

  Future<void> _showScaleDialog() async {
    final factor = TextEditingController(text: '1.0');
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scale active mesh'),
        content: TextField(
          controller: factor,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Uniform scale factor'),
          onSubmitted: (text) {
            final parsed = double.tryParse(text);
            if (parsed != null && parsed > 0 && parsed.isFinite) {
              Navigator.pop(context, parsed);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(factor.text);
              if (parsed != null && parsed > 0 && parsed.isFinite) {
                Navigator.pop(context, parsed);
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (value == null) return;
    _recordUndo();
    setState(() {
      _mesh.scaleUniform(value);
      _isDirty = true;
    });
  }

  void _applyScaleFactor(double factor) {
    if (_scaleStartPositions.length != _mesh.vertices.length) return;
    final mesh = _mesh;
    for (var index = 0; index < mesh.vertices.length; index++) {
      mesh.vertices[index] = MeshVertex(_scaleStartPositions[index]);
    }
    mesh.scaleUniform(factor);
    _isDirty = true;
  }

  void _updateTypedScale() {
    final factor = double.tryParse(_scaleFactorText);
    if (factor != null && factor.isFinite && factor > 0) {
      setState(() => _applyScaleFactor(factor));
    }
  }

  void _toggleSelectAll() {
    setState(() {
      final visibleMeshes = [
        for (var index = 0; index < _objects.length; index++)
          if (_objects[index].visible) index,
      ];
      final allVisibleMeshesSelected = visibleMeshes.isNotEmpty &&
          visibleMeshes.every(_selectedMeshIndices.contains);
      _selectedMeshIndices
        ..clear()
        ..addAll(allVisibleMeshesSelected ? const <int>[] : visibleMeshes);
      var selectingAll = true;
      if (_mode == EditMode.vertex) {
        if (_selectedVertices.length == _mesh.vertices.length) {
          _selectedVertices.clear();
          selectingAll = false;
        } else {
          _selectedVertices
            ..clear()
            ..addAll(List.generate(_mesh.vertices.length, (index) => index));
        }
      } else if (_selectedFaces.length == _mesh.faces.length) {
        _selectedFaces.clear();
        _selectedFace = null;
        selectingAll = false;
      } else {
        _selectedFaces
          ..clear()
          ..addAll(List.generate(_mesh.faces.length, (index) => index));
        _selectedFace = _selectedFaces.isEmpty ? null : _selectedFaces.last;
      }
      if (_page == EditorPage.uv) {
        _selectedUvs
          ..clear()
          ..addAll(selectingAll
              ? [
                  for (var faceIndex = 0;
                      faceIndex < _mesh.faces.length;
                      faceIndex++)
                    for (var corner = 0;
                        corner < _mesh.faces[faceIndex].uv.length;
                        corner++)
                      (faceIndex, corner),
                ]
              : const <(int, int)>[]);
      }
    });
  }

  void _deleteSelection() {
    final facesToDelete = _selectedFaces.isNotEmpty
        ? _selectedFaces
        : (_selectedFace == null ? const <int>[] : [_selectedFace!]);
    if ((_mode == EditMode.vertex && _selectedVertices.isEmpty) ||
        (_mode == EditMode.face && facesToDelete.isEmpty)) {
      return;
    }
    _recordUndo();
    final changed = _mode == EditMode.vertex
        ? _mesh.deleteVertices(_selectedVertices)
        : _mesh.deleteFaces(facesToDelete);
    if (!changed) {
      _undoHistory.removeLast();
      return;
    }
    setState(() {
      _selectedVertices.clear();
      _selectedFaces.clear();
      _selectedUvs.clear();
      _selectedFace = _mesh.faces.isEmpty ? null : 0;
      _isDirty = true;
    });
  }

  void _joinSelectedVertices() {
    if (_mode != EditMode.vertex || _selectedVertices.length != 2) {
      _showMessage('Select exactly two vertices to join.');
      return;
    }
    final selection = _selectedVertices.toList()..sort();
    _recordUndo();
    if (!_mesh.joinVertices(selection)) {
      _undoHistory.removeLast();
      _showMessage('Those vertices could not be joined.');
      return;
    }
    setState(() {
      _selectedVertices
        ..clear()
        ..add(selection.first);
      _selectedFaces.clear();
      _selectedFace = _mesh.faces.isEmpty ? null : 0;
      _isDirty = true;
    });
  }

  void _flipSelectedFaceNormals() {
    final facesToFlip = _selectedFaces.isNotEmpty
        ? _selectedFaces
        : (_selectedFace == null ? const <int>{} : {_selectedFace!});
    if (_mode != EditMode.face || facesToFlip.isEmpty) {
      _showMessage('Select at least one face to flip its normal.');
      return;
    }
    _recordUndo();
    if (!_mesh.flipFaceNormals(facesToFlip)) {
      _undoHistory.removeLast();
      _showMessage('Could not flip the selected face normals.');
      return;
    }
    setState(() => _isDirty = true);
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
    _recordUndo();
    setState(() {
      _referenceImages.remove(_activeViewportIndex);
      _referenceImages[_activeViewportIndex] = frame.image;
    });
  }

  void _removeReferenceImage() {
    _recordUndo();
    setState(() => _referenceImages.remove(_activeViewportIndex));
  }

  void _connectVertices() {
    if (!_canAddFaces(1)) return;
    _recordUndo();
    if (!_mesh.addQuad(_selectedVertices)) {
      _undoHistory.removeLast();
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

  void _createTriangle() {
    if (!_canAddFaces(1)) return;
    _recordUndo();
    if (!_mesh.addTriangle(_selectedVertices)) {
      _undoHistory.removeLast();
      _showMessage('Select three distinct vertices to make a triangle.');
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

  Future<void> _finishFlatSurfaceDrag(
    Rect selection,
    Size size,
    ViewportState viewport,
  ) async {
    if (selection.width < 6 || selection.height < 6) {
      _showMessage('Drag a larger region to create a flat surface.');
      return;
    }
    final result = await _showFlatSurfaceDialog();
    if (result == null || !mounted) return;
    final (name, horizontalSteps, verticalSteps) = result;
    if (!_canAddFaces(horizontalSteps * verticalSteps)) return;
    final surface = MeshModel.empty();
    final corners = [
      selection.topLeft,
      selection.topRight,
      selection.bottomRight,
      selection.bottomLeft,
    ].map((point) => _worldPosition(point, size, viewport)).toList();
    if (!surface.addGridSurface(corners, horizontalSteps, verticalSteps)) {
      _showMessage('Could not create a surface with those dimensions.');
      return;
    }

    _recordUndo();
    setState(() {
      _objects.add(SceneObject(name, surface));
      _activeObjectIndex = _objects.length - 1;
      _selectedMeshIndices
        ..clear()
        ..add(_activeObjectIndex);
      _selectedVertices.clear();
      _selectedFaces
        ..clear()
        ..addAll(List.generate(surface.faces.length, (index) => index));
      _selectedFace = surface.faces.isEmpty ? null : 0;
      _mode = EditMode.face;
      _tool = ActiveTool.select;
      _surfaceSelectionStart = null;
      _surfaceSelectionEnd = null;
      _isDirty = true;
    });
  }

  Future<(String, int, int)?> _showFlatSurfaceDialog() async {
    var surfaceName = 'Surface';
    var horizontalText = '2';
    var verticalText = '2';
    String? error;
    final result = await showDialog<(String, int, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Define flat surface'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  autofocus: true,
                  onChanged: (value) => surfaceName = value,
                  decoration: const InputDecoration(
                    labelText: 'Object name',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (value) => horizontalText = value,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Horizontal faces',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        onChanged: (value) => verticalText = value,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Vertical faces',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = surfaceName.trim();
                final horizontal = int.tryParse(horizontalText);
                final vertical = int.tryParse(verticalText);
                if (name.isEmpty) {
                  setDialogState(() => error = 'Enter an object name.');
                  return;
                }
                if (_objects.any(
                  (object) => object.name.toLowerCase() == name.toLowerCase(),
                )) {
                  setDialogState(
                    () => error = 'An object with that name already exists.',
                  );
                  return;
                }
                if (horizontal == null ||
                    vertical == null ||
                    horizontal < 1 ||
                    vertical < 1 ||
                    horizontal > 64 ||
                    vertical > 64) {
                  setDialogState(
                    () => error = 'Face counts must be between 1 and 64.',
                  );
                  return;
                }
                Navigator.pop(context, (name, horizontal, vertical));
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  void _mergeSelectedTriangles() {
    _recordUndo();
    final merged = _mesh.mergeTriangles(_selectedFaces);
    if (merged == null) {
      _undoHistory.removeLast();
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
    if (_stripEdge.length >= 2 && !_canAddFaces(1)) return;
    _recordUndo();
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
      _undoHistory.removeLast();
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
    if (!_verticesToRotate.isNotEmpty) {
      _showMessage('Select vertices, a face, or a mesh to rotate.');
      return;
    }
    _selectAxis(axis);
    _recordUndo();
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
    var axis = _selectedAxis;
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
    if (axis == null) return;
    _recordUndo();
    if (!_mesh.mirror(axis.index)) {
      _undoHistory.removeLast();
      return;
    }
    setState(() {
      _selectedVertices.clear();
      _selectedFaces.clear();
      _selectedFace = _mesh.faces.isEmpty ? null : 0;
      _isDirty = true;
    });
  }

  Future<void> _deleteActiveMesh() => _deleteMeshAt(_activeObjectIndex);

  Future<void> _deleteMeshAt(int index) async {
    if (index < 0 || index >= _objects.length) return;
    await _deleteMeshes(
      [_objects[index]],
      title: 'Delete mesh?',
      message: 'Delete "${_objects[index].name}"?',
    );
  }

  Future<void> _deleteMeshGroup(String groupName) async {
    final groupObjects =
        _objects.where((object) => object.groupName == groupName).toList();
    if (groupObjects.isEmpty) return;
    await _deleteMeshes(
      groupObjects,
      title: 'Delete mesh group?',
      message: 'Delete "$groupName" and all ${groupObjects.length} '
          'contained ${groupObjects.length == 1 ? 'mesh' : 'meshes'}?',
    );
  }

  Future<void> _deleteMeshes(
    List<SceneObject> objects, {
    required String title,
    required String message,
  }) async {
    final targets = Set<SceneObject>.identity()..addAll(objects);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
    if (!mounted) return;
    final deleted = _objects.where(targets.contains).toList();
    if (deleted.length != targets.length) return;
    final activeObject = _objects[_activeObjectIndex];
    final activeDeleted = targets.contains(activeObject);
    final activeIndexBeforeDelete = _activeObjectIndex;
    final selectedObjects = [
      for (final index in _selectedMeshIndices)
        if (index >= 0 && index < _objects.length) _objects[index],
    ];
    _recordUndo();
    setState(() {
      _objects.removeWhere(targets.contains);
      _collapsedMeshGroups.removeWhere(
        (name) => !_objects.any((object) => object.groupName == name),
      );
      if (_objects.isEmpty) {
        _objects.add(SceneObject('Mesh_1', MeshModel.empty()));
        _activeObjectIndex = 0;
        _selectedMeshIndices
          ..clear()
          ..add(0);
      } else {
        _activeObjectIndex = activeDeleted
            ? math.min(activeIndexBeforeDelete, _objects.length - 1)
            : _objects.indexOf(activeObject);
        _selectedMeshIndices
          ..clear()
          ..addAll([
            for (final object in selectedObjects)
              if (!targets.contains(object)) _objects.indexOf(object),
          ]);
        if (_selectedMeshIndices.isEmpty) {
          _selectedMeshIndices.add(_activeObjectIndex);
        }
      }
      _selectedVertices.clear();
      _selectedFaces.clear();
      _selectedFace = _mesh.faces.isEmpty ? null : 0;
      _isDirty = true;
    });
  }

  Future<void> _renameMesh(int index) async {
    if (index < 0 || index >= _objects.length) return;
    final object = _objects[index];
    final controller = TextEditingController(text: object.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename mesh'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Mesh name'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    final trimmed = name?.trim();
    if (trimmed == null ||
        trimmed.isEmpty ||
        !mounted ||
        index >= _objects.length ||
        !identical(_objects[index], object)) {
      return;
    }
    _recordUndo();
    setState(() {
      object.name = trimmed;
      _isDirty = true;
    });
  }

  Future<void> _duplicateMesh(int index) async {
    if (index < 0 || index >= _objects.length) return;
    final source = _objects[index];
    if (!_canAddFaces(source.mesh.faces.length)) return;
    final mesh = MeshModel.fromData(
      source.mesh.vertices.map((vertex) => vertex.position),
      source.mesh.faces.map((face) => MeshFace(face.vertices, face.uv)),
      smoothShading: source.mesh.smoothShading,
    );
    mesh.moveVertices(
      List.generate(mesh.vertices.length, (vertexIndex) => vertexIndex),
      const Vec3(1.5, 0, 0),
    );
    ui.Image? image;
    try {
      if (source.texturePath != null &&
          await File(source.texturePath!).exists()) {
        image =
            await _decodeImage(await File(source.texturePath!).readAsBytes());
      }
    } catch (error) {
      if (mounted) _showMessage('Could not copy mesh texture: $error');
      return;
    }
    if (!mounted) {
      image?.dispose();
      return;
    }
    _recordUndo();
    final copyName = _uniqueMeshName('${source.name}_copy');
    setState(() {
      _objects.add(
        SceneObject(
          copyName,
          mesh,
          texturePath: source.texturePath,
          textureImage: image,
          groupName: source.groupName,
          rvCoordinateScale: source.rvCoordinateScale,
          rvCoordinateOrigin: source.rvCoordinateOrigin,
          rvTextureAnimations: source.rvTextureAnimations,
          rvTextures: Map.of(source.rvTextures),
        ),
      );
      _activeObjectIndex = _objects.length - 1;
      _selectedMeshIndices
        ..clear()
        ..add(_activeObjectIndex);
      _selectedVertices.clear();
      _selectedFaces.clear();
      _selectedFace = mesh.faces.isEmpty ? null : 0;
      _isDirty = true;
    });
  }

  String _uniqueMeshName(String preferred) {
    final names = _objects.map((object) => object.name).toSet();
    if (!names.contains(preferred)) return preferred;
    var suffix = 2;
    while (names.contains('${preferred}_$suffix')) {
      suffix++;
    }
    return '${preferred}_$suffix';
  }

  Future<void> _showMeshContextMenu(int index, Offset position) async {
    if (index < 0 || index >= _objects.length) return;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        _contextMenuItem(
            'rename', 'Rename mesh', Icons.drive_file_rename_outline),
        _contextMenuItem('copy', 'Create copy', Icons.copy_outlined),
        _contextMenuItem('delete', 'Delete mesh', Icons.delete_outline),
      ],
    );
    switch (action) {
      case 'rename':
        await _renameMesh(index);
      case 'copy':
        await _duplicateMesh(index);
      case 'delete':
        await _deleteMeshAt(index);
    }
  }

  Future<void> _showGroupContextMenu(String groupName, Offset position) async {
    if (!_objects.any((object) => object.groupName == groupName)) return;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        _contextMenuItem(
            'rename', 'Rename group', Icons.drive_file_rename_outline),
        _contextMenuItem('copy', 'Create group copy', Icons.copy_outlined),
        _contextMenuItem('delete', 'Delete group', Icons.delete_outline),
      ],
    );
    switch (action) {
      case 'rename':
        await _renameMeshGroup(groupName);
      case 'copy':
        await _duplicateMeshGroup(groupName);
      case 'delete':
        await _deleteMeshGroup(groupName);
    }
  }

  PopupMenuItem<String> _contextMenuItem(
    String value,
    String label,
    IconData icon,
  ) {
    return PopupMenuItem<String>(
      value: value,
      height: 34,
      padding: EdgeInsets.zero,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF48505E)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  void _selectModelBox(Rect selection, Size size, ViewportState viewport) {
    setState(() {
      _selectedVertices.clear();
      _selectedFaces.clear();
      if (_mode == EditMode.vertex) {
        for (var index = 0; index < _mesh.vertices.length; index++) {
          if (selection.contains(
            _project(_mesh.vertices[index].position, size, viewport),
          )) {
            _selectedVertices.add(index);
          }
        }
      } else {
        for (var faceIndex = 0; faceIndex < _mesh.faces.length; faceIndex++) {
          final face = _mesh.faces[faceIndex];
          final points = face.vertices
              .map((index) =>
                  _project(_mesh.vertices[index].position, size, viewport))
              .toList();
          if (points.isNotEmpty &&
              selection.contains(Offset(
                points.map((point) => point.dx).reduce((a, b) => a + b) /
                    points.length,
                points.map((point) => point.dy).reduce((a, b) => a + b) /
                    points.length,
              ))) {
            _selectedFaces.add(faceIndex);
          }
        }
        _selectedFace = _selectedFaces.isEmpty ? null : _selectedFaces.last;
      }
    });
  }

  void _handleModelTap(
    Offset point,
    Size size,
    ViewportState viewport,
  ) {
    if (_tool == ActiveTool.addSurface) return;
    if (_tool == ActiveTool.strip && _mode == EditMode.vertex) {
      _addStripPoint(point, size, viewport);
      return;
    }
    if (_tool == ActiveTool.addVertex && _mode == EditMode.vertex) {
      _recordUndo();
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
        _rvHighlightedFaces.clear();
        if (hit != null) {
          if (!_selectedVertices.add(hit)) _selectedVertices.remove(hit);
        } else {
          _selectedVertices.clear();
        }
      });
    } else {
      final hit = _hitFace(point, size, viewport);
      setState(() {
        _rvHighlightedFaces.clear();
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
        .where((object) => object.visible)
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
          groupName: object.groupName,
          rvCoordinateScale: object.rvCoordinateScale,
          rvCoordinateOrigin: object.rvCoordinateOrigin,
          rvTextureAnimations: object.rvTextureAnimations,
          rvTexturePaths: object.rvTexturePaths,
        ),
      )
      .toList();

  List<int> get _selectedRvFaces {
    final selected = _selectedFaces.isNotEmpty
        ? _selectedFaces
        : (_selectedFace == null ? const <int>{} : {_selectedFace!});
    return selected
        .where((index) => index >= 0 && index < _mesh.faces.length)
        .toList();
  }

  void _applyRvFlag(int flag, {bool clear = false}) {
    final faceIndices = _selectedRvFaces;
    if (faceIndices.isEmpty) {
      _showMessage('Select one or more faces first.');
      return;
    }
    _recordUndo();
    setState(() {
      for (final index in faceIndices) {
        final face = _mesh.faces[index];
        var rvType = clear ? face.rvType & ~flag : face.rvType | flag;
        if (!clear && flag == rvFlagEnvMap) {
          rvType &= ~rvFlagNoEnvMap;
        } else if (!clear && flag == rvFlagNoEnvMap) {
          rvType &= ~rvFlagEnvMap;
        }
        _mesh.faces[index] = MeshFace.copyOf(
          face,
          rvType: rvType,
        );
      }
      _rvHighlightedFaces.clear();
      _isDirty = true;
    });
  }

  void _selectRvFacesWithFlag() {
    final matches = <int>{
      for (var index = 0; index < _mesh.faces.length; index++)
        if ((_mesh.faces[index].rvType & _rvFlagToSelect) != 0) index,
    };
    setState(() {
      _rvHighlightedFaces
        ..clear()
        ..addAll(matches);
      _mode = EditMode.face;
      _selectedFaces.clear();
      _selectedFace = null;
    });
    if (matches.isEmpty) _showMessage('No faces use the selected RV flag.');
  }

  static const List<(String, int)> _rvFaceFlags = [
    ('Invisible', rvFlagInvisible),
    ('Mirroring', rvFlagMirror),
    ('No EnvMap', rvFlagNoEnvMap),
    ('Double-Sided', rvFlagDoubleSided),
    ('Add Blending', rvFlagAddBlending),
    ('EnvMap', rvFlagEnvMap),
    ('Translucent', rvFlagTranslucent),
  ];

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

  Future<void> _exportModel() async {
    final location = await getSaveLocation(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Wavefront OBJ (*.obj)', extensions: ['obj']),
        XTypeGroup(label: 'RV model (*.prm)', extensions: ['prm']),
        XTypeGroup(label: 'RV world (*.w)', extensions: ['w']),
      ],
      suggestedName: 'Blunder_Export.obj',
      confirmButtonText: 'Export',
    );
    if (location == null) return;
    final extension = location.path.split('.').last.toLowerCase();
    final supportedExtension =
        {'obj', 'prm', 'w'}.contains(extension) ? extension : 'obj';
    final path = location.path.toLowerCase().endsWith('.$supportedExtension')
        ? location.path
        : '${location.path}.$supportedExtension';
    try {
      if (supportedExtension == 'obj') {
        await ModelIo.writeObj(path, _documentData());
      } else {
        final meshes = [
          for (final object in _objects)
            RvExportMesh(
              mesh: object.mesh,
              coordinateScale: object.rvCoordinateScale ?? 0.01,
              coordinateOrigin:
                  object.rvCoordinateOrigin ?? const Vec3(0, 0, 0),
            ),
        ];
        final bytes = supportedExtension == 'prm'
            ? RvModelIo.encodePrm(meshes)
            : RvModelIo.encodeWorld(
                meshes,
                textureAnimations: _objects
                    .firstWhere(
                      (object) => object.rvTextureAnimations.isNotEmpty,
                      orElse: () => _objects.first,
                    )
                    .rvTextureAnimations,
              );
        await File(path).writeAsBytes(bytes, flush: true);
      }
      if (mounted) _showMessage('Exported ${File(path).uri.pathSegments.last}');
    } catch (error) {
      if (mounted) _showMessage('Could not export model: $error');
    }
  }

  Future<void> _openScene() async {
    if (!await _confirmUnsavedChanges()) return;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Blunder project', extensions: ['pky', 'pkg']),
      ],
      confirmButtonText: 'Open',
    );
    if (file == null) return;
    await _loadScenePath(file.path);
  }

  Future<void> _importFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Wavefront OBJ', extensions: ['obj']),
        XTypeGroup(label: 'RV (*.prm)', extensions: ['prm']),
        XTypeGroup(label: 'RV (*.w)', extensions: ['w']),
      ],
      confirmButtonText: 'Import',
    );
    if (file == null) return;
    final extension = file.path.split('.').last.toLowerCase();
    if (extension == 'prm' || extension == 'w') {
      await _importRv(file.path, extension);
      return;
    }
    await _importObj(file.path);
  }

  Future<void> _importObj(String path) async {
    final loadedObjects = <SceneObject>[];
    try {
      final imported = await ModelIo.readObj(path);
      final importedFaceCount = imported.fold<int>(
        0,
        (count, object) => count + object.mesh.faces.length,
      );
      if (!_canAddFaces(importedFaceCount)) return;
      final existingGroups = _objects
          .map((object) => object.groupName)
          .whereType<String>()
          .toSet();
      final existingMeshNames = _objects.map((object) => object.name).toSet();
      final baseGroup = imported.first.groupName ?? 'Imported OBJ';
      var groupName = baseGroup;
      var suffix = 2;
      while (existingGroups.contains(groupName)) {
        groupName = '${baseGroup}_$suffix';
        suffix++;
      }

      var unavailableTextures = 0;
      for (final object in imported) {
        final texturePath = object.texturePath;
        ui.Image? textureImage;
        if (texturePath != null) {
          if (await File(texturePath).exists()) {
            try {
              textureImage =
                  await _decodeImage(await File(texturePath).readAsBytes());
            } on Exception {
              unavailableTextures++;
            }
          } else {
            unavailableTextures++;
          }
        }
        var meshName = object.name;
        var meshSuffix = 2;
        while (existingMeshNames.contains(meshName)) {
          meshName = '${object.name}_$meshSuffix';
          meshSuffix++;
        }
        existingMeshNames.add(meshName);
        loadedObjects.add(
          SceneObject(
            meshName,
            object.mesh,
            texturePath: textureImage == null ? null : texturePath,
            textureImage: textureImage,
            groupName: groupName,
          ),
        );
      }
      if (!mounted) {
        for (final object in loadedObjects) {
          object.textureImage?.dispose();
        }
        return;
      }
      _recordUndo();
      setState(() {
        _objects.addAll(loadedObjects);
        _activeObjectIndex = _objects.length - loadedObjects.length;
        _selectedMeshIndices
          ..clear()
          ..addAll(
            List.generate(
              loadedObjects.length,
              (index) => _activeObjectIndex + index,
            ),
          );
        _selectedVertices.clear();
        _selectedFaces.clear();
        _selectedFace = _mesh.faces.isEmpty ? null : 0;
        _tool = ActiveTool.select;
        _lockedAxis = null;
        _isDirty = true;
      });
      _showMessage(
        unavailableTextures == 0
            ? 'Imported ${File(path).uri.pathSegments.last}'
            : 'Imported OBJ; $unavailableTextures texture(s) could not be loaded.',
      );
    } catch (error) {
      for (final object in loadedObjects) {
        object.textureImage?.dispose();
      }
      if (mounted) _showMessage('Could not import OBJ: $error');
    }
  }

  Future<void> _importRv(String path, String extension) async {
    final loadTextures = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import RV model'),
        content:
            const Text('Load matching texture files from the same folder?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Skip textures'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Load textures'),
          ),
        ],
      ),
    );
    if (loadTextures == null) return;
    late final RvImportResult imported;
    try {
      imported = extension == 'prm'
          ? await RvModelIo.readPrm(path)
          : await RvModelIo.readWorld(path);
    } catch (error) {
      if (mounted) _showMessage('Could not import RV file: $error');
      return;
    }
    final importedFaceCount = imported.meshes.fold<int>(
      0,
      (count, item) => count + item.mesh.faces.length,
    );
    if (!_canAddFaces(importedFaceCount)) return;

    final loadedObjects = <SceneObject>[];
    final existingNames = _objects.map((object) => object.name).toSet();
    var loadedTextureCount = 0;
    var unavailableTextureCount = 0;
    final loadedTextures = <int, ui.Image>{};
    final loadedTexturePaths = <int, String>{};
    try {
      if (loadTextures) {
        final textureIndices = imported.meshes
            .expand((item) => item.mesh.faces)
            .map((face) => face.rvTextureIndex)
            .where((index) => index >= 0)
            .toSet();
        for (final textureIndex in textureIndices) {
          final texturePath =
              await _findRvTexture(path, extension, textureIndex);
          if (texturePath == null) {
            unavailableTextureCount++;
            continue;
          }
          try {
            loadedTextures[textureIndex] =
                await _decodeImage(await File(texturePath).readAsBytes());
            loadedTexturePaths[textureIndex] = texturePath;
            loadedTextureCount++;
          } on Exception {
            unavailableTextureCount++;
          }
        }
      }
      for (final item in imported.meshes) {
        var objectName = item.name;
        var suffix = 2;
        while (existingNames.contains(objectName)) {
          objectName = '${item.name}_$suffix';
          suffix++;
        }
        existingNames.add(objectName);
        loadedObjects.add(
          SceneObject(
            objectName,
            item.mesh,
            groupName: File(path).uri.pathSegments.last,
            rvCoordinateScale: item.coordinateScale,
            rvCoordinateOrigin: item.coordinateOrigin,
            rvTextureAnimations: item == imported.meshes.first
                ? imported.textureAnimations
                : const [],
            rvTextures: Map.of(loadedTextures),
            rvTexturePaths: Map.of(loadedTexturePaths),
          ),
        );
      }
      if (!mounted) {
        for (final image in loadedTextures.values.toSet()) {
          image.dispose();
        }
        return;
      }
      _recordUndo();
      setState(() {
        _objects.addAll(loadedObjects);
        _activeObjectIndex = _objects.length - loadedObjects.length;
        _selectedMeshIndices
          ..clear()
          ..addAll(
            List.generate(
              loadedObjects.length,
              (index) => _activeObjectIndex + index,
            ),
          );
        _selectedVertices.clear();
        _selectedFaces.clear();
        _rvHighlightedFaces.clear();
        _selectedFace = _mesh.faces.isEmpty ? null : 0;
        _tool = ActiveTool.select;
        _lockedAxis = null;
        _isDirty = true;
      });
      if (!loadTextures) {
        _showMessage(
          'Imported ${File(path).uri.pathSegments.last}; textures skipped.',
        );
      } else if (loadedTextureCount == 0) {
        _showMessage('No texture data. Please add manually');
      } else {
        _showMessage(
          'Imported ${File(path).uri.pathSegments.last} with '
          '$loadedTextureCount texture(s)'
          '${unavailableTextureCount == 0 ? '' : '; '
              '$unavailableTextureCount unavailable'}',
        );
      }
    } catch (error) {
      for (final image in loadedTextures.values.toSet()) {
        image.dispose();
      }
      if (mounted) _showMessage('Could not import RV file: $error');
    }
  }

  Future<String?> _findRvTexture(
    String sourcePath,
    String extension,
    int textureIndex,
  ) async {
    final source = File(sourcePath);
    final directory = source.parent.path;
    final basename = source.uri.pathSegments.last.replaceFirst(
      RegExp(r'\.[^.]+$'),
      '',
    );
    final folderName = source.parent.path
        .split(RegExp(r'[\\/]'))
        .where((segment) => segment.isNotEmpty)
        .last;
    final candidates = extension == 'w'
        ? [
            '$directory${Platform.pathSeparator}'
                '$basename${_rvTextureSuffix(textureIndex)}.bmp',
            '$directory${Platform.pathSeparator}'
                '$basename${_rvTextureSuffix(textureIndex)}.png',
          ]
        : [
            '$directory${Platform.pathSeparator}$basename.bmp',
            '$directory${Platform.pathSeparator}car.bmp',
            '$directory${Platform.pathSeparator}'
                '$folderName.bmp',
          ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }

  String _rvTextureSuffix(int index) {
    if (index < 0) return '';
    var value = index + 1;
    var suffix = '';
    while (value > 0) {
      value--;
      suffix = String.fromCharCode(97 + value % 26) + suffix;
      value ~/= 26;
    }
    return suffix;
  }

  Future<void> _loadScenePath(String path) async {
    try {
      final imported = await ModelIo.readPky(path);
      final loadedObjects = <SceneObject>[];
      final rvTextureImageCache = <String, ui.Image>{};
      var missingRvTextures = 0;
      for (final object in imported) {
        var texturePath = object.texturePath;
        if (texturePath != null && !File(texturePath).isAbsolute) {
          texturePath = '${File(path).parent.path}${Platform.pathSeparator}'
              '${texturePath.replaceAll(RegExp(r'[\\/]'), Platform.pathSeparator)}';
        }
        final textureImage =
            texturePath != null && await File(texturePath).exists()
                ? await _decodeImage(await File(texturePath).readAsBytes())
                : null;
        final rvTexturePaths = <int, String>{};
        final rvTextures = <int, ui.Image>{};
        for (final entry in object.rvTexturePaths.entries) {
          var rvTexturePath = entry.value;
          if (!File(rvTexturePath).isAbsolute) {
            rvTexturePath = '${File(path).parent.path}${Platform.pathSeparator}'
                '${rvTexturePath.replaceAll(RegExp(r'[\\/]'), Platform.pathSeparator)}';
          }
          if (!await File(rvTexturePath).exists()) {
            missingRvTextures++;
            continue;
          }
          if (!rvTextureImageCache.containsKey(rvTexturePath)) {
            rvTextureImageCache[rvTexturePath] =
                await _decodeImage(await File(rvTexturePath).readAsBytes());
          }
          rvTextures[entry.key] = rvTextureImageCache[rvTexturePath]!;
          rvTexturePaths[entry.key] = rvTexturePath;
        }
        loadedObjects.add(
          SceneObject(
            object.name,
            object.mesh,
            texturePath: texturePath,
            textureImage: textureImage,
            groupName: object.groupName,
            rvCoordinateScale: object.rvCoordinateScale,
            rvCoordinateOrigin: object.rvCoordinateOrigin,
            rvTextureAnimations: object.rvTextureAnimations,
            rvTextures: rvTextures,
            rvTexturePaths: rvTexturePaths,
          ),
        );
      }
      _undoHistory.clear();
      _redoHistory.clear();
      for (final object in _objects) {
        object.textureImage?.dispose();
        for (final image in object.rvTextures.values) {
          image.dispose();
        }
      }
      setState(() {
        _objects
          ..clear()
          ..addAll(loadedObjects);
        if (_objects.isEmpty) {
          _objects.add(SceneObject('Mesh_1', MeshModel.empty()));
        }
        _activeObjectIndex = 0;
        _selectedMeshIndices
          ..clear()
          ..add(0);
        _selectedVertices.clear();
        _selectedFaces.clear();
        _rvHighlightedFaces.clear();
        _selectedFace = _mesh.faces.isEmpty ? null : 0;
        _tool = ActiveTool.select;
        _lockedAxis = null;
        _currentFilePath = path;
        _isDirty = false;
        _page = EditorPage.model;
      });
      _showMessage(
        missingRvTextures == 0
            ? 'Opened ${File(path).uri.pathSegments.last}'
            : 'Opened scene; $missingRvTextures RV texture(s) are missing.',
      );
    } catch (error) {
      _showMessage('Could not open scene file: $error');
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
    _undoHistory.clear();
    _redoHistory.clear();
    for (final object in _objects) {
      object.textureImage?.dispose();
      for (final image in object.rvTextures.values) {
        image.dispose();
      }
    }
    setState(() {
      _objects
        ..clear()
        ..add(SceneObject('Mesh_1', MeshModel.starterPlane()));
      _activeObjectIndex = 0;
      _selectedMeshIndices
        ..clear()
        ..add(0);
      _selectedVertices.clear();
      _selectedFaces.clear();
      _rvHighlightedFaces.clear();
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
      _recordUndo();
      setState(() {
        object.texturePath = file.path;
        object.textureImage = image;
        if (object.rvCoordinateScale != null) {
          for (final faceIndex in _selectedRvFaces) {
            final textureIndex = object.mesh.faces[faceIndex].rvTextureIndex;
            object.rvTextures[textureIndex] = image;
            object.rvTexturePaths[textureIndex] = file.path;
          }
        }
        _isDirty = true;
      });
    } catch (error) {
      if (mounted) _showMessage('Could not load texture: $error');
    }
  }

  List<int> get _selectedVisibleMeshIndices => _selectedMeshIndices
      .where((index) => index >= 0 && index < _objects.length)
      .where((index) => _objects[index].visible)
      .toList()
    ..sort();

  int get _selectedAtlasTextureCount {
    final keys = <Object>{};
    for (final meshIndex in _selectedVisibleMeshIndices) {
      final object = _objects[meshIndex];
      final keysByTextureIndex = <int, Object>{};
      for (final face in object.mesh.faces) {
        final textureIndex = face.rvTextureIndex;
        keys.add(
          keysByTextureIndex.putIfAbsent(textureIndex, () {
            final image =
                object.rvTextures[textureIndex] ?? object.textureImage;
            return _atlasTextureKey(object, textureIndex, image);
          }),
        );
      }
    }
    return keys.length;
  }

  Object _atlasTextureKey(
    SceneObject object,
    int textureIndex,
    ui.Image? image,
  ) {
    final path = object.rvTexturePaths[textureIndex] ??
        (object.rvTextures.containsKey(textureIndex)
            ? null
            : object.texturePath);
    if (path != null && path.isNotEmpty) {
      final normalized = File(path).absolute.path.replaceAll('\\', '/');
      return 'path:${Platform.isWindows ? normalized.toLowerCase() : normalized}';
    }
    return image ?? 'untextured';
  }

  Future<void> _generateAtlas() async {
    final meshIndices = _selectedVisibleMeshIndices;
    if (meshIndices.isEmpty) {
      _showMessage('Select one or more visible meshes in the Scene panel.');
      return;
    }
    if (meshIndices.every((index) => _objects[index].mesh.faces.isEmpty)) {
      _showMessage('The selected meshes do not contain any faces.');
      return;
    }
    final location = await getSaveLocation(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PNG texture atlas', extensions: ['png']),
      ],
      suggestedName: 'Blunder_Atlas.png',
      confirmButtonText: 'Create Atlas',
    );
    if (location == null || !mounted) return;
    final outputPath = location.path.toLowerCase().endsWith('.png')
        ? location.path
        : '${location.path}.png';
    setState(() => _isGeneratingAtlas = true);

    ui.Image? atlasImage;
    try {
      final sources = AtlasTextureRegistry<ui.Image>();
      final sourceForFaces = <int, List<int>>{};

      int sourceIndex(SceneObject object, int textureIndex, ui.Image? image) {
        return sources.indexFor(
          _atlasTextureKey(object, textureIndex, image),
          image,
        );
      }

      for (final meshIndex in meshIndices) {
        final object = _objects[meshIndex];
        final sourceIdsByTextureIndex = <int, int>{};
        sourceForFaces[meshIndex] = [
          for (final face in object.mesh.faces)
            sourceIdsByTextureIndex.putIfAbsent(
              face.rvTextureIndex,
              () => sourceIndex(
                object,
                face.rvTextureIndex,
                object.rvTextures[face.rvTextureIndex] ?? object.textureImage,
              ),
            ),
        ];
        if (object.mesh.faces.any(
          (face) => face.uv.length != face.vertices.length,
        )) {
          throw const FormatException(
            'Every selected face needs one UV coordinate per vertex.',
          );
        }
      }

      final sourceImages = sources.textures;
      final sourceSizes = [
        for (final image in sourceImages)
          AtlasTextureSize(image?.width ?? 1, image?.height ?? 1),
      ];
      final layout = AtlasPacker.pack(
        textures: sourceSizes,
        maxSize: _atlasMaxSize,
        padding: _atlasPadding,
        shape: _atlasShape,
        density: _atlasDensity,
        autoFit: _atlasAutoFit,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawColor(Colors.transparent, BlendMode.src);
      for (var index = 0; index < sourceImages.length; index++) {
        final image = sourceImages[index];
        final region = layout.regions[index];
        final destination = Rect.fromLTWH(
          region.x.toDouble(),
          region.y.toDouble(),
          region.width.toDouble(),
          region.height.toDouble(),
        );
        if (image == null) {
          canvas.drawRect(destination, Paint()..color = Colors.white);
        } else {
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            destination,
            Paint()..filterQuality = FilterQuality.high,
          );
        }
      }
      final picture = recorder.endRecording();
      atlasImage = await picture.toImage(layout.width, layout.height);
      picture.dispose();
      final png = await atlasImage.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        throw const FormatException('Could not encode the atlas as PNG.');
      }
      await File(outputPath).writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        flush: true,
      );

      _recordUndo();
      setState(() {
        for (final meshIndex in meshIndices) {
          final object = _objects[meshIndex];
          final faceSources = sourceForFaces[meshIndex]!;
          for (var faceIndex = 0;
              faceIndex < object.mesh.faces.length;
              faceIndex++) {
            final face = object.mesh.faces[faceIndex];
            final sourceIndex = faceSources[faceIndex];
            object.mesh.faces[faceIndex] = MeshFace.copyOf(
              face,
              rvTextureIndex: 0,
              uv: [
                for (final uv in face.uv)
                  AtlasPacker.remapUv(
                    uv: uv,
                    source: sourceSizes[sourceIndex],
                    region: layout.regions[sourceIndex],
                    atlas: layout,
                  ),
              ],
            );
          }
          object
            ..texturePath = outputPath
            ..textureImage = atlasImage
            ..rvTextures = {0: atlasImage!}
            ..rvTexturePaths = {0: outputPath};
        }
        _isDirty = true;
      });
      atlasImage = null;
      _showMessage(
        'Created ${layout.width} × ${layout.height} atlas for '
        '${meshIndices.length} mesh(es) from ${sourceImages.length} texture(s).',
      );
    } catch (error) {
      atlasImage?.dispose();
      if (mounted) _showMessage('Could not generate texture atlas: $error');
    } finally {
      if (mounted) setState(() => _isGeneratingAtlas = false);
    }
  }

  void _smartUvRemap() {
    _recordUndo();
    final selected = _facesForUvMapping;
    final faceIndices = selected.isEmpty ? null : selected.toList();
    if (!_mesh.smartUvRemap(faceIndices)) {
      _undoHistory.removeLast();
      _showMessage('Add faces before creating a smart UV layout.');
      return;
    }
    setState(() => _isDirty = true);
    _showMessage(
      'Smart UV remap created non-overlapping face islands'
      '${faceIndices == null ? '.' : ' for ${faceIndices.length} selected face(s).'}',
    );
  }

  void _startUvBoxSelection() {
    setState(() {
      _selectedUvs.clear();
      _uvEditTool = _UvEditTool.boxSelect;
      _uvSelectionReadyToMove = false;
      _uvSelectionStart = null;
      _uvSelectionEnd = null;
    });
  }

  void _selectVisibleMeshes() {
    setState(() {
      _selectedMeshIndices
        ..clear()
        ..addAll([
          for (var index = 0; index < _objects.length; index++)
            if (_objects[index].visible) index,
        ]);
    });
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
              final menuRow = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dropMenu(
                    'File',
                    [
                      const PopupMenuItem(
                          value: 'new', child: Text('New Scene')),
                      const PopupMenuItem(value: 'open', child: Text('Open')),
                      const PopupMenuItem(
                          value: 'import', child: Text('Import…')),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'save',
                        child: Text(_isSaving ? 'Saving…' : 'Save'),
                      ),
                      const PopupMenuItem(
                        value: 'saveAs',
                        child: Text('Save As'),
                      ),
                      const PopupMenuItem(
                        value: 'export',
                        child: Text('Export'),
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
                        case 'import':
                          _importFile();
                        case 'save':
                          _saveScene();
                        case 'saveAs':
                          _saveScene(saveAs: true);
                        case 'export':
                          _exportModel();
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
                      PopupMenuItem(
                        value: 'duplicate',
                        child: Text('Duplicate selection  (Shift+D)'),
                      ),
                      PopupMenuItem(
                        value: 'deleteSelection',
                        child: Text('Delete selected elements  (Delete)'),
                      ),
                      PopupMenuItem(
                        value: 'joinMeshes',
                        child: Text('Join selected meshes  (Ctrl+J)'),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'mirror', child: Text('Mirror…')),
                      PopupMenuItem(
                        value: 'rotate',
                        child: Text('Rotate selection…  (R)'),
                      ),
                      PopupMenuItem(
                        value: 'uvProject',
                        child: Text('UV mapping…  (U)'),
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
                        case 'duplicate':
                          _duplicateSelection();
                        case 'deleteSelection':
                          _deleteSelection();
                        case 'joinMeshes':
                          _joinSelectedMeshes();
                        case 'mirror':
                          _mirrorActiveMesh();
                        case 'rotate':
                          _showRotateDialog();
                        case 'uvProject':
                          _openUvMappingOptions();
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
                      PopupMenuItem(
                        value: 'shading',
                        child: Text('Toggle flat / smooth shading'),
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
                        case 'shading':
                          _toggleShading();
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
                      PopupMenuItem(value: 'shape_cube', child: Text('Cube')),
                      PopupMenuItem(
                        value: 'shape_cylinder',
                        child: Text('Cylinder'),
                      ),
                      PopupMenuItem(
                        value: 'shape_circle',
                        child: Text('Circle'),
                      ),
                      PopupMenuItem(
                        value: 'shape_rectangle',
                        child: Text('Rectangle'),
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
                        case 'shape_cube':
                          _addPrimitive('Cube');
                        case 'shape_cylinder':
                          _addPrimitive('Cylinder');
                        case 'shape_circle':
                          _addPrimitive('Circle');
                        case 'shape_rectangle':
                          _addPrimitive('Rectangle');
                        case 'layout1':
                          _setViewportCount(1);
                        case 'layout2':
                          _setViewportCount(2);
                        case 'layout4':
                          _setViewportCount(4);
                      }
                    },
                  ),
                  _dropMenu(
                    'Help',
                    const [
                      PopupMenuItem(
                        value: 'features',
                        child: Text('Features'),
                      ),
                      PopupMenuItem(
                        value: 'shortcuts',
                        child: Text('Shortcut Keys'),
                      ),
                      PopupMenuItem(
                        value: 'about',
                        child: Text('About Blunder'),
                      ),
                    ],
                    (value) {
                      if (value == 'features') _showFeatures();
                      if (value == 'shortcuts') _showShortcutHelp();
                      if (value == 'about') _showAbout();
                    },
                  ),
                  const SizedBox(width: 4),
                  const SizedBox(width: 5),
                  Container(
                    height: 24,
                    width: 1,
                    color: const Color(0xFF48505E),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                  ),
                  _buildAxisButtons(),
                  Container(
                    height: 24,
                    width: 1,
                    color: const Color(0xFF48505E),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                  ),
                  _buildHistoryButtons(),
                  if (!wide &&
                      _objects.any(
                        (object) => object.rvCoordinateScale != null,
                      ))
                    _compactTool(
                      label: 'RV face flags',
                      icon: Icons.flag_outlined,
                      onPressed: _showRvPanelSheet,
                    ),
                  _compactTool(
                    label: _mesh.smoothShading
                        ? 'Switch to flat shading'
                        : 'Switch to smooth shading',
                    icon: _mesh.smoothShading
                        ? Icons.blur_on_rounded
                        : Icons.blur_off_rounded,
                    selected: _mesh.smoothShading,
                    onPressed: _toggleShading,
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
              return SizedBox(
                width: constraints.maxWidth,
                child: DecoratedBox(
                  key: const ValueKey('menuBarBorder'),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF48505E)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: menuRow,
                  ),
                ),
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
          Container(
            margin: const EdgeInsets.only(bottom: 3),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF48505E)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: MenuItemButton(
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                minimumSize: WidgetStatePropertyAll(Size(0, 30)),
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                ),
              ),
              onPressed: value == null
                  ? null
                  : () {
                      controller.close();
                      onSelected(value);
                    },
              child: DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 11),
                child: entry.child ?? const SizedBox.shrink(),
              ),
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
            padding: const EdgeInsets.symmetric(horizontal: 3),
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
            ],
          ),
        ),
      ),
    );
  }

  void _showShortcutHelp() {
    const shortcuts = <(String, String)>[
      (
        'A',
        'Select all visible meshes and vertices/faces in the active mode; '
            'press again to clear.'
      ),
      ('Ctrl+J', 'Join the selected visible meshes into one named mesh.'),
      ('B', 'Start box selection in the Model or UV editor.'),
      ('Delete / Backspace', 'Delete selected vertices or faces.'),
      ('M', 'Toggle constrained move on the selected X/Y/Z axis.'),
      (
        'R',
        'Enter a rotation angle around the selected axis; Enter applies it.'
      ),
      ('X / Y / Z', 'Select the axis for move, rotate, and duplicate.'),
      (
        'Shift+D',
        'Duplicate selected vertices/faces and move on the selected axis.'
      ),
      (
        'S',
        'Scale the active mesh uniformly; type a factor or drag, then Enter.'
      ),
      ('Enter / Esc', 'Confirm or cancel the active scale/UV transform.'),
      ('Ctrl+Z / Ctrl+Y', 'Undo / redo the last recorded action.'),
      ('Ctrl+N / Ctrl+O', 'Create a scene / open a project.'),
      ('Ctrl+S / Ctrl+Shift+S', 'Save / Save As.'),
      ('Ctrl+E', 'Export the scene as Wavefront OBJ.'),
      ('Numpad 1 / 3 / 7 / 9 / 5', 'Front / right / top / back / free view.'),
      ('Numpad 2 / 4 / 6 / 8', 'Orbit the active viewport.'),
      ('UV: B', 'Drag a rectangle to select UV corners.'),
      ('UV: S', 'Move the selected UV corners by dragging.'),
      ('UV: E, then X/Y', 'Stretch selected UVs along an axis.'),
      ('UV: M, then X/Y', 'Mirror selected UVs along an axis.'),
      ('UV: R', 'Rotate selected UVs by dragging or entering degrees.'),
      ('U', 'Open Project from view and Smart UV unwrap options.'),
      ('Hand tool', 'Drag to move a reference image or pan the grid.'),
    ];
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Shortcut Keys'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (keys, description) in shortcuts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 150,
                          child: Text(
                            keys,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF9FBEFF),
                            ),
                          ),
                        ),
                        Expanded(child: Text(description)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showFeatures() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Blunder Features'),
        content: const SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FeatureSection(
                  title: 'Create and edit meshes',
                  description:
                      'Start with a flat quad or add common primitives and '
                      'gridded surfaces. In Vertex mode add and select vertices, '
                      'then connect them into quads or triangles. In Face mode '
                      'select, delete, flip, and merge faces. Move, rotate, '
                      'scale, duplicate, join, hide, or rename meshes. Undo and '
                      'redo edits with Ctrl+Z and Ctrl+Y.',
                ),
                _FeatureSection(
                  title: 'Navigate the viewport',
                  description:
                      'Drag to orbit, use the mouse wheel or +/− controls to '
                      'zoom, and use the Hand tool or Ctrl/Shift plus wheel to '
                      'pan. Choose front, back, left, right, top, or bottom '
                      'views. Use two or four independent viewports and add '
                      'reference images when modeling from a blueprint.',
                ),
                _FeatureSection(
                  title: 'UV mapping and Atlas Creator',
                  description:
                      'Create UVs with Project from view or Smart UV unwrap, '
                      'then select, move, stretch, mirror, and rotate UV '
                      'corners in the UV editor. Atlas Creator combines the '
                      'textures used by selected meshes into one PNG, packs '
                      'each distinct source texture once, and remaps UVs. '
                      'Configure output shape, maximum size, island padding, '
                      'texture density, and auto-fit.',
                ),
                _FeatureSection(
                  title: 'Import and export',
                  description:
                      'Import OBJ, RV (*.prm), RV (*.w), and Blunder PKY/PKG '
                      'projects. Export OBJ, PRM, and W models, or save a PKY '
                      'project. OBJ material textures are loaded from their '
                      'MTL references when available. RV tools preserve and '
                      'edit face flags and texture assignments. In the RV '
                      'panel, select faces and toggle Invisible, Mirroring, '
                      'No EnvMap, Double-Sided, Add Blending, EnvMap, or '
                      'Translucent. Apply Flag can select faces with a flag, '
                      'apply the chosen flag to selected faces, or clear '
                      'their flags. Blunder supports up to 100,000 faces per '
                      'scene; missing textures can be assigned manually.',
                ),
                _FeatureSection(
                  title: 'Requirements',
                  description:
                      'The app is built with Flutter. To build from source, '
                      'install Flutter SDK (Dart 3.3 or later). Windows builds '
                      'require Visual Studio with Desktop development with C++ '
                      'and Windows Developer Mode. Android builds require '
                      'Android Studio and an Android SDK. To run on Android, '
                      'use a connected device or emulator.',
                ),
                _FeatureSection(
                  title: 'Getting started',
                  description:
                      'Choose File → Import to open a model, or use Add to '
                      'create geometry. Select meshes in the Scene panel; use '
                      'the UV layout page to map textures. Select the meshes '
                      'to combine before using Create Atlas. Help → Shortcut '
                      'Keys lists keyboard controls.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Blunder'),
        content: const SizedBox(
          width: 380,
          child: Text(
            'Blunder v$_appVersion\n\n'
            'A lightweight, beginner-friendly polygon modeler for building '
            'and editing 3D meshes with vertices, faces, and UV mapping.\n\n'
            'Includes UV mapping and the Atlas Creator for combining textures '
            'and remapping selected meshes.\n\n'
            'Created by -Prakhar Kumar Yadav.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactEditorTools() {
    final canMakeQuad = _mode == EditMode.vertex
        ? _selectedVertices.length == 4
        : _selectedFaces.length == 2;
    final canMakeTriangle =
        _mode == EditMode.vertex && _selectedVertices.length == 3;
    final canJoinVertices =
        _mode == EditMode.vertex && _selectedVertices.length == 2;
    final canFlipNormals = _mode == EditMode.face &&
        (_selectedFaces.isNotEmpty || _selectedFace != null);
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
        _buildTouchToolsMenu(),
        _compactTool(
          label: 'Move on ${_selectedAxis.name.toUpperCase()} (M)',
          icon: Icons.open_with_rounded,
          selected: _tool == ActiveTool.move,
          onPressed: _startMovingOnSelectedAxis,
        ),
        _compactTool(
          label: 'Join vertices',
          icon: Icons.merge_type_rounded,
          onPressed: canJoinVertices ? _joinSelectedVertices : null,
        ),
        _compactTool(
          label: 'Flip normals',
          icon: Icons.flip_rounded,
          onPressed: canFlipNormals ? _flipSelectedFaceNormals : null,
        ),
        if (_mode == EditMode.vertex)
          _compactTool(
            label: 'Make triangle',
            icon: Icons.change_history_outlined,
            onPressed: canMakeTriangle ? _createTriangle : null,
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
          label: 'Add flat face',
          icon: Icons.grid_4x4_rounded,
          selected: _tool == ActiveTool.addSurface,
          onPressed: () => setState(() {
            _tool = _tool == ActiveTool.addSurface
                ? ActiveTool.select
                : ActiveTool.addSurface;
            _surfaceSelectionStart = null;
            _surfaceSelectionEnd = null;
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
          onPressed: !canMakeQuad
              ? null
              : _mode == EditMode.face
                  ? _mergeSelectedTriangles
                  : _connectVertices,
        ),
      ],
    );
  }

  Widget _buildAxisButtons() => SegmentedButton<MeshAxis>(
        segments: const [
          ButtonSegment(value: MeshAxis.x, label: Text('X')),
          ButtonSegment(value: MeshAxis.y, label: Text('Y')),
          ButtonSegment(value: MeshAxis.z, label: Text('Z')),
        ],
        selected: {_selectedAxis},
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 5)),
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        onSelectionChanged: (selection) => _selectAxis(selection.single),
      );

  Widget _buildHistoryButtons() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Undo (Ctrl+Z)',
            onPressed: _undoHistory.isEmpty ? null : _undo,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.undo_rounded, size: 17),
          ),
          IconButton(
            tooltip: 'Redo (Ctrl+Y)',
            onPressed: _redoHistory.isEmpty ? null : _redo,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.redo_rounded, size: 17),
          ),
        ],
      );

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

  Widget _buildTouchToolsMenu() => MenuAnchor(
        menuChildren: [
          for (final (tool, label) in const [
            ('box', 'Box select (B)'),
            ('all', 'Select all / none (A)'),
            ('delete', 'Delete selected'),
            ('scale', 'Scale mesh'),
            ('hand', 'Hand pan tool'),
          ])
            _touchToolMenuItem(tool, label),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            height: 1,
            color: const Color(0xFF48505E),
          ),
          for (final (tool, label) in const [
            ('visible', 'Select visible meshes'),
            ('join', 'Join selected meshes'),
          ])
            _touchToolMenuItem(tool, label),
        ],
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(Color(0xFF171B23)),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
              side: const BorderSide(color: Color(0xFF48505E)),
            ),
          ),
        ),
        builder: (context, controller, child) => Tooltip(
          message: 'Selection and viewport tools',
          child: IconButton(
            onPressed: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.tune_rounded, size: 18),
          ),
        ),
      );

  Widget _touchToolMenuItem(String tool, String label) {
    return Container(
      key: ValueKey('touchMenuItem-$tool'),
      margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF48505E)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: MenuItemButton(
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          minimumSize: WidgetStatePropertyAll(Size(0, 30)),
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          ),
        ),
        onPressed: () => _handleTouchToolSelection(tool),
        child: SizedBox(
          width: 210,
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
      ),
    );
  }

  void _handleTouchToolSelection(String tool) {
    switch (tool) {
      case 'box':
        setState(() {
          _boxSelectActive = !_boxSelectActive;
          _boxSelectionStart = null;
          _boxSelectionEnd = null;
        });
      case 'all':
        _toggleSelectAll();
      case 'delete':
        _deleteSelection();
      case 'scale':
        _showScaleDialog();
      case 'hand':
        setState(() {
          _tool =
              _tool == ActiveTool.hand ? ActiveTool.select : ActiveTool.hand;
        });
      case 'visible':
        _selectVisibleMeshes();
      case 'join':
        _joinSelectedMeshes();
    }
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
    final hasRvMeshes =
        _objects.any((object) => object.rvCoordinateScale != null);
    return Row(
      children: [
        SizedBox(
          width: 220,
          child: Column(
            children: [
              if (hasRvMeshes) ...[
                Expanded(
                  flex: 5,
                  child: _isRvPanelVisible
                      ? _buildRvPanel()
                      : Align(
                          alignment: Alignment.topLeft,
                          child: IconButton(
                            tooltip: 'Show RV panel',
                            onPressed: () =>
                                setState(() => _isRvPanelVisible = true),
                            icon: const Icon(Icons.add),
                          ),
                        ),
                ),
                const SizedBox(height: 8),
              ],
              Expanded(
                flex: hasRvMeshes ? 4 : 1,
                child: _buildAtlasPanel(),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _page == EditorPage.model
              ? _buildViewportWorkspace()
              : _buildUvEditor(),
        ),
        const SizedBox(width: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          width: _isSidePanelVisible ? 220 : 36,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerRight,
              minWidth: 220,
              maxWidth: 220,
              child: _isSidePanelVisible
                  ? _buildSidePanel()
                  : SizedBox(
                      width: 220,
                      child: Align(
                        alignment: Alignment.centerRight,
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
      ],
    );
  }

  Widget _buildAtlasPanel() {
    if (!_isAtlasPanelVisible) {
      return Container(
        decoration: _panelDecoration(),
        alignment: Alignment.topLeft,
        child: IconButton(
          tooltip: 'Show Atlas Creator',
          onPressed: () => setState(() => _isAtlasPanelVisible = true),
          icon: const Icon(Icons.add),
        ),
      );
    }
    final selectedMeshes = _selectedVisibleMeshIndices.length;
    final selectedTextures = _selectedAtlasTextureCount;
    return Container(
      key: const ValueKey('atlasCreatorPanel'),
      decoration: _panelDecoration(),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ATLAS CREATOR',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.1,
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              IconButton(
                tooltip: 'Hide Atlas Creator panel',
                visualDensity: VisualDensity.compact,
                constraints:
                    const BoxConstraints.tightFor(width: 28, height: 28),
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _isAtlasPanelVisible = false),
                icon: const Icon(Icons.chevron_left, size: 19),
              ),
            ],
          ),
          const Divider(height: 16),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Text(
                  '$selectedMeshes mesh(es) · $selectedTextures texture(s)',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(height: 8),
                _atlasOption<int>(
                  label: 'Maximum size',
                  value: _atlasMaxSize,
                  options: [
                    for (final size in [512, 1024, 2048, 4096])
                      (size, '$size × $size'),
                  ],
                  onSelected: (size) => setState(() => _atlasMaxSize = size),
                ),
                const SizedBox(height: 8),
                _atlasOption<AtlasShape>(
                  label: 'Atlas shape',
                  value: _atlasShape,
                  options: const [
                    (AtlasShape.square, 'Square'),
                    (AtlasShape.landscape, 'Landscape'),
                    (AtlasShape.portrait, 'Portrait'),
                  ],
                  onSelected: (shape) => setState(() => _atlasShape = shape),
                ),
                const SizedBox(height: 8),
                _atlasOption<int>(
                  label: 'Island padding',
                  value: _atlasPadding,
                  options: [
                    for (final padding in [2, 4, 8, 16])
                      (padding, '$padding px'),
                  ],
                  onSelected: (padding) =>
                      setState(() => _atlasPadding = padding),
                ),
                const SizedBox(height: 8),
                _atlasOption<double>(
                  label: 'Texture density',
                  value: _atlasDensity,
                  options: const [
                    (0.5, '50%'),
                    (0.75, '75%'),
                    (1, '100%'),
                    (1.5, '150%'),
                    (2, '200%'),
                  ],
                  onSelected: (density) =>
                      setState(() => _atlasDensity = density),
                ),
                Material(
                  color: Colors.transparent,
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Auto-fit smallest size',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _atlasAutoFit,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _atlasAutoFit = value);
                      }
                    },
                  ),
                ),
                const Text(
                  'Selected meshes only. Source UV layout is preserved and '
                  'repacked into one PNG.',
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _isGeneratingAtlas ? null : _generateAtlas,
            icon: _isGeneratingAtlas
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.build_outlined, size: 16),
            label: Text(_isGeneratingAtlas ? 'Creating…' : 'Create Atlas'),
          ),
        ],
      ),
    );
  }

  Widget _atlasOption<T>({
    required String label,
    required T value,
    required List<(T, String)> options,
    required ValueChanged<T> onSelected,
  }) {
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Color(0xFF171B23)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
            side: const BorderSide(color: Color(0xFF48505E)),
          ),
        ),
      ),
      menuChildren: [
        for (final (option, title) in options)
          Container(
            margin: const EdgeInsets.only(bottom: 3),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF48505E)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: MenuItemButton(
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                minimumSize: WidgetStatePropertyAll(Size(0, 30)),
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                ),
              ),
              onPressed: () => onSelected(option),
              child: SizedBox(
                width: 184,
                child: Text(title, style: const TextStyle(fontSize: 11)),
              ),
            ),
          ),
      ],
      builder: (context, controller, child) {
        final selectedLabel =
            options.firstWhere((option) => option.$1 == value).$2;
        return Container(
          key: ValueKey('atlasOption-$label'),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF48505E)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 9,
                          ),
                        ),
                        Text(selectedLabel,
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRvPanel() {
    final selectedFaces = _selectedRvFaces;
    return Container(
      decoration: _panelDecoration(),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'RV',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Hide RV panel',
                visualDensity: VisualDensity.compact,
                constraints:
                    const BoxConstraints.tightFor(width: 28, height: 28),
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _isRvPanelVisible = false),
                icon: const Icon(Icons.chevron_left, size: 19),
              ),
            ],
          ),
          const Divider(height: 16),
          const Text(
            'ACTIVE FACE',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final (label, flag) in _rvFaceFlags)
                  _rvFlagButton(
                    label,
                    flag,
                    enabled: selectedFaces.isNotEmpty,
                  ),
                const Divider(height: 18),
                const Text(
                  'APPLY FLAG',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: _rvFlagToSelect,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final (label, flag) in _rvFaceFlags)
                      DropdownMenuItem(value: flag, child: Text(label)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _rvFlagToSelect = value);
                    }
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _selectRvFacesWithFlag,
                      child: const Text('Select'),
                    ),
                    TextButton(
                      onPressed: () => _applyRvFlag(_rvFlagToSelect),
                      child: const Text('Apply'),
                    ),
                    TextButton(
                      onPressed: () =>
                          _applyRvFlag(_rvFlagToSelect, clear: true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                if (_mesh.faces.isNotEmpty &&
                    _mesh.faces.any((face) => face.rvType != 0)) ...[
                  const Divider(height: 18),
                  Text(
                    '${_mesh.faces.where((face) => face.rvType != 0).length} faces with RV flags',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRvPanelSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF171B23),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _buildRvPanel(),
          ),
        ),
      ),
    );
  }

  void _showAtlasPanelSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF171B23),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.82,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _buildAtlasPanel(),
          ),
        ),
      ),
    );
  }

  void _showMobileMeshesSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF171B23),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: ListView(
            children: [
              const ListTile(
                title: Text('Select meshes'),
                subtitle:
                    Text('Tap meshes to add or remove them from selection.'),
              ),
              for (var index = 0; index < _objects.length; index++)
                CheckboxListTile(
                  dense: true,
                  title: Text(_objects[index].name),
                  subtitle: Text(
                    '${_objects[index].mesh.faces.length} faces',
                  ),
                  value: _selectedMeshIndices.contains(index),
                  onChanged: _objects[index].visible
                      ? (_) => _selectMesh(index, toggle: true)
                      : null,
                ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showAtlasPanelSheet();
                  },
                  child: const Text('Open Atlas Creator'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rvFlagButton(
    String label,
    int flag, {
    required bool enabled,
  }) {
    final active = enabled &&
        _selectedRvFaces
            .every((index) => (_mesh.faces[index].rvType & flag) != 0);
    final blendingReady = flag != rvFlagAddBlending ||
        _selectedRvFaces.every((index) {
          final type = _mesh.faces[index].rvType;
          const otherFlags = rvFlagInvisible |
              rvFlagMirror |
              rvFlagNoEnvMap |
              rvFlagDoubleSided |
              rvFlagEnvMap |
              rvFlagTranslucent;
          return type & (otherFlags | rvFlagAddBlending) != 0;
        });
    final isEnabled = enabled && blendingReady;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: OutlinedButton(
        onPressed: isEnabled ? () => _applyRvFlag(flag, clear: active) : null,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          side: BorderSide(
            color: active ? const Color(0xFF6CA8FF) : const Color(0xFF414B5A),
          ),
          backgroundColor:
              active ? const Color(0x332D6DB5) : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              active ? Icons.check_box : Icons.check_box_outline_blank,
              size: 16,
              color: active ? const Color(0xFF8FC2FF) : Colors.white54,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          ],
        ),
      ),
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
    if (_visibleViewportCount == 3) {
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
          Expanded(child: panes[2]),
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
      padding: const EdgeInsets.all(12),
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
                tooltip: 'Select all visible meshes',
                visualDensity: VisualDensity.compact,
                onPressed: _selectVisibleMeshes,
                icon: const Icon(Icons.select_all_rounded, size: 19),
              ),
              IconButton(
                tooltip: 'Join selected meshes',
                visualDensity: VisualDensity.compact,
                onPressed: _selectedMeshIndices.length < 2
                    ? null
                    : _joinSelectedMeshes,
                icon: const Icon(Icons.merge_type_rounded, size: 19),
              ),
              IconButton(
                tooltip: 'Hide scene panel',
                visualDensity: VisualDensity.compact,
                constraints:
                    const BoxConstraints.tightFor(width: 28, height: 28),
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _isSidePanelVisible = false),
                icon: const Icon(Icons.chevron_right, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _pageButton(EditorPage.model, Icons.view_in_ar_rounded, 'Scene'),
              const SizedBox(width: 8),
              _pageButton(EditorPage.uv, Icons.grid_on_rounded, 'UV layout'),
            ],
          ),
          if (_page == EditorPage.model) ...[
            const Divider(height: 20),
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
              child: Builder(
                builder: (context) {
                  final rows = <(String?, int?)>[];
                  final emittedGroups = <String>{};
                  for (var index = 0; index < _objects.length; index++) {
                    final groupName = _objects[index].groupName;
                    if (groupName == null) {
                      rows.add((null, index));
                    } else if (emittedGroups.add(groupName)) {
                      rows.add((groupName, null));
                      if (!_collapsedMeshGroups.contains(groupName)) {
                        for (var childIndex = 0;
                            childIndex < _objects.length;
                            childIndex++) {
                          if (_objects[childIndex].groupName == groupName) {
                            rows.add((groupName, childIndex));
                          }
                        }
                      }
                    }
                  }
                  return ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, rowIndex) {
                      final (groupName, meshIndex) = rows[rowIndex];
                      if (meshIndex == null) {
                        final collapsed =
                            _collapsedMeshGroups.contains(groupName);
                        final count = _objects
                            .where((object) => object.groupName == groupName)
                            .length;
                        return GestureDetector(
                          onSecondaryTapDown: (details) =>
                              _showGroupContextMenu(
                            groupName,
                            details.globalPosition,
                          ),
                          onLongPressStart: (details) => _showGroupContextMenu(
                            groupName,
                            details.globalPosition,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                collapsed
                                    ? Icons.chevron_right
                                    : Icons.expand_more,
                                size: 20,
                              ),
                              title: Text(groupName!),
                              subtitle: Text(
                                '$count imported ${count == 1 ? 'mesh' : 'meshes'}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              onTap: () => setState(() {
                                if (collapsed) {
                                  _collapsedMeshGroups.remove(groupName);
                                } else {
                                  _collapsedMeshGroups.add(groupName);
                                }
                              }),
                            ),
                          ),
                        );
                      }
                      final object = _objects[meshIndex];
                      final active = meshIndex == _activeObjectIndex;
                      final selected = _selectedMeshIndices.contains(meshIndex);
                      final objectVisible = object.visible;
                      final vertexCount = object.mesh.vertices.length;
                      final faceCount = object.mesh.faces.length;
                      return Padding(
                        padding: EdgeInsets.only(
                          left: groupName == null ? 0 : 18,
                        ),
                        child: GestureDetector(
                          onSecondaryTapDown: (details) => _showMeshContextMenu(
                            meshIndex,
                            details.globalPosition,
                          ),
                          onLongPressStart: (details) => _showMeshContextMenu(
                            meshIndex,
                            details.globalPosition,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            child: ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              selected: selected,
                              selectedTileColor: active
                                  ? const Color(0xFF283955)
                                  : const Color(0xFF222A37),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              title: Text(
                                '${object.name} · '
                                '$vertexCount ${vertexCount == 1 ? 'vertex' : 'vertices'} · '
                                '$faceCount ${faceCount == 1 ? 'face' : 'faces'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: IconButton(
                                tooltip: objectVisible
                                    ? 'Hide ${object.name}'
                                    : 'Show ${object.name}',
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(
                                  width: 30,
                                  height: 30,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () =>
                                    _toggleMeshVisibility(meshIndex),
                                icon: Icon(
                                  objectVisible
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 18,
                                  color: objectVisible
                                      ? Colors.white70
                                      : Colors.white38,
                                ),
                              ),
                              onTap: () => _selectMesh(
                                meshIndex,
                                toggle:
                                    HardwareKeyboard.instance.isControlPressed,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
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
            if (_referenceImages.containsKey(_activeViewportIndex)) ...[
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
                    'X / Y / Z: choose axis · M: constrained move\n'
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
    final selected = _page == page;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _page = page),
        borderRadius: BorderRadius.circular(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 46,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF2A3546)
                    : const Color(0xFF1D222B),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF4E8DFF)
                      : const Color(0xFF394252),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                icon,
                size: 19,
                color: selected ? const Color(0xFF9FBEFF) : Colors.white70,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected ? Colors.white : Colors.white60,
              ),
            ),
          ],
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
          return MouseRegion(
            cursor: _tool == ActiveTool.hand
                ? SystemMouseCursors.grab
                : _boxSelectActive || _tool == ActiveTool.addSurface
                    ? SystemMouseCursors.precise
                    : SystemMouseCursors.basic,
            child: Listener(
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
                  if (_tool == ActiveTool.addSurface &&
                      details.pointerCount == 1) {
                    setState(() {
                      _surfaceSelectionStart = details.localFocalPoint;
                      _surfaceSelectionEnd = details.localFocalPoint;
                    });
                  } else if (_boxSelectActive) {
                    _boxSelectionStart = details.localFocalPoint;
                    _boxSelectionEnd = details.localFocalPoint;
                  } else if (_scaleActive) {
                    _scaleStartPointer = details.localFocalPoint;
                  } else if (_tool == ActiveTool.move && _lockedAxis != null) {
                    _recordUndo();
                  }
                },
                onScaleUpdate: (details) {
                  if (_tool == ActiveTool.addSurface &&
                      details.pointerCount == 1 &&
                      _surfaceSelectionStart != null) {
                    setState(
                      () => _surfaceSelectionEnd = details.localFocalPoint,
                    );
                  } else if (_boxSelectActive) {
                    setState(() => _boxSelectionEnd = details.localFocalPoint);
                  } else if (_scaleActive) {
                    final start = _scaleStartPointer;
                    if (start != null) {
                      final factor = math.exp(
                        (details.localFocalPoint.dx - start.dx) / 100,
                      );
                      setState(() => _applyScaleFactor(factor));
                    }
                  } else if (details.pointerCount >= 2) {
                    setState(() {
                      viewport.pan += details.focalPoint - _gestureAnchor;
                      viewport.zoom = (_gestureZoomStart * details.scale)
                          .clamp(_minZoom, _maxZoom)
                          .toDouble();
                      _gestureAnchor = details.focalPoint;
                    });
                  } else if (_tool == ActiveTool.hand) {
                    setState(() {
                      if (_referenceImages.containsKey(viewportIndex)) {
                        viewport.referencePan += details.focalPointDelta;
                      } else {
                        viewport.pan += details.focalPointDelta;
                      }
                    });
                  } else if (_tool == ActiveTool.move && _lockedAxis != null) {
                    _moveSelectedAlongAxis(
                      details.focalPointDelta,
                      size,
                      viewport,
                    );
                  } else if (_tool != ActiveTool.addVertex &&
                      _tool != ActiveTool.addSurface &&
                      _tool != ActiveTool.strip &&
                      _tool != ActiveTool.move) {
                    setState(() {
                      viewport.preset = ViewPreset.free;
                      viewport.yaw += details.focalPointDelta.dx * 0.008;
                      viewport.pitch =
                          (viewport.pitch + details.focalPointDelta.dy * 0.008)
                              .clamp(-3.13, 3.13)
                              .toDouble();
                    });
                  }
                },
                onScaleEnd: (_) {
                  if (_surfaceSelectionStart != null) {
                    final start = _surfaceSelectionStart!;
                    final end = _surfaceSelectionEnd ?? start;
                    setState(() {
                      _surfaceSelectionStart = null;
                      _surfaceSelectionEnd = null;
                    });
                    _finishFlatSurfaceDrag(
                      Rect.fromPoints(start, end),
                      size,
                      viewport,
                    );
                  } else if (_boxSelectActive) {
                    final start = _boxSelectionStart;
                    final end = _boxSelectionEnd;
                    if (start != null && end != null) {
                      _selectModelBox(
                        Rect.fromPoints(start, end),
                        size,
                        viewport,
                      );
                    }
                    setState(() {
                      _boxSelectActive = false;
                      _boxSelectionStart = null;
                      _boxSelectionEnd = null;
                    });
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _ViewportPainter(
                        meshes: _objects.map((object) => object.mesh).toList(),
                        visibleMeshes: [
                          for (final object in _objects) object.visible,
                        ],
                        textures: _objects
                            .map((object) => object.textureImage)
                            .toList(),
                        rvTextures: [
                          for (final object in _objects) object.rvTextures,
                        ],
                        activeMeshIndex: _activeObjectIndex,
                        selectedVertices: _selectedVertices,
                        selectedFaces: _selectedFaces,
                        selectedFace: _selectedFace,
                        highlightedFaces: _rvHighlightedFaces,
                        project: (point) => _project(point, size, viewport),
                        basis: _viewBasis(viewport),
                        viewPreset: viewport.preset,
                        referenceImage: _referenceImages[viewportIndex],
                        referencePan: viewport.referencePan,
                        selectionRect: _surfaceSelectionStart != null &&
                                _surfaceSelectionEnd != null
                            ? Rect.fromPoints(
                                _surfaceSelectionStart!,
                                _surfaceSelectionEnd!,
                              )
                            : _boxSelectionStart == null ||
                                    _boxSelectionEnd == null
                                ? null
                                : Rect.fromPoints(
                                    _boxSelectionStart!,
                                    _boxSelectionEnd!,
                                  ),
                        referenceOpacity: _referenceOpacity,
                        viewStyle: _viewStyle,
                        fade:
                            ((viewport.zoom - _minZoom) / 0.18).clamp(0.0, 1.0),
                        showVertices: _mode == EditMode.vertex ||
                            _viewStyle == ViewStyle.wireframe,
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: _zoomControls(size, viewport, viewportIndex),
                    ),
                    if (_visibleViewportCount > 1)
                      Positioned(
                        left: 7,
                        bottom: 7,
                        child: IconButton(
                          tooltip: 'Close this viewport',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                              width: 28, height: 28),
                          padding: EdgeInsets.zero,
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xAA171B23),
                            foregroundColor: Colors.white70,
                          ),
                          onPressed: () => _closeViewport(viewportIndex),
                          icon: const Icon(Icons.close, size: 15),
                        ),
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
                    if (viewportIndex == 0)
                      Positioned(
                        key: const ValueKey('fpsCounter'),
                        right: 12,
                        top: 10,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xAA171B23),
                            border: Border.all(
                              color: const Color(0xFF48505E),
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: ValueListenableBuilder<int>(
                              valueListenable: _fpsValue,
                              builder: (context, fps, _) => Text(
                                '$fps FPS',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
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
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _smartUvRemap,
                  icon: const Icon(Icons.auto_fix_high, size: 17),
                  label: const Text('Smart UV remap'),
                ),
                OutlinedButton.icon(
                  onPressed: _openUvMappingOptions,
                  icon: const Icon(Icons.view_in_ar_rounded, size: 17),
                  label: const Text('Project from view'),
                ),
                OutlinedButton.icon(
                  onPressed: _startUvBoxSelection,
                  icon: const Icon(Icons.select_all_rounded, size: 17),
                  label: const Text('Box select'),
                ),
                OutlinedButton.icon(
                  onPressed: _selectedUvs.isEmpty ? null : _startUvRotation,
                  icon: const Icon(Icons.rotate_right_rounded, size: 17),
                  label: const Text('Rotate (R)'),
                ),
                if (_uvEditTool == _UvEditTool.rotate) ...[
                  SizedBox(
                    width: 100,
                    child: TextField(
                      key: const ValueKey('uvRotationDegrees'),
                      controller: _uvRotationController,
                      keyboardType:
                          const TextInputType.numberWithOptions(signed: true),
                      decoration: const InputDecoration(
                        labelText: 'Degrees',
                        suffixText: '°',
                        isDense: true,
                      ),
                      onChanged: _setUvRotationText,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Confirm UV rotation',
                    onPressed: _confirmUvRotation,
                    icon: const Icon(Icons.check_circle_outline_rounded),
                  ),
                  IconButton(
                    tooltip: 'Cancel UV rotation',
                    onPressed: _cancelUvEdit,
                    icon: const Icon(Icons.cancel_outlined),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: _toggleSelectAll,
                  icon: const Icon(Icons.done_all_rounded, size: 17),
                  label: const Text('Select all'),
                ),
                OutlinedButton.icon(
                  onPressed: _loadTexture,
                  icon: const Icon(Icons.texture_rounded, size: 17),
                  label: const Text('Add texture'),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                final faceIndex = _selectedFace;
                return MouseRegion(
                  cursor: _uvEditTool == _UvEditTool.boxSelect
                      ? SystemMouseCursors.precise
                      : SystemMouseCursors.basic,
                  child: GestureDetector(
                    key: const ValueKey('uvEditorCanvas'),
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) =>
                        _startUvGesture(details.localPosition, size),
                    onPanUpdate: (details) =>
                        _updateUvGesture(details.localPosition, size),
                    onPanEnd: (_) => _finishUvGesture(),
                    child: CustomPaint(
                      size: size,
                      painter: _UvPainter(
                        faces: _mesh.faces,
                        selectedFaceIndex: faceIndex,
                        selectedUvs: _selectedUvs,
                        selectionRect:
                            _uvSelectionStart == null || _uvSelectionEnd == null
                                ? null
                                : Rect.fromPoints(
                                    _uvSelectionStart!,
                                    _uvSelectionEnd!,
                                  ),
                        texture: _selectedFace != null &&
                                _selectedFace! >= 0 &&
                                _selectedFace! < _mesh.faces.length
                            ? _objects[_activeObjectIndex].rvTextures[_mesh
                                    .faces[_selectedFace!].rvTextureIndex] ??
                                _objects[_activeObjectIndex].textureImage
                            : _objects[_activeObjectIndex].textureImage,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
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
    final compact = MediaQuery.sizeOf(context).width < 460;
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
              compact: compact,
              onPressed: () => setState(() => _page = EditorPage.model),
            ),
            _BottomNavButton(
              label: 'UVs',
              icon: Icons.grid_on_rounded,
              selected: _page == EditorPage.uv,
              compact: compact,
              onPressed: () => setState(() => _page = EditorPage.uv),
            ),
            _BottomNavButton(
              label: 'Meshes',
              icon: Icons.view_list_rounded,
              selected: false,
              compact: compact,
              onPressed: _showMobileMeshesSheet,
            ),
            _BottomNavButton(
              label: 'Atlas',
              icon: Icons.auto_awesome,
              selected: false,
              compact: compact,
              onPressed: _showAtlasPanelSheet,
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
              'Drag: orbit · X/Y/Z then M: move · Shift+D: duplicate',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white38,
                  ),
            ),
        ],
      ),
    );
  }

  String _statusText() {
    if (_rotationAxis != null) {
      return 'Rotate ${_rotationAxis!.name.toUpperCase()}: '
          '${_rotationDegrees.isEmpty ? 'type degrees' : _rotationDegrees} · Enter';
    }
    if (_page == EditorPage.uv) {
      if (_uvEditTool == _UvEditTool.boxSelect) {
        return 'UV box select · drag a box around UV corners';
      }
      if (_uvEditTool == _UvEditTool.move) {
        return 'UV move · drag selected UVs · Enter confirms · Esc cancels';
      }
      if (_uvEditTool == _UvEditTool.awaitStretchAxis) {
        return 'UV stretch · press X or Y, then drag · Enter confirms';
      }
      if (_uvEditTool == _UvEditTool.stretch) {
        return 'UV stretch ${_uvTransformAxis == 0 ? 'X' : 'Y'} · '
            'drag to scale · Enter confirms · Esc cancels';
      }
      if (_uvEditTool == _UvEditTool.rotate) {
        return 'UV rotate ${_uvRotationDegrees.isEmpty ? 'by dragging or entering degrees' : '$_uvRotationDegrees°'}'
            ' · Enter confirms · Esc cancels';
      }
      if (_uvEditTool == _UvEditTool.awaitMirrorAxis) {
        return 'UV mirror · press X or Y · Esc cancels';
      }
      if (_uvEditTool == _UvEditTool.mirrorPending) {
        return 'UV mirrored on ${_uvTransformAxis == 0 ? 'X' : 'Y'} · '
            'Enter confirms · Esc cancels';
      }
      final textureHint = _objects[_activeObjectIndex].texturePath == null
          ? ' · choose a texture'
          : '';
      return _selectedFace == null
          ? '${_selectedUvs.length} UVs selected · '
              'B: box select · S: move · E: stretch · M: mirror$textureHint'
          : 'Face ${_selectedFace! + 1} · ${_selectedUvs.length} UVs · '
              'B: box select · S: move · E: stretch · M: mirror$textureHint';
    }
    if (_scaleActive) {
      return 'Scale ${_scaleFactorText.isEmpty ? 'by dragging or type a factor' : _scaleFactorText}'
          ' · Enter confirms · Esc cancels';
    }
    if (_boxSelectActive) return 'Box select · drag to select elements';
    if (_tool == ActiveTool.addVertex) {
      return 'Tap the surface to place a vertex';
    }
    if (_tool == ActiveTool.addSurface) {
      return 'Drag a region to add a flat face';
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

class _FeatureSection extends StatelessWidget {
  const _FeatureSection({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF9FBEFF),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(description),
        ],
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
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: label,
        onPressed: onPressed,
        icon: Icon(icon),
        color: selected ? const Color(0xFF94B9FF) : Colors.white60,
      );
    }
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

class _DepthSortedFaces {
  _DepthSortedFaces(
    List<MeshModel> meshes,
    List<bool> visibleMeshes,
    _ViewBasis basis,
  ) {
    var minimumDepth = double.infinity;
    var maximumDepth = double.negativeInfinity;
    var count = 0;
    for (var meshIndex = 0; meshIndex < meshes.length; meshIndex++) {
      if (!visibleMeshes[meshIndex]) continue;
      final mesh = meshes[meshIndex];
      count += mesh.faces.length;
      for (final vertex in mesh.vertices) {
        final position = vertex.position;
        final depth = position.x * basis.normal.x +
            position.y * basis.normal.y +
            position.z * basis.normal.z;
        minimumDepth = math.min(minimumDepth, depth);
        maximumDepth = math.max(maximumDepth, depth);
      }
    }

    meshIndices = Int32List(count);
    faceIndices = Int32List(count);
    nextIndices = Int32List(count);
    bucketHeads = Int32List(_bucketCount)..fillRange(0, _bucketCount, -1);
    var entryIndex = 0;
    final depthRange = maximumDepth - minimumDepth;
    for (var meshIndex = 0; meshIndex < meshes.length; meshIndex++) {
      if (!visibleMeshes[meshIndex]) continue;
      final mesh = meshes[meshIndex];
      for (var faceIndex = 0; faceIndex < mesh.faces.length; faceIndex++) {
        final vertices = mesh.faces[faceIndex].vertices;
        var depth = 0.0;
        for (final vertexIndex in vertices) {
          final position = mesh.vertices[vertexIndex].position;
          depth += position.x * basis.normal.x +
              position.y * basis.normal.y +
              position.z * basis.normal.z;
        }
        depth /= vertices.length;
        final bucket = depthRange <= 1e-12
            ? 0
            : ((depth - minimumDepth) / depthRange * _lastBucket)
                .toInt()
                .clamp(0, _lastBucket);
        meshIndices[entryIndex] = meshIndex;
        faceIndices[entryIndex] = faceIndex;
        nextIndices[entryIndex] = bucketHeads[bucket];
        bucketHeads[bucket] = entryIndex;
        entryIndex++;
      }
    }
  }

  static const int _bucketCount = 16384;
  static const int _lastBucket = _bucketCount - 1;

  late final Int32List meshIndices;
  late final Int32List faceIndices;
  late final Int32List nextIndices;
  late final Int32List bucketHeads;

  void forEach(void Function(int meshIndex, int faceIndex) action) {
    for (final head in bucketHeads) {
      var index = head;
      while (index >= 0) {
        action(meshIndices[index], faceIndices[index]);
        index = nextIndices[index];
      }
    }
  }
}

class _ViewportPainter extends CustomPainter {
  _ViewportPainter({
    required this.meshes,
    required this.visibleMeshes,
    required this.textures,
    required this.rvTextures,
    required this.activeMeshIndex,
    required this.selectedVertices,
    required this.selectedFaces,
    required this.selectedFace,
    required this.highlightedFaces,
    required this.project,
    required this.basis,
    required this.viewPreset,
    required this.referenceImage,
    required this.referencePan,
    required this.selectionRect,
    required this.referenceOpacity,
    required this.viewStyle,
    required this.fade,
    required this.showVertices,
  });

  final List<MeshModel> meshes;
  final List<bool> visibleMeshes;
  final List<ui.Image?> textures;
  final List<Map<int, ui.Image>> rvTextures;
  final int activeMeshIndex;
  final Set<int> selectedVertices;
  final Set<int> selectedFaces;
  final int? selectedFace;
  final Set<int> highlightedFaces;
  final Offset Function(Vec3 point) project;
  final _ViewBasis basis;
  final ViewPreset viewPreset;
  final ui.Image? referenceImage;
  final Offset referencePan;
  final Rect? selectionRect;
  final double referenceOpacity;
  final ViewStyle viewStyle;
  final double fade;
  final bool showVertices;

  Vec3 _faceNormal(MeshModel mesh, MeshFace face) {
    if (face.vertices.length < 3) return const Vec3(0, 0, 1);
    final a = mesh.vertices[face.vertices[0]].position;
    final b = mesh.vertices[face.vertices[1]].position;
    final c = mesh.vertices[face.vertices[2]].position;
    final x1 = b.x - a.x;
    final y1 = b.y - a.y;
    final z1 = b.z - a.z;
    final x2 = c.x - a.x;
    final y2 = c.y - a.y;
    final z2 = c.z - a.z;
    final x = y1 * z2 - z1 * y2;
    final y = z1 * x2 - x1 * z2;
    final z = x1 * y2 - y1 * x2;
    final length = math.sqrt(x * x + y * y + z * z);
    if (length < 1e-10) return const Vec3(0, 0, 1);
    return Vec3(x / length, y / length, z / length);
  }

  Vec3 _normalizedNormal(Vec3 normal) {
    final length = math
        .sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z);
    return length < 1e-10
        ? const Vec3(0, 0, 1)
        : Vec3(normal.x / length, normal.y / length, normal.z / length);
  }

  double _shade(Vec3 normal) {
    const light = Vec3(0.35, 0.55, 0.76);
    return (0.32 +
            math.max(
                  0,
                  normal.x * light.x + normal.y * light.y + normal.z * light.z,
                ) *
                0.68)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  Color _shadeColor(Color base, double amount) {
    final color = base.toARGB32();
    return Color.fromARGB(
      (color >> 24) & 0xFF,
      (((color >> 16) & 0xFF) * amount).round(),
      (((color >> 8) & 0xFF) * amount).round(),
      ((color & 0xFF) * amount).round(),
    );
  }

  void _drawSolidFaces(
    Canvas canvas,
    List<List<Offset>> projectedMeshes,
    _DepthSortedFaces faceOrder,
  ) {
    final faceNormals = <List<Vec3>>[
      for (var meshIndex = 0; meshIndex < meshes.length; meshIndex++)
        if (visibleMeshes[meshIndex])
          [
            for (final face in meshes[meshIndex].faces)
              _faceNormal(meshes[meshIndex], face),
          ]
        else
          const [],
    ];
    final vertexNormals = <List<Vec3>>[];
    for (var meshIndex = 0; meshIndex < meshes.length; meshIndex++) {
      final mesh = meshes[meshIndex];
      if (!visibleMeshes[meshIndex] || !mesh.smoothShading) {
        vertexNormals.add(const []);
        continue;
      }
      final normalSums = List<Vec3>.filled(
        mesh.vertices.length,
        const Vec3(0, 0, 0),
      );
      for (var faceIndex = 0; faceIndex < mesh.faces.length; faceIndex++) {
        final normal = faceNormals[meshIndex][faceIndex];
        for (final vertexIndex in mesh.faces[faceIndex].vertices) {
          final sum = normalSums[vertexIndex];
          normalSums[vertexIndex] = Vec3(
            sum.x + normal.x,
            sum.y + normal.y,
            sum.z + normal.z,
          );
        }
      }
      vertexNormals.add([
        for (final normal in normalSums) _normalizedNormal(normal),
      ]);
    }

    const maxBatchVertices = 65532;
    const maxBatchIndices = maxBatchVertices * 2;
    final positions = Float32List(maxBatchVertices * 2);
    final colors = Int32List(maxBatchVertices);
    final indices = Uint16List(maxBatchIndices);
    var vertexCount = 0;
    var indexCount = 0;

    void flush() {
      if (indexCount == 0) return;
      canvas.drawVertices(
        ui.Vertices.raw(
          ui.VertexMode.triangles,
          Float32List.sublistView(positions, 0, vertexCount * 2),
          colors: Int32List.sublistView(colors, 0, vertexCount),
          indices: Uint16List.sublistView(indices, 0, indexCount),
        ),
        BlendMode.srcOver,
        Paint(),
      );
      vertexCount = 0;
      indexCount = 0;
    }

    faceOrder.forEach((meshIndex, faceIndex) {
      final mesh = meshes[meshIndex];
      final face = mesh.faces[faceIndex];
      final corners = face.vertices;
      final triangleIndexCount = (corners.length - 2) * 3;
      if (vertexCount + corners.length > maxBatchVertices ||
          indexCount + triangleIndexCount > maxBatchIndices) {
        flush();
      }

      final highlighted =
          meshIndex == activeMeshIndex && highlightedFaces.contains(faceIndex);
      final selected = meshIndex == activeMeshIndex &&
          (selectedFaces.contains(faceIndex) ||
              (selectedFaces.isEmpty && faceIndex == selectedFace));
      final base = highlighted
          ? const Color(0xFF68C9EE).withValues(alpha: fade)
          : selected
              ? const Color(0xFFE68186).withValues(alpha: fade)
              : const Color(0xFF707985).withValues(alpha: fade);
      final firstVertex = vertexCount;
      for (var corner = 0; corner < corners.length; corner++) {
        final vertexIndex = corners[corner];
        final position = projectedMeshes[meshIndex][vertexIndex];
        final pointOffset = vertexCount * 2;
        positions[pointOffset] = position.dx;
        positions[pointOffset + 1] = position.dy;
        final normal = mesh.smoothShading
            ? vertexNormals[meshIndex][vertexIndex]
            : faceNormals[meshIndex][faceIndex];
        colors[vertexCount] = _shadeColor(base, _shade(normal)).toARGB32();
        vertexCount++;
      }
      for (var corner = 1; corner < corners.length - 1; corner++) {
        indices[indexCount++] = firstVertex;
        indices[indexCount++] = firstVertex + corner;
        indices[indexCount++] = firstVertex + corner + 1;
      }
    });
    flush();
  }

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
      final destination = referencePan & size;
      final fitted = applyBoxFit(
        BoxFit.contain,
        Size(source.width, source.height),
        size,
      );
      canvas
        ..save()
        ..clipRect(Offset.zero & size)
        ..drawImageRect(
          image,
          Alignment.center.inscribe(fitted.source, source),
          Alignment.center.inscribe(fitted.destination, destination),
          Paint()
            ..color = Colors.white.withValues(alpha: referenceOpacity)
            ..filterQuality = FilterQuality.medium,
        )
        ..restore();
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
    final projectedMeshes = [
      for (var meshIndex = 0; meshIndex < meshes.length; meshIndex++)
        if (visibleMeshes[meshIndex])
          meshes[meshIndex]
              .vertices
              .map((vertex) => project(vertex.position))
              .toList()
        else
          const <Offset>[],
    ];
    final faceOrder = _DepthSortedFaces(meshes, visibleMeshes, basis);
    if (viewStyle == ViewStyle.solid) {
      _drawSolidFaces(canvas, projectedMeshes, faceOrder);
    }

    ui.Image? batchTexture;
    final batchPositions = <Offset>[];
    final batchTextureCoordinates = <Offset>[];
    final batchColors = <Color>[];
    final textureTint = Colors.white.withValues(alpha: fade);

    void flushTexturedBatch() {
      final texture = batchTexture;
      if (texture == null || batchPositions.isEmpty) return;
      _drawTexturedBatch(
        canvas,
        texture,
        batchPositions,
        batchTextureCoordinates,
        batchColors,
      );
      batchPositions.clear();
      batchTextureCoordinates.clear();
      batchColors.clear();
    }

    faceOrder.forEach((meshIndex, faceIndex) {
      final face = meshes[meshIndex].faces[faceIndex];
      final active = meshIndex == activeMeshIndex;
      final highlighted = active && highlightedFaces.contains(faceIndex);
      final selected = active &&
          (selectedFaces.contains(faceIndex) ||
              (selectedFaces.isEmpty && faceIndex == selectedFace));
      if (viewStyle == ViewStyle.solid && !selected && !highlighted) return;
      final points = face.vertices
          .map((index) => projectedMeshes[meshIndex][index])
          .toList();
      if (viewStyle == ViewStyle.textured) {
        final texture =
            rvTextures[meshIndex][face.rvTextureIndex] ?? textures[meshIndex];
        if (texture != null && face.uv.length == points.length) {
          if (batchTexture != texture || selected || highlighted) {
            flushTexturedBatch();
            batchTexture = texture;
          }
          for (var corner = 1; corner < points.length - 1; corner++) {
            for (final cornerIndex in [0, corner, corner + 1]) {
              batchPositions.add(points[cornerIndex]);
              batchTextureCoordinates.add(
                Offset(
                  face.uv[cornerIndex].dx * texture.width,
                  (1 - face.uv[cornerIndex].dy) * texture.height,
                ),
              );
              batchColors.add(textureTint);
            }
          }
          if (selected || highlighted) {
            flushTexturedBatch();
            final path = Path()..addPolygon(points, true);
            canvas.drawPath(
              path,
              Paint()
                ..color = (highlighted
                        ? const Color(0x6675D9FA)
                        : const Color(0x66F06B73))
                    .withValues(alpha: fade),
            );
          }
          if (active && (selected || highlighted)) {
            flushTexturedBatch();
            canvas.drawPath(
              Path()..addPolygon(points, true),
              Paint()
                ..color = (highlighted
                        ? const Color(0xFF75D9FA)
                        : const Color(0xFFFF8B91))
                    .withValues(alpha: fade)
                ..strokeWidth = 2
                ..style = PaintingStyle.stroke,
            );
          }
        } else {
          flushTexturedBatch();
          batchTexture = null;
          final path = Path()..addPolygon(points, true);
          canvas.drawPath(
            path,
            Paint()..color = const Color(0xFF707985).withValues(alpha: fade),
          );
        }
      } else {
        final path = Path()..addPolygon(points, true);
        if (viewStyle == ViewStyle.wireframe) {
          canvas.drawPath(path, edgePaint);
        } else if (active && (selected || highlighted)) {
          canvas.drawPath(
            path,
            Paint()
              ..color = (highlighted
                      ? const Color(0xFF75D9FA)
                      : const Color(0xFFFF8B91))
                  .withValues(alpha: fade)
              ..strokeWidth = 2
              ..style = PaintingStyle.stroke,
          );
        }
      }
    });
    flushTexturedBatch();

    if (showVertices) {
      for (var meshIndex = 0; meshIndex < meshes.length; meshIndex++) {
        if (!visibleMeshes[meshIndex]) continue;
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
                      ? const Color(0xFFFF777F)
                      : const Color(0xFFE3E9F0))
                  .withValues(alpha: fade),
          );
        }
      }
    }

    if (!List.generate(meshes.length, (index) => index).any(
        (index) => visibleMeshes[index] && meshes[index].vertices.isNotEmpty)) {
      _drawText(
        canvas,
        'Add vertices or reset the active mesh to start',
        size.center(Offset.zero),
        Colors.white54,
        centered: true,
      );
    }
    _drawAxis(canvas);
    final selection = selectionRect;
    if (selection != null) {
      canvas.drawRect(
        selection,
        Paint()
          ..color = const Color(0x336CA8FF)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        selection,
        Paint()
          ..color = const Color(0xFF78B3FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _drawTexturedBatch(
    Canvas canvas,
    ui.Image image,
    List<Offset> positions,
    List<Offset> textureCoordinates,
    List<Color> colors,
  ) {
    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: textureCoordinates,
      colors: colors,
    );
    canvas.drawVertices(
      vertices,
      BlendMode.modulate,
      Paint()
        ..shader = ui.ImageShader(
          image,
          TileMode.clamp,
          TileMode.clamp,
          Float64List.fromList(const [
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
          ]),
        ),
    );
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
  const _UvPainter({
    required this.faces,
    required this.selectedFaceIndex,
    required this.selectedUvs,
    required this.selectionRect,
    required this.texture,
  });

  final List<MeshFace> faces;
  final int? selectedFaceIndex;
  final Set<(int, int)> selectedUvs;
  final Rect? selectionRect;
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

    if (faces.isEmpty) {
      _drawLabel(
        canvas,
        'Create or select a face to edit its UVs',
        size.center(Offset.zero),
      );
      return;
    }

    for (var faceIndex = 0; faceIndex < faces.length; faceIndex++) {
      final face = faces[faceIndex];
      final selected = faceIndex == selectedFaceIndex;
      final points = face.uv
          .map((uv) => origin + Offset(uv.dx, 1 - uv.dy) * scale)
          .toList();
      canvas.drawPath(
        Path()..addPolygon(points, true),
        Paint()
          ..color = selected ? const Color(0x55F06B73) : const Color(0x332E9CA6)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        Path()..addPolygon(points, true),
        Paint()
          ..color = selected ? const Color(0xFFFF8B91) : const Color(0xFF63B7C1)
          ..strokeWidth = selected ? 2 : 1
          ..style = PaintingStyle.stroke,
      );
      for (var corner = 0; corner < points.length; corner++) {
        final uvSelected = selectedUvs.contains((faceIndex, corner));
        if (!selected && !uvSelected) continue;
        final point = points[corner];
        canvas.drawCircle(
          point,
          uvSelected ? 9 : 6,
          Paint()
            ..color =
                uvSelected ? const Color(0xFFFF777F) : const Color(0xFFFFC45C),
        );
        canvas.drawCircle(
          point,
          uvSelected ? 9 : 6,
          Paint()
            ..color = const Color(0xFF101319)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke,
        );
      }
    }
    final box = selectionRect;
    if (box != null) {
      canvas.drawRect(
        box,
        Paint()
          ..color = const Color(0x553E9CFF)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        box,
        Paint()
          ..color = const Color(0xFF78B5FF)
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
