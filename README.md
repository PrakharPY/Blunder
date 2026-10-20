# Blunder

Blunder is a lightweight, beginner-friendly polygon modeler built with Flutter.
The same app is designed to run on Windows and Android.

## Requirements

- Flutter SDK (Dart 3.3 or later)
- Windows: Visual Studio with the **Desktop development with C++** workload
- Android: Android Studio and an Android SDK; a connected device or emulator for
  running the app

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

- **New flat surface** resets the scene to one editable quad.
- In **Vertex** mode, tap the visible vertices to select them. Choose **Add
  vertex**, then tap the viewport to place a new vertex on the modeling plane.
- Select four vertices and choose **Make quad** to connect them into a face.
- In **Face** mode, tap a face to select it; **Delete face** removes it.
- Drag in the viewport to orbit. Pinch to zoom or use two fingers to pan.
- Open **UVs** to view the selected face's UV tile and drag a corner to adjust
  its mapping.

The MVP edits an in-memory mesh and does not yet save or export model files.
