# Goats

Goats is a 2D arena prototype with bitmap terrain. Missiles carve holes, and falling dirt adds solid ground.

## Run locally

Open this project in Godot 4.7 and press F5 to run the arena. To run the same scene directly, open `goats/goatsgame.tscn` and press F6.

## Controls

- **A / D** to walk.
- **Left Shift** cycles the active goat through goat only (0), backpack (1), and launcher (2).
- **Enter** to charge a jump in mode 0 or 1, then release to jump.
- Goats keep their momentum in the air. A drop of 48 world pixels below the last grounded position causes a bounce, and controls return once the goat settles. Adjust the drop distance in the console with `set fall_control_loss_distance 48`.
- In mode 2, use **W / S** to aim and **Space** to charge a shot, then release to fire.
- The cursor starts visible. **Right-click** to capture the mouse so it pans the camera, and **right-click again** to release it. **Scroll wheel** zooms in either mode.
- With the cursor visible, **left-click** in open air to drop dirt or **left-drag** to pan. Dirt drops are disabled while paused.
- **F1** to pause or resume. Camera controls and mouse capture still work while paused.
- **F2** to reset the level, just like the console's `reset` command.
- **Backtick** to open the tuning console.

## Tuning console

- `vars` lists the current tuning values and level filename.
- `set <name> <value>` changes a tuning value.
- `load <filename>.png` loads a PNG from `levels/` and restarts the arena.
- `reset` reloads the current level.

## Project layout

- [`goats/`](goats/) contains the arena, goat controller, missile, dirt drop, and wind effects.
- [`sim/terrain.gd`](sim/terrain.gd) stores and queries the terrain collision mask. [`view/terrain_view.gd`](view/terrain_view.gd) keeps the terrain artwork in sync with it.
- `levels/`, `sprites/`, and `assets/` contain runtime assets. `.files/` holds source artwork and development files.
