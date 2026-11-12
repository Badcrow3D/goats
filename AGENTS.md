# Working on Goats

Use Godot 4.7 with the GL Compatibility renderer configured in `project.godot`. The main scene is `goats/goatsgame.tscn`. See [README.md](README.md) for controls and tuning commands.

## Where changes belong

- `goats/goatsgame.gd` wires the arena together. It owns level loading, camera and console input, bitmap movement and collision, and the arena's response to missile impacts and dirt deposits.
- `goats/goat_controller.gd` provides movement, jump, fall recovery, and equipment control. The arena extends it and supplies bitmap movement and grounding. `goats/goat.gd` holds the goat's state and visual layers.
- `goats/missile.gd` handles missile flight and impact detection. `goats/dirt_drop.gd` handles falling, settling, and depositing dirt. It emits `deposited` after updating terrain so the arena can lift goats out of newly solid pixels.
- `sim/terrain.gd` owns the solidity mask. `view/terrain_view.gd` keeps the image and texture in sync with changes to the mask. For carving, update the mask before calling `TerrainView.carve`. For dirt, `TerrainView.deposit` updates the mask and artwork together.
- Terrain checks use terrain-local pixel coordinates. Convert screen input through the terrain view's canvas transform so clicks still land correctly after panning, zooming, or scaling the terrain.

## Verify changes

- Keep Godot-generated `.gd.uid` sidecars with their scripts. Keep the generated `.godot/` cache out of commits.
- For a fresh checkout, open the project in Godot or run `godot --headless --path . --editor --import` to import assets and resolve scene UIDs.
- From the project root, run `godot --headless --path . --quit-after 10` for a startup smoke test. Use your Godot executable path if `godot` is unavailable on `PATH`. Check the output for script and scene errors.
- Play the affected behavior in the arena. For terrain edits, fire a missile into the ground and drop dirt over open terrain and near a goat. Check that the artwork matches collision and that a goat overlapping a new deposit moves clear of the ground.
