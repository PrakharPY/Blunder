# Blunder

**Version 1.0.0** — Windows-first polygon modeling MVP.

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
  vertex**, then tap the viewport to place a new vertex on the current view's
  plane. Front and side views place vertices on vertical planes; Top places
  them on the horizontal plane.
- Select four vertices and choose **Make quad** to connect them into a face.
- In **Face** mode, tap a face to select it; **Delete face** removes it.
- Choose **Front**, **Back**, **Left**, **Right**, **Top**, or **Bottom** to
  align the viewport; **Free** restores the orbiting view. Drag to orbit and
  pinch to zoom or use two fingers to pan.
- Select vertices or a face, press **M**, choose **X**, **Y**, or **Z**, then
  drag in the viewport to move the selection along that world axis. Use
  **Duplicate** or **Shift+D** before moving to make a separate copy.
- Select an orthographic view and choose **Reference image** to load a
  blueprint for that view. Adjust its opacity or remove it from the scene panel.
- Open **UVs** to view the selected face's UV tile and drag a corner to adjust
  its mapping.

Windows view shortcuts: **Numpad 1** Front, **Numpad 3** Right, **Numpad 7**
Top, and **Numpad 9** Back. **Numpad 2 / 4 / 6 / 8** orbit in 15-degree steps;
**Numpad 5** returns to the free view. The number-row 1, 3, 5, 7, and 9 keys
also select the corresponding views.

The MVP edits an in-memory mesh and does not yet save or export model files.
