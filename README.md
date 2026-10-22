# Blunder

**Version 1.02.1** — Windows-first polygon modeling MVP.

Blunder is a lightweight, beginner-friendly polygon modeler built with Flutter.
The same app is designed to run on Windows and Android.

## Requirements

- Flutter SDK (Dart 3.3 or later)
- Windows: Visual Studio with the **Desktop development with C++** workload
- Windows: enable **Developer Mode** so Flutter can create plugin symlinks
- Android: Android Studio and an Android SDK; a connected device or emulator for
  running the app

On Windows, enable Developer Mode in **Settings → System → For developers**
before running `flutter pub get` (Flutter also offers to open this page with
`start ms-settings:developers`).

## Set up platform runners

This starter repository contains the shared Flutter app source. Generate the
native Windows and Android runner projects once from the repository root:

```shell
flutter create --platforms=windows,android .
flutter pub get
```

## Run

```shell
flutter run -d windows
```

For Android, list available devices and run on a connected device or emulator:

```shell
flutter devices
flutter run -d <device-id>
```

Run the mesh model tests with:

```shell
flutter test
```

## Modeling basics

- Use the **Meshes** panel to add and switch between independent meshes. Each
  mesh starts with its own flat quad; adding a mesh leaves the others in the
  scene.
- **Reset active mesh** replaces only the selected mesh with a flat quad.
- In **Vertex** mode, tap the visible vertices to select them. Choose **Add
  vertex** once, then tap the viewport repeatedly to place vertices on the
  current view's plane. The tool stays active until you select another tool.
  Front and side views place vertices on vertical planes; Top places them on
  the horizontal plane.
- Select four vertices and choose **Make quad** to connect them into a face.
- Use **Strip** to place a pair of starting vertices and then add successive
  vertices; each new point creates a triangle connected to the last edge.
- In **Face** mode, click two adjacent triangles and choose **Triangles → quad**
  to merge them into one quad while preserving their UV positions.
- In **Face** mode, tap a face to select it; **Delete face** removes it.
- Choose **Front**, **Back**, **Left**, **Right**, **Top**, or **Bottom** to
  align the viewport; **Free** restores the orbiting view. Drag to orbit and
  pinch to zoom or use two fingers to pan.
- Select vertices or a face, press **M**, choose **X**, **Y**, or **Z**, then
  drag in the viewport to move the selection along that world axis. Use
  **Duplicate** or **Shift+D** before moving to make a separate copy.
- Choose a view from the **View** menu or each viewport's eye menu. Select an
  orthographic view and choose **Add → Reference image** to load a blueprint
  for that view. Adjust its opacity or remove it from the scene panel.
- Use the mouse wheel or the **+ / -** viewport controls to zoom within the
  supported range; use **Fit** to frame the scene. Models fade as you zoom far
  out.
- Choose **Add → Scene: 2 views** or **4 views** to edit with independent
  cameras. Use the eye menu in each viewport to choose its view; edits to the
  shared mesh appear in every viewport.
- Hold **Left Ctrl** while scrolling to pan the active viewport horizontally;
  hold **Left Shift** while scrolling to pan it vertically.
- Collapse the scene panel with its left-chevron button; reopen it with the
  plus button at the left edge of the workspace.
- Choose **Mesh → Mirror** to reflect the active mesh across a selected axis.
  Select vertices or faces and press **R**, then **X/Y/Z**, type an angle, and
  press **Enter** to rotate around that axis. If nothing is selected, rotation
  applies to the active mesh.
- Open **UVs**, select a face, and drag a UV corner to adjust its mapping.
  Choose a texture image from the UV toolbar to preview the UVs over it.
- Switch between **Solid**, **Textured**, and **Wireframe** from the **Scene**
  menu. Texture preview displays an assigned image when available; otherwise
  the mesh remains gray.
- Use **File → New**, **Open**, **Save**, and **Export**, or the keyboard
  shortcuts **Ctrl+N**, **Ctrl+O**, **Ctrl+S**, **Ctrl+Shift+S**, and **Ctrl+E**.
  Blunder opens and saves `.pky` files (OBJ-compatible geometry with Blunder
  texture metadata) and exports `.obj` files. Textured exports include an MTL
  file and a copy of the referenced texture beside the OBJ.
- On Windows, the app registers `.pky` files to use the Blunder executable icon
  and open in Blunder when launched from File Explorer.

Windows view shortcuts: **Numpad 1** Front, **Numpad 3** Right, **Numpad 7**
Top, and **Numpad 9** Back. **Numpad 2 / 4 / 6 / 8** orbit in 15-degree steps;
**Numpad 5** returns to the free view. The number-row 1, 3, 5, 7, and 9 keys
also select the corresponding views. Press **R**, then **X/Y/Z**, enter a
rotation angle, and press **Enter** to rotate the selection or active mesh.

The app is implemented in Flutter/Dart, which keeps the desktop and Android
targets on one shared codebase. Python would add a separate runtime and would
not simplify the existing Flutter UI or platform packaging.
