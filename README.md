# Goats

Goats is a 2D arena prototype with bitmap terrain. Missiles carve holes, and falling dirt adds solid ground.

## Run locally

Open this project in Godot 4.7 and press F5 to run the arena. To run the same scene directly, open `goats/goatsgame.tscn` and press F6.

## Controls

To rebind a control or add another key, mouse button, or controller input for the same action, open **Project > Project Settings > Input Map** in Godot. The console's text editing and submission use Godot's built-in UI actions.

- **A / D** to walk.
- **Tab** selects the next goat and centers the camera on it.
- **Left Shift** switches the active goat between Goat Only and Launcher.
- Hold **Enter** to charge a jump in Goat Only mode. Release to jump.
- Hold **Space** to charge a shot in Launcher mode. Release to fire.
- Goats keep their momentum in the air. By default, a drop of 64 world pixels below the last grounded position disables controls until the goat settles. A hard landing can cause a bounce. Use `set fall_control_loss_distance <pixels>` to change the threshold.
- When a goat walks off an edge, it holds its current frame for the first 24 world pixels of the drop. Adjust the threshold in the console with `set fall_animation_distance 24`.
- In Launcher mode, use **W / S** to aim while idle.
- The cursor starts visible. **Right-click** to capture the mouse so it pans the camera, and **right-click again** to release it. **Scroll** through 0.5×, 1×, 2×, and 3× zoom around the visible cursor. With the mouse captured, zooming uses the center of the view.
- With the cursor visible, **left-click** in open air to drop dirt or **left-drag** to pan. Dirt drops are disabled while paused.
- **F1** to pause or resume. Camera controls and mouse capture still work while paused.
- **F2** to reset the level, just like the console's `reset` command.
- **Backtick** to open the tuning console.

## Tuning console

- `vars` lists the current tuning values and level filename.
- `set <name> <value>` changes a tuning value.
- `set leaf_count <count>` sets the total number of leaves across all three layers. Use a whole number from 0 to 300. The default is 30.
- `load <filename>.png` loads a PNG from `levels/` and restarts the arena.
- `reset` reloads the current level.

## Project layout

- [`goats/`](goats/) contains the arena, goat controller, missile, dirt drop, and wind effects.
- [`sim/terrain.gd`](sim/terrain.gd) stores and queries the terrain collision mask. [`view/terrain_view.gd`](view/terrain_view.gd) keeps the terrain artwork in sync with it.
- `levels/`, `sprites/`, and `assets/` contain runtime assets. `.files/` holds source artwork and development files.
