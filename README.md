# Goats

Open this project in Godot 4.7 and press F5 to run the arena. To run the same scene directly, open `goats/goats.tscn` and press F6.

- **A / D** to walk.
- **Enter** to charge a jump, then release to jump.
- **Space** to charge a shot, then release to fire.
- **Mouse** to pan, **scroll wheel** to zoom, and **right-click** to toggle mouse capture.
- **F1** to pause or resume. Camera controls and mouse capture still work while paused.
- **Backtick** to open the tuning console.

The arena, goat controller, rocket, and wind effects live in `goats/`. The terrain collision mask is in `sim/terrain.gd`, and `view/terrain_view.gd` renders the destructible level. Source artwork and development files are in `.files/`.
