# Goats

Goats is a 2D arena prototype with bitmap terrain. Missiles carve holes, and falling dirt adds solid ground.

## Run locally

Open this project in Godot 4.7 and press F5 to run the arena. To run the same scene directly, open `goats/goatsgame.tscn` and press F6.

## Controls

To rebind a control or add another key, mouse button, or controller input for the same action, open **Project > Project Settings > Input Map** in Godot. The console's text editing and submission use Godot's built-in UI actions.

- **A / D** to walk.
- **Tab** selects the next goat and centers the camera on it.
- **Z** cycles inactive goats’ nameplates from 2× (default) to 1×, then hidden, then back to 2×.
- **Shift** switches the active goat to Goat Only mode.
- **Q** cycles through Goat Only → Grapple → Missile → Grenade → Rockets → Cannon → Laser → Goat Only.
- **1** selects Missile, **2** Grenade, **3** Rockets, **4** Cannon, and **5** Laser.
- **E** selects Grapple mode. Aim with **W / S** and press **Space** to fire the grapple. Hold **W** to reel in and pull the goat toward the anchor. While airborne, hold **S** to lengthen the rope and use **A / D** to build swing momentum. Press **Space** again to release.
- Tap **Enter** while grounded with the grapple connected to bounce into a swing. Each goat can bounce once every two seconds.
- Hold **Enter** to charge a jump in Goat Only mode. Release to jump.
- Hold **Space** to charge a shot in Missile or Grenade mode. Release to fire. Grenades bounce and explode four seconds after launch.
- In Rockets mode, aim with **W / S** and press **Space** to immediately fire three rockets, 250 ms apart. Each rocket flies straight at half the speed of a fully charged missile, at a random angle 3° to 6° to either side of your aim, and explodes on impact or after one second. Walking and aiming resume after the third launch.
- In Cannon mode, aim with **W / S** and press **Space** to immediately fire one shot within 3° of your aim. It cuts through up to 35 pixels of solid terrain and deals 25 damage to the first goat or item it hits.
- In Laser mode, aim with **W / S** and press **Space** to fire immediately. The beam reaches up to 150 terrain pixels and cuts a 16-pixel circle after 250 ms on the same spot. It lasts up to two seconds if it touches terrain, or one second in open air.
- Goats keep their momentum in the air. By default, a drop of 64 world pixels below the last grounded position disables controls until the goat settles. A hard landing can cause a bounce. Use `set fall_control_loss_distance <pixels>` to change the threshold.
- When a goat walks off an edge, it holds its current frame for the first 24 world pixels of the drop. Adjust the threshold in the console with `set fall_animation_distance 24`.
- In Missile or Grenade mode, use **W / S** to aim while idle.
- The cursor starts visible. **Right-click** to capture the mouse so it pans the camera, and **right-click again** to release it. **Scroll** through 0.5×, 1×, 2×, and 3× zoom around the visible cursor. With the mouse captured, zooming uses the center of the view.
- With the cursor visible, **left-click** in open air to drop dirt or **left-drag** to pan. Dirt drops are disabled while paused.
- **F1** to pause or resume. Camera controls and mouse capture still work while paused.
- **F2** to reset the level, just like the console's `reset` command.
- **Backtick** to open the tuning console.

## Tuning console

- `vars` lists the current tuning values and level filename.
- `set <name> <value>` changes a tuning value.
- `set leaf_count <count>` sets the total number of leaves across all three layers. Use a whole number from 0 to 300. The default is 30.
- `load <filename>.png` loads a 1920×1080 level PNG from `levels/` and restarts the arena.
- `reset` reloads the current level.

### Test teams

- `team create [name]` creates a team and prints its numeric ID. Omit the name to use a default such as `Team 1`.
- `team name <id> <name>` renames a team, for example `team name 1 Hill Climbers`.
- `team add <id> <goat name>` adds a goat name, for example `team add 1 Billy Blue`. Each team can hold up to 12 goat names.
- `team list` shows team IDs, names, and rosters.

The console loads all test teams into memory and saves every successful change to `user://teams.cfg`. These commands manage test roster data independently of the goats in the arena.

On first launch, the console creates `Team1` and `Team2` if `teams.cfg` is missing. Each team has `Goat1` through `Goat12`.

`newmatch level2 team1 4 team2 6` starts a fresh arena on `levels/level2.png`. Provide two or more distinct teams by case-insensitive name or numeric ID from `team list`. Use IDs for names containing spaces. Follow each team with its goat count, a whole number from 1 to 12. Each team uses its saved goat names in order. Empty slots get temporary names such as `Goat1` and `Goat2`, skipping names already in use on that team. Each team draws a color from the shuffled `colors.cfg` palette. Colors repeat only if there are more teams than palette entries. The goats start at randomly assigned, separate spots on the terrain.

Each successful `newmatch` saves the level, teams, and per-team goat counts to `user://rematch.cfg`. Run `rematch` to start a fresh match with the saved level, teams, and goat counts, with new random spawn positions and team colors. During a match, `reset` restores its starting positions and terrain.

The active goat starts in goat-only mode. The camera holds at 2× on that goat for one second, then zooms out to 1× before returning control to the player.

## Project layout

- [`goats/`](goats/) contains the arena, goat controller, missile, dirt drop, and wind effects.
- [`sim/terrain.gd`](sim/terrain.gd) stores and queries the terrain collision mask. [`view/terrain_view.gd`](view/terrain_view.gd) keeps the terrain artwork in sync with it.
- `levels/`, `sprites/`, and `assets/` contain runtime assets. `.files/` holds source artwork and development files.
