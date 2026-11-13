# Blunder

**Version 1.2** — Windows and Android polygon modeling build.

Blunder is a lightweight, beginner-friendly polygon modeler built with Flutter for low-poly 3D asset creation.

## Modeling basics

- Use the **Meshes** panel to add and switch between independent meshes. Each
  mesh starts with its own flat quad; adding a mesh leaves the others in the
  scene.
- Right-click a mesh in the panel (or long-press it on touch devices) to rename
  it, create an independent copy, or delete it. Imported OBJ parts appear
  beneath a collapsible group named after the OBJ file. Right-click or
  long-press a group to rename, duplicate, or delete all its meshes together.
- Meshes are visible by default. Use each row's eye button to hide or show that
  mesh. Click a row to activate it; Ctrl-click rows to select multiple meshes,
  or press **A** to select all visible meshes. Press **Ctrl+J** to join the
  selected visible meshes and give the result a name.
- **Reset active mesh** replaces only the selected mesh with a flat quad.
- In **Vertex** mode, tap the visible vertices to select them. Choose **Add
  vertex** once, then tap the viewport repeatedly to place vertices on the
  current view's plane. The tool stays active until you select another tool.
  Front and side views place vertices on vertical planes; Top places them on
  the horizontal plane.
- Select four vertices and choose **Make quad** to connect them into a face.
- Select three vertices and choose **Make triangle** to create a triangular
  face.
- Select two vertices and choose **Join vertices** to merge them at their
  midpoint; faces collapsed below three corners are removed. In Face mode,
  select one or more faces and choose **Flip normals** to reverse their
  winding while keeping their UVs aligned.
- Choose **Add flat surface**, drag a rectangle in the viewport, then enter an
  object name and horizontal/vertical face counts. Blunder creates a separate
  gridded surface in the active view plane; each direction supports 1–64 faces.
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
- Select **X**, **Y**, or **Z** in the top toolbar, then press **M** or click
  Move and drag to constrain movement to that world axis. **Shift+D** or
  **Mesh → Duplicate selection** makes a copy that can be moved on the selected
  axis. **R** enters a rotation angle around the selected axis; press **Enter**
  to apply it.
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
- Use the **Atlas Creator** panel to combine textures from
  selected visible meshes into one PNG atlas and remap their UVs. Choose a
  maximum size and optional island padding; identical sources are packed only
  once, and auto-fit selects the smallest suitable square output. If sources
  need resizing to fit the selected maximum, Blunder asks before continuing.
  Hide and restore its panel with the collapse and plus buttons. On touch
  devices, open **Atlas** from the bottom toolbar.
- Press **U** or choose **Mesh → UV mapping** for **Project from view** or
  **Smart UV unwrap**. Mapping operates on selected faces and leaves other
  faces' UVs unchanged; with no faces selected it maps the full mesh. In the UV
  editor press **R** and drag horizontally to rotate selected UV corners, or
  enter a degree value and press **Enter**. Touch users can use the visible
  Rotate, degrees, confirm, and cancel controls.
- Choose **Add → Cube / Cylinder / Circle / Rectangle** to create common
  starting shapes. Select **Hand tool** and drag to move a reference image, or
  pan the grid when no reference image is loaded.
- Toggle the **Flat / Smooth shading** toolbar button to change the active
  mesh's viewport lighting; the setting is saved in PKY scene files. The
  viewport uses indexed solid-face batches and depth buckets to reduce per-frame
  sorting and temporary geometry data on larger meshes.
- Blunder enforces a **100,000 face per scene limit** for imported scenes and
  model edits. OBJ parsing runs off the UI isolate; oversized OBJ/PKY scenes
  are rejected with an explicit limit message.
- **File → Import** also accepts **RV (*.prm)** and **RV (*.w)** files. RV
  imports preserve per-face flags, texture indices, UVs, colors, coordinate
  transforms, and world texture-animation records. Binary mesh decoding runs
  off the UI isolate, and the textured viewport batches triangles by texture to
  keep larger imports responsive. Blunder searches beside the source file for
  matching BMP textures; missing textures can be assigned manually with
  **Add texture** in the UV editor.
- RV models and worlds can be exported through **File → Export** by choosing
  `.prm` or `.w`. The RV panel shows and edits flags on the active face, and its
  **Apply Flag** controls can select matching faces, apply a flag, or clear it.
  Selected matches are highlighted light blue. On narrow screens, open these
  controls with the **RV face flags** toolbar button.
- PRM import reads the first LOD mesh; export writes one LOD. W export rebuilds
  bounds and a single big-cube index group from the current scene. PKY projects
  retain RV flags and coordinate metadata, along with paths to loaded RV
  textures.
- Android includes touch buttons for box/select-all, delete, scale, hand pan,
  UV box selection/rotation, and mesh selection/joining alongside the desktop
  menus and gestures.
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
targets on one shared codebase.

Use **Help → Features** for an overview of modeling tools and platform
requirements, **Help → Shortcut Keys** for the complete shortcut reference.
