# Blackout

**A Minetest / Luanti mod by ronrob-lu (2026)**

A special control block that toggles all mese lamps in the world on or off simultaneously.

## Features

- **Global Control**: One switch block controls every mese lamp in the world.
- **Toggle Functionality**: Right-click to switch all lamps between **ON** (full illumination) and **OFF** (light level 0).
- **Visual Feedback**: The switch block changes appearance and emits light (level 6) when turned ON, darkening when turned OFF.
- **Instant Effect**: All mese lamps in active/loaded mapblocks respond immediately via node swapping (`swap_node`).
- **Dynamic Chunk Loading (LBMs)**: Any mapblock loaded after a toggle automatically updates to the current global blackout state.
- **State Persistence**: The global state persists across server restarts via Mod Storage and switch node metadata.

## Installation

1. Download or clone this repository into your Minetest/Luanti mods directory:
   - **Linux / BSD**: `~/.minetest/mods/blackout/`
   - **macOS**: `~/Library/Application Support/minetest/mods/blackout/`
   - **Windows**: `%APPDATA%\minetest\mods\blackout\`
2. Ensure the mod is enabled in your world via the Minetest/Luanti main menu or in `world.mt`:
   ```
   load_mod_blackout = true
   ```
3. Launch your world.

## Usage

### Crafting Recipe

The Blackout Switch can be crafted using:

| | | |
| :---: | :---: | :---: |
| Steel Ingot | Mese Crystal | Steel Ingot |
| Mese Crystal | Lever* | Mese Crystal |
| Steel Ingot | Mese Crystal | Steel Ingot |

*\*If a lever mod (such as `mesecons_walllever`) or `default:lever` is not installed, standard `default:meselamp` is automatically accepted as the center item.*

### Operating the Switch

1. Place the **Blackout Switch** anywhere in the world.
2. **Right-click** the block to toggle all mese lamps:
   - **OFF state**: Turns off all mese lamps (light emission = 0).
   - **ON state**: Restores normal illumination to all mese lamps.
3. The switch emits a mechanical click sound and updates its appearance and infotext.
4. Multiple switches placed in the world stay synchronized.

## Technical Details

- **Supported Nodes**: Automatically discovers and handles `default:meselamp`, `default:mese_lamp`, mese post light variants (`default:mese_post_light*`), and compatible mod variants.
- **Light Emulation**: Because engine node light values cannot be varied per position at runtime, the mod registers unlit twin nodes (`blackout:<nodename>_off` with `light_source = 0`) and swaps them in place using `minetest.swap_node`, preserving node orientation, metadata, and drops.
- **Chunk Management**: Uses Loading Block Modifiers (`minetest.register_lbm`) with `run_at_every_load = true` to update nodes in unloaded chunks the moment a player travels near them.
- **Persistence**: Global blackout status is saved via `minetest.get_mod_storage()`, ensuring server restarts resume in the exact state last toggled.

## Compatibility

- Tested with **Minetest 5.x** and **Luanti**.
- Compatible with Minetest Game `default` mese lamps and post lights, as well as `moreblocks` and `mesecons` lamps.
- Works in both singleplayer and multiplayer.

## License

MIT License - See the [LICENSE](LICENSE) file for details.

## Credits

- **Author**: ronrob-lu
- **Year**: 2026
- Created for the Minetest / Luanti community.
