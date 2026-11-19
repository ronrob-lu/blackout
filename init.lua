--[[
Blackout - A Minetest/Luanti mod by ronrob-lu (2026)

A special control block that toggles all mese lamps in the world on or off
simultaneously.

Features:
  * Global Control   - one block controls every mese lamp in the world
  * Toggle           - right-click switches all lamps between ON and OFF
  * Visual Feedback  - the switch block changes appearance with its state
  * Instant Effect   - lamps respond immediately (swap_node, no re-place)
  * Persistence      - state survives server restarts via mod storage & metadata

License: MIT
--]]

blackout = {}

local MODNAME = minetest.get_current_modname() or "blackout"
local storage = minetest.get_mod_storage()

-- ---------------------------------------------------------------------------
-- State persistence & switch tracking
-- ---------------------------------------------------------------------------

--- Recover the blackout state ("on" or "off"). Defaults to "on".
function blackout.load_state()
	local s = storage:get_string("state")
	if s == "off" or s == "on" then
		return s
	end
	return "on"
end

blackout.state = blackout.load_state()

--- Persist the current state into mod storage and optional switch node metadata.
function blackout.save_state(pos)
	storage:set_string("state", blackout.state)
	if pos then
		local meta = minetest.get_meta(pos)
		meta:set_string("blackout_state", blackout.state)
	end
end

local function get_tracked_switches()
	local raw = storage:get_string("switches")
	if raw == "" then return {} end
	return minetest.deserialize(raw) or {}
end

local function track_switch(pos)
	local list = get_tracked_switches()
	local key = minetest.pos_to_string(pos)
	list[key] = {x = pos.x, y = pos.y, z = pos.z}
	storage:set_string("switches", minetest.serialize(list))
end

local function untrack_switch(pos)
	local list = get_tracked_switches()
	local key = minetest.pos_to_string(pos)
	if list[key] then
		list[key] = nil
		storage:set_string("switches", minetest.serialize(list))
	end
end

-- ---------------------------------------------------------------------------
-- Mese-lamp detection & registration of unlit twins
-- ---------------------------------------------------------------------------

local function looks_like_mese_lamp(name)
	if name:find("^blackout:") or name:find("_off$") then
		return false
	end
	if name == "default:meselamp" or name == "default:mese_lamp" then
		return true
	end
	local item = name:match(":(.+)$")
	if not item then
		return false
	end
	return item == "meselamp"
		or item:find("mese_lamp") ~= nil
		or item:find("lamp_mese") ~= nil
		or item:find("mese_post_light") ~= nil
end

blackout.off_variant     = {} -- lit name -> unlit twin name
blackout.lit_of_off      = {} -- unlit twin name -> original lit name
blackout.lamp_names      = {} -- original lit lamp names
blackout.all_lamp_names  = {} -- lit and unlit lamp names
blackout.all_target_names = {} -- lamp names + switch names for quick queries

--- Register an unlit twin for one lamp node (light_source = 0).
function blackout.register_off_variant(name)
	if blackout.off_variant[name] then return false end
	local def = minetest.registered_nodes[name]
	if not def or (def.light_source or 0) <= 0 then
		return false
	end

	local safe_name = name:gsub(":", "_")
	local off_name = "blackout:" .. safe_name .. "_off"
	if not minetest.registered_nodes[off_name] then
		local offdef = table.copy(def)
		offdef.light_source = 0
		offdef.description = (def.description or name) .. " (powered off)"
		offdef.groups = table.copy(def.groups or {})
		offdef.groups.blackout_lamp_off = 1
		offdef.groups.not_in_creative_inventory = 1
		offdef.drop = name -- always drop the original lamp

		-- Apply darkening overlay to unlit tiles so they visually look unlit
		if type(offdef.tiles) == "table" then
			local new_tiles = {}
			for i, tile in ipairs(offdef.tiles) do
				if type(tile) == "string" then
					new_tiles[i] = tile .. "^[colorize:#000000:120"
				elseif type(tile) == "table" and type(tile.name) == "string" then
					local t = table.copy(tile)
					t.name = t.name .. "^[colorize:#000000:120"
					new_tiles[i] = t
				else
					new_tiles[i] = tile
				end
			end
			offdef.tiles = new_tiles
		end

		minetest.register_node(off_name, offdef)
		pcall(minetest.register_alias, name .. "_blackout_off", off_name)
	end

	blackout.off_variant[name] = off_name
	blackout.lit_of_off[off_name] = name
	return true
end

local function init_lamp_registry()
	local names = {}
	for name in pairs(minetest.registered_nodes) do
		if looks_like_mese_lamp(name) then
			names[#names + 1] = name
		end
	end
	table.sort(names)

	for _, name in ipairs(names) do
		blackout.register_off_variant(name)
	end

	blackout.lamp_names = {}
	blackout.all_lamp_names = {}
	blackout.all_target_names = {
		"blackout:switch",
		"blackout:switch_off_visual",
	}

	for lit_name, off_name in pairs(blackout.off_variant) do
		blackout.lamp_names[#blackout.lamp_names + 1] = lit_name
		blackout.all_lamp_names[#blackout.all_lamp_names + 1] = lit_name
		blackout.all_lamp_names[#blackout.all_lamp_names + 1] = off_name
		blackout.all_target_names[#blackout.all_target_names + 1] = lit_name
		blackout.all_target_names[#blackout.all_target_names + 1] = off_name
	end

	if #blackout.lamp_names == 0 then
		minetest.log("warning", "[" .. MODNAME .. "] No mese lamp nodes found; " ..
			"the Blackout Switch will have no lamps to control.")
	else
		minetest.log("action", "[" .. MODNAME .. "] Registered " ..
			#blackout.lamp_names .. " mese lamp variants.")
	end
end

init_lamp_registry()

-- ---------------------------------------------------------------------------
-- Lamp state application
-- ---------------------------------------------------------------------------

--- Swap one lamp to its lit/unlit form (instant, preserves param2 & meta).
function blackout.set_lamp_state(pos, state)
	local node = minetest.get_node(pos)
	local name = node.name

	local target
	if state == "off" then
		target = blackout.off_variant[name]
	else
		target = blackout.lit_of_off[name]
	end

	if target and target ~= name then
		node.name = target
		minetest.swap_node(pos, node)
		return true
	end
	return false
end

--- Apply a global state ("on"/"off") to lamps in currently loaded blocks.
function blackout.apply_state(state)
	blackout.state = state
	local count = 0
	local visited_blocks = {}

	local function scan_mapblock(bx, by, bz)
		local key = bx .. "," .. by .. "," .. bz
		if visited_blocks[key] then return end
		visited_blocks[key] = true

		local minp = {x = bx * 16, y = by * 16, z = bz * 16}
		local maxp = {x = bx * 16 + 15, y = by * 16 + 15, z = bz * 16 + 15}

		local positions = minetest.find_nodes_in_area(minp, maxp, blackout.all_target_names)
		for _, npos in ipairs(positions) do
			local node = minetest.get_node(npos)
			if node.name == "blackout:switch" or node.name == "blackout:switch_off_visual" then
				local want = (state == "off") and "blackout:switch_off_visual" or "blackout:switch"
				if node.name ~= want then
					node.name = want
					minetest.swap_node(npos, node)
				end
			elseif blackout.set_lamp_state(npos, state) then
				count = count + 1
			end
		end
	end

	-- Try engine mapblock query if supported
	local get_blocks = minetest.get_loaded_blocks or (core and core.get_loaded_blocks)
		or minetest.get_active_blocks or (core and core.get_active_blocks)
	local blocks = nil
	if type(get_blocks) == "function" then
		pcall(function() blocks = get_blocks() end)
	end

	if blocks and #blocks > 0 then
		for _, bpos in ipairs(blocks) do
			scan_mapblock(bpos.x, bpos.y, bpos.z)
		end
	else
		-- Proximity fallback: scan active blocks around all connected players
		local players = minetest.get_connected_players()
		for _, p in ipairs(players) do
			local ppos = p:get_pos()
			if ppos then
				local cx = math.floor(ppos.x / 16)
				local cy = math.floor(ppos.y / 16)
				local cz = math.floor(ppos.z / 16)
				for dx = -5, 5 do
					for dy = -3, 3 do
						for dz = -5, 5 do
							scan_mapblock(cx + dx, cy + dy, cz + dz)
						end
					end
				end
			end
		end
	end

	minetest.log("action", "[" .. MODNAME .. "] Applied state '" .. state ..
		"' to " .. count .. " lamps in loaded mapblocks")
	return count
end

-- ---------------------------------------------------------------------------
-- The Blackout Switch node
-- ---------------------------------------------------------------------------

local function switch_on_rightclick(pos, node, clicker, itemstack, pointed_thing)
	blackout.toggle(pos, clicker)
	return itemstack
end

local function make_switch_def(on)
	local d = {
		description = "Blackout Switch",
		inventory_image = "blackout_switch_inv_" .. (on and "on" or "off") .. ".png",
		wield_image = "blackout_switch_top_" .. (on and "on" or "off") .. ".png",
		drawtype = "nodebox",
		tiles = {
			"blackout_switch_top_" .. (on and "on" or "off") .. ".png",
			"blackout_switch_bottom.png",
			"blackout_switch_side.png",
		},
		node_box = {
			type = "fixed",
			fixed = {-0.4, -0.5, -0.4, 0.4, -0.1, 0.4},
		},
		selection_box = {
			type = "fixed",
			fixed = {-0.4, -0.5, -0.4, 0.4, -0.1, 0.4},
		},
		paramtype = "light",
		paramtype2 = "facedir",
		light_source = on and 6 or 0,
		sunlight_propagates = true,
		groups = {cracky = 2, oddly_breakable_by_hand = 2},
		sounds = default and default.node_sound_stone_defaults and default.node_sound_stone_defaults(),
		drop = "blackout:switch",
		on_rightclick = switch_on_rightclick,
		after_place_node = function(pos, placer, itemstack, pointed_thing)
			track_switch(pos)
			local want_name = (blackout.state == "off") and "blackout:switch_off_visual" or "blackout:switch"
			local current = minetest.get_node(pos)
			if current.name ~= want_name then
				current.name = want_name
				minetest.swap_node(pos, current)
			end
			local meta = minetest.get_meta(pos)
			meta:set_string("blackout_state", blackout.state)
			meta:set_string("infotext", "Blackout Switch (" .. (blackout.state == "off" and "OFF" or "ON") .. ")")
		end,
		after_dig_node = function(pos, oldnode, oldmetadata, digger)
			untrack_switch(pos)
		end,
	}
	if not on then
		d.groups.not_in_creative_inventory = 1
	end
	return d
end

minetest.register_node("blackout:switch", make_switch_def(true))
minetest.register_node("blackout:switch_off_visual", make_switch_def(false))

-- ---------------------------------------------------------------------------
-- Toggling
-- ---------------------------------------------------------------------------

--- Swap all known placed switches to match the current state.
function blackout.update_switch_appearance()
	local target_name = (blackout.state == "off") and "blackout:switch_off_visual" or "blackout:switch"
	local list = get_tracked_switches()
	for key, spos in pairs(list) do
		local node = minetest.get_node_or_nil(spos)
		if node then
			if node.name == "blackout:switch" or node.name == "blackout:switch_off_visual" then
				if node.name ~= target_name then
					node.name = target_name
					minetest.swap_node(spos, node)
				end
				local meta = minetest.get_meta(spos)
				meta:set_string("blackout_state", blackout.state)
				meta:set_string("infotext", "Blackout Switch (" .. (blackout.state == "off" and "OFF" or "ON") .. ")")
			else
				untrack_switch(spos)
			end
		end
	end
end

--- Flip the global lamp state.
function blackout.toggle(pos, player)
	local new_state = (blackout.state == "off") and "on" or "off"
	blackout.state = new_state
	blackout.save_state(pos)

	if pos then
		minetest.sound_play("default_place_node_metal", {
			pos = pos,
			gain = 1.0,
			max_hear_distance = 16,
		}, true)
	end

	blackout.update_switch_appearance()
	blackout.apply_state(new_state)

	local msg = (new_state == "off")
		and "Blackout: all mese lamps are now OFF."
		or  "Blackout: all mese lamps are now ON."
	if player and player.is_player and player:is_player() then
		minetest.chat_send_player(player:get_player_name(), msg)
	end
	minetest.log("action", "[" .. MODNAME .. "] Toggled -> " .. new_state)
end

-- ---------------------------------------------------------------------------
-- LBMs (Loading Block Modifiers) & Dynamic Event Hooks
-- ---------------------------------------------------------------------------

-- Automatically apply current state to lamps when mapblocks load
if #blackout.all_lamp_names > 0 then
	minetest.register_lbm({
		name = "blackout:update_lamps",
		nodenames = blackout.all_lamp_names,
		run_at_every_load = true,
		action = function(pos, node)
			blackout.set_lamp_state(pos, blackout.state)
		end,
	})
end

-- Automatically apply visual appearance to switches when mapblocks load
minetest.register_lbm({
	name = "blackout:update_switches",
	nodenames = {"blackout:switch", "blackout:switch_off_visual"},
	run_at_every_load = true,
	action = function(pos, node)
		track_switch(pos)
		local want = (blackout.state == "off") and "blackout:switch_off_visual" or "blackout:switch"
		if node.name ~= want then
			node.name = want
			minetest.swap_node(pos, node)
		end
		local meta = minetest.get_meta(pos)
		meta:set_string("blackout_state", blackout.state)
		meta:set_string("infotext", "Blackout Switch (" .. (blackout.state == "off" and "OFF" or "ON") .. ")")
	end,
})

-- Handle newly placed lamps or switches while blackout is off
minetest.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing)
	if blackout.state == "off" and blackout.off_variant[newnode.name] then
		local off_name = blackout.off_variant[newnode.name]
		newnode.name = off_name
		minetest.swap_node(pos, newnode)
	end
end)

-- ---------------------------------------------------------------------------
-- Crafting recipe
-- ---------------------------------------------------------------------------

local lever = "default:meselamp"
if minetest.registered_items["mesecons_walllever:lever_off"] then
	lever = "mesecons_walllever:lever_off"
elseif minetest.registered_items["default:lever"] then
	lever = "default:lever"
end

minetest.register_craft({
	output = "blackout:switch",
	recipe = {
		{"default:steel_ingot", "default:mese_crystal", "default:steel_ingot"},
		{"default:mese_crystal", lever,                  "default:mese_crystal"},
		{"default:steel_ingot", "default:mese_crystal", "default:steel_ingot"},
	},
})

-- ---------------------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------------------

minetest.register_on_mods_loaded(function()
	minetest.log("action", "[" .. MODNAME .. "] Ready. Current state: " .. blackout.state)
end)
