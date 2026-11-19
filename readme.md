```markdown
# Blackout

**A Minetest/Luanti mod by ronrob-lu (2026)**

A special control block that toggles all mese lamps in the world on or off simultaneously.

## Features

- **Global Control**: One block controls every mese lamp in the entire world
- **Toggle Functionality**: Right-click to switch between ON (normal light emission) and OFF (light level 0)
- **Visual Feedback**: The switch block changes appearance to indicate current state
- **Instant Effect**: All mese lamps respond immediately when toggled

## Installation

1. Download or clone this repository into your Minetest mods directory:
   ```
   ~/.minetest/mods/blackout/
   ```

2. Ensure the mod is enabled in your `world.mt` file or through the Minetest game menu

3. Restart Minetest

## Usage

### Crafting Recipe

The Blackout Switch can be crafted using:
```
[Steel Ingot] [Mese Crystal] [Steel Ingot]
[Mese Crystal] [Lever]      [Mese Crystal]
[Steel Ingot] [Mese Crystal] [Steel Ingot]
```

### Operating the Switch

1. Place the Blackout Switch block anywhere in the world
2. **Right-click** the block to toggle all mese lamps:
   - **First click**: Turns OFF all mese lamps (light emission = 0)
   - **Second click**: Turns ON all mese lamps (normal light emission)
3. The switch block will visually indicate its current state

## Technical Details

- The mod scans for all nodes with the name `default:mese_lamp` or similar mese lamp variants
- When toggled OFF, mese lamps retain their node type but emit no light (param2 modified)
- When toggled ON, mese lamps restore their original light emission values
- The switch maintains its state across server restarts using metadata

## Compatibility

- Tested with Minetest 5.x and Luanti
- Compatible with default mese lamps and most mese lamp variants
- Works in singleplayer and multiplayer environments

## Configuration

No configuration required. The mod works out of the box.

## Known Limitations

- Only affects standard mese lamps; custom lamp nodes from other mods may not be included
- Large worlds with thousands of mese lamps may experience brief lag during toggle operation
- The switch affects ALL mese lamps globally, regardless of distance or ownership

## License

MIT License - See LICENSE file for details

## Credits

**Author**: ronrob-lu  
**Year**: 2026  
Created for the Minetest/Luanti community.
```
