# Goats

Open this project in Godot 4.7 and press F5 to run the arena. To run the same scene directly, open `goats/goatsgame.tscn` and press F6.

- **A / D** to walk.
- **Enter** to charge a jump, then release to jump.
- Goats keep their momentum in the air. A drop of 48 world pixels below the last grounded position causes a bounce, and controls return once the goat settles. Adjust the drop distance in the console with `set fall_control_loss_distance 48`.
- **Space** to charge a shot, then release to fire.
- The cursor starts visible. **Right-click** to capture the mouse so it pans the camera, and **right-click again** to release it. **Scroll wheel** zooms in either mode.
- **F1** to pause or resume. Camera controls and mouse capture still work while paused.
- **F2** to reset the level, just like the console's `reset` command.
- **Backtick** to open the tuning console.

The arena, goat controller, rocket, and wind effects live in `goats/`. The terrain collision mask is in `sim/terrain.gd`, and `view/terrain_view.gd` renders the destructible level. Source artwork and development files are in `.files/`.
