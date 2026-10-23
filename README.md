# Blunder

**Version 1.04** — Windows-first polygon modeling MVP.

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
- Right-click a mesh in the panel (or long-press it on touch devices) to rename
  it, create an independent copy, or delete it. Imported OBJ parts appear
  beneath a collapsible group named after the OBJ file.
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
- Click or tap additional vertices/faces to multi-select them. Selected elements
  are highlighted light red; move and rotate operations affect the full
  selection.
- Choose **Front**, **Back**, **Left**, **Right**, **Top**, or **Bottom** to
  align the viewport; **Free** restores the orbiting view. Drag to orbit and
  pinch to zoom or use two fingers to pan.
- Select vertices or a face, press **M**, choose **X**, **Y**, or **Z**, then
  drag in the viewport to move the selection along that world axis. Use
  **Duplicate** or **Shift+D** before moving to make a separate copy.
- Choose a view from the **View** menu or each viewport's eye menu. Activate a
  viewport and choose **Add → Reference image** to load a blueprint for that
  quadrant. Each quadrant keeps its own reference image; adjust its opacity or
  remove it from the scene panel.
- Use the mouse wheel or the **+ / -** viewport controls to zoom within the
  supported range; use **Fit** to frame the scene. Models fade as you zoom far
  out.
- Choose **Add → Scene: 2 views** or **4 views** to edit with independent
  cameras. Use the eye menu in each viewport to choose its view; edits to the
  shared mesh appear in every viewport. Click the small **×** in a viewport's
  lower-left corner to close that pane; the final pane cannot be closed.
- Press **A** to select all vertices or faces in the current edit mode, and
  press **A** again to clear the selection. Drag a box with **B** in Model or
  UV view to select elements or UV corners. In Model view, **Delete** or
  **Backspace** removes the selected vertices or faces; deleting a vertex also
  removes faces that use it.
- Press **S** in Model view and drag horizontally to scale the active mesh
  uniformly, or type a positive factor such as `1.25` or `0.75`; the change is
  previewed immediately. Press **Enter** to accept or **Esc** to cancel.
- Undo and redo with **Ctrl+Z** and **Ctrl+Y** (or the toolbar arrow buttons).
  Modeling, mesh, UV, scaling, and viewport-close actions are recorded in a
  bounded history.
- Hold **Left Ctrl** while scrolling to pan the active viewport horizontally;
  hold **Left Shift** while scrolling to pan it vertically.
- Collapse the scene panel with its left-chevron button; reopen it with the
  plus button at the left edge of the workspace.
- Choose **Mesh → Mirror** to reflect the active mesh across a selected axis.
  Select vertices or faces and press **R**, then **X/Y/Z**, type an angle, and
  press **Enter** to rotate around that axis. If nothing is selected, rotation
  applies to the active mesh.
- Open **UVs** and choose **Smart UV remap** to project each face and pack its
  UV island into a separate tile in the 0–1 texture space. Select a face in
  Model view to drag its UV corners manually. Use **Add texture** in the UV
  toolbar to assign a texture to the active mesh; it remains linked to that
  mesh and is used in Textured view. In the UV editor, press **B** and drag a
  box to select UV corners across the active mesh; press **S**, drag, then
  **Enter** to move the selection. Press **E**, then **X** or **Y**, and drag
  to stretch along that UV axis; **M**, then **X** or **Y**, mirrors the
  selection. **Enter** confirms UV transforms and **Esc** cancels a transform.
- Switch between **Solid**, **Textured**, and **Wireframe** from the **Scene**
  menu. Texture preview displays an assigned image when available; otherwise
  the mesh remains gray.
- Use **File → New**, **Open**, **Save**, and **Export**, or the keyboard
  shortcuts **Ctrl+N**, **Ctrl+O**, **Ctrl+S**, **Ctrl+Shift+S**, and **Ctrl+E**.
  Blunder opens `.pky` and `.pkg` scene files and saves `.pky` files
  (OBJ-compatible geometry with Blunder texture metadata), imports `.obj`
  files, and exports Wavefront `.obj` files. OBJ import
  reads material assignments and diffuse `map_Kd` textures from the companion
  MTL file. Each object/material part becomes a selectable mesh under the
  imported file's group; polygon faces larger than quads are triangulated.
  Textured exports include an MTL file and a copy of the referenced texture
  beside the OBJ.
- On Windows, the app registers `.pky` files to use the Blunder executable icon
  and open in Blunder when launched from File Explorer.

Windows view shortcuts: **Numpad 1** Front, **Numpad 3** Right, **Numpad 7**
Top, and **Numpad 9** Back. **Numpad 2 / 4 / 6 / 8** orbit in 15-degree steps;
**Numpad 5** returns to the free view. The number-row 1, 3, 5, 7, and 9 keys
also select the corresponding views. Press **R**, then **X/Y/Z**, enter a
rotation angle, and press **Enter** to rotate the selection or active mesh.
Free view can orbit over and underneath the model.

The app is implemented in Flutter/Dart, which keeps the desktop and Android
targets on one shared codebase. Python would add a separate runtime and would
not simplify the existing Flutter UI or platform packaging.
