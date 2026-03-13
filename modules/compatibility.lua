local utils = require("modules.utils")

local compatibility = {}

local AAI_LOADERS_MOD = "aai-loaders"

local AAI_LOADER_PREFIX = "aai-"
local AAI_PIPE_Y_OFFSET = 1 / 32
local MAX_PENDING_RESTORE_ATTEMPTS = 600
local MAX_PENDING_RESTORES_PER_TICK = 16


local function is_aai_loader_name(name)
	local powered_name = utils.strip_unpowered_prefix(name)
	return utils.startswith(powered_name, AAI_LOADER_PREFIX)
end

local function copy_position(position)
	return {x = position.x, y = position.y}
end

local function get_pipe_position(loader_position)
	return {x = loader_position.x, y = loader_position.y + AAI_PIPE_Y_OFFSET}
end

local function get_pipe_name(loader_name)
	return utils.strip_unpowered_prefix(loader_name) .. "-pipe"
end

local function ensure_compat_storage()
	if storage.compatibility == nil then
		storage.compatibility = {}
	end
	if storage.compatibility.aai_pipe_fluid_snapshots == nil then
		storage.compatibility.aai_pipe_fluid_snapshots = {}
	end
	if storage.compatibility.aai_pending_restores == nil then
		storage.compatibility.aai_pending_restores = {}
	end
	if storage.compatibility.skip_built_init_markers == nil then
		storage.compatibility.skip_built_init_markers = {}
	end
	if storage.compatibility.warned == nil then
		storage.compatibility.warned = {}
	end
	return storage.compatibility
end

local function warn_once(warn_key, message)
	local compat_storage = ensure_compat_storage()
	if compat_storage.warned[warn_key] then
		return
	end
	compat_storage.warned[warn_key] = true
	log("[PBE][compat] " .. message)
end

local function is_aai_loaders_active()
	return script ~= nil and script.active_mods ~= nil and script.active_mods[AAI_LOADERS_MOD] ~= nil
end

local function get_snapshot(surface_key, pos_key)
	local compat_storage = ensure_compat_storage()
	local by_surface = compat_storage.aai_pipe_fluid_snapshots[surface_key]
	if by_surface == nil then
		return nil
	end
	return by_surface[pos_key]
end

local function set_snapshot(surface_key, pos_key, entry)
	local compat_storage = ensure_compat_storage()
	if compat_storage.aai_pipe_fluid_snapshots[surface_key] == nil then
		compat_storage.aai_pipe_fluid_snapshots[surface_key] = {}
	end
	compat_storage.aai_pipe_fluid_snapshots[surface_key][pos_key] = entry
end

local function clear_snapshot(surface_key, pos_key)
	local compat_storage = ensure_compat_storage()
	local by_surface = compat_storage.aai_pipe_fluid_snapshots[surface_key]
	if by_surface ~= nil then
		by_surface[pos_key] = nil
		if next(by_surface) == nil then
			compat_storage.aai_pipe_fluid_snapshots[surface_key] = nil
		end
	end
end

local function mark_pending_restore(surface_key, pos_key, position)
	local compat_storage = ensure_compat_storage()
	if compat_storage.aai_pending_restores[surface_key] == nil then
		compat_storage.aai_pending_restores[surface_key] = {}
	end
	local by_surface = compat_storage.aai_pending_restores[surface_key]
	local entry = by_surface[pos_key]
	if entry == nil then
		entry = {tries = 0, position = copy_position(position)}
		by_surface[pos_key] = entry
	end
	entry.tries = (entry.tries or 0) + 1
	entry.position = copy_position(position)
	return entry
end

local function clear_pending_restore(surface_key, pos_key)
	local compat_storage = ensure_compat_storage()
	local by_surface = compat_storage.aai_pending_restores[surface_key]
	if by_surface ~= nil then
		by_surface[pos_key] = nil
		if next(by_surface) == nil then
			compat_storage.aai_pending_restores[surface_key] = nil
		end
	end
end

local function clear_snapshot_and_pending(surface_key, pos_key)
	clear_snapshot(surface_key, pos_key)
	clear_pending_restore(surface_key, pos_key)
end

local function set_skip_built_init_marker(surface_key, pos_key, expected_name)
	local compat_storage = ensure_compat_storage()
	if compat_storage.skip_built_init_markers[surface_key] == nil then
		compat_storage.skip_built_init_markers[surface_key] = {}
	end
	compat_storage.skip_built_init_markers[surface_key][pos_key] = expected_name
end

local function clear_skip_built_init_marker(surface_key, pos_key)
	local compat_storage = ensure_compat_storage()
	local by_surface = compat_storage.skip_built_init_markers[surface_key]
	if by_surface ~= nil then
		by_surface[pos_key] = nil
		if next(by_surface) == nil then
			compat_storage.skip_built_init_markers[surface_key] = nil
		end
	end
end

local function consume_skip_built_init_marker(surface_key, pos_key)
	local compat_storage = ensure_compat_storage()
	local by_surface = compat_storage.skip_built_init_markers[surface_key]
	if by_surface == nil then
		return nil
	end
	local expected_name = by_surface[pos_key]
	if expected_name == nil then
		return nil
	end
	by_surface[pos_key] = nil
	if next(by_surface) == nil then
		compat_storage.skip_built_init_markers[surface_key] = nil
	end
	return expected_name
end

local function find_pipe_entity(surface, pipe_name, loader_position, force_name)
	if not (surface and surface.valid and type(pipe_name) == "string" and pipe_name ~= "") then
		return nil
	end
	local pipe_position = get_pipe_position(loader_position)
	local entity = surface.find_entity(pipe_name, pipe_position)
	if entity ~= nil and entity.valid and (force_name == nil or entity.force.name == force_name) then
		return entity
	end

	local nearby = surface.find_entities_filtered{
		name = pipe_name,
		position = pipe_position,
		radius = 0.12,
	}
	for _, candidate in pairs(nearby) do
		if candidate and candidate.valid and (force_name == nil or candidate.force.name == force_name) then
			return candidate
		end
	end
	return nil
end

local function find_powered_aai_loader_entity(surface, position)
	if not (surface and surface.valid and type(position) == "table") then
		return nil
	end
	local entities = surface.find_entities_filtered{
		position = position,
		radius = 0.12,
		type = {"loader", "loader-1x1"},
	}
	for _, entity in pairs(entities) do
		if entity and entity.valid and is_aai_loader_name(entity.name) and not utils.is_unpowered_name(entity.name) then
			return entity
		end
	end
	return nil
end

local function capture_fluid_snapshot(pipe)
	if not (pipe and pipe.valid) then
		return nil
	end
	local fluid = pipe.get_fluid(1)
	if fluid == nil then
		return nil
	end
	local amount = fluid.amount or 0
	if amount <= 0 then
		return nil
	end
	return {
		name = fluid.name,
		amount = amount,
		temperature = fluid.temperature,
	}
end

local function clear_pipe_fluid(pipe)
	if not (pipe and pipe.valid) then
		return
	end
	local existing = pipe.get_fluid(1)
	if existing ~= nil and existing.amount and existing.amount > 0 then
		pipe.remove_fluid({name = existing.name, amount = existing.amount})
	end
end

local function try_restore_pipe_fluid(loader_entity, warn_key_suffix)
	if not (loader_entity and loader_entity.valid and loader_entity.surface and loader_entity.surface.valid) then
		return false
	end

	local surface_key = loader_entity.surface.index
	local pos_key = utils.get_entity_position_key(loader_entity)
	local snapshot = get_snapshot(surface_key, pos_key)
	if snapshot == nil then
		clear_pending_restore(surface_key, pos_key)
		return true
	end

	local expected_loader_name = utils.strip_unpowered_prefix(loader_entity.name)
	if snapshot.loader_name ~= expected_loader_name then
		clear_snapshot_and_pending(surface_key, pos_key)
		return true
	end

	local pipe = find_pipe_entity(loader_entity.surface, snapshot.pipe_name, loader_entity.position, snapshot.force_name)
	if pipe == nil then
		local warn_key = "missing-restore-pipe:" .. tostring(surface_key) .. ":" .. pos_key .. ":" .. tostring(warn_key_suffix or "generic")
		warn_once(warn_key, "Could not find AAI loader pipe for restore at " .. pos_key .. " on surface " .. tostring(surface_key) .. ".")
		local pending_entry = mark_pending_restore(surface_key, pos_key, loader_entity.position)
		if (pending_entry.tries or 0) > MAX_PENDING_RESTORE_ATTEMPTS then
			warn_once(
				"pending-restore-timeout:" .. tostring(surface_key) .. ":" .. pos_key,
				"Timed out waiting for AAI pipe restore target at " .. pos_key .. " on surface " .. tostring(surface_key) .. ". Snapshot dropped."
			)
			clear_snapshot_and_pending(surface_key, pos_key)
		end
		return false
	end

	clear_pipe_fluid(pipe)
	local inserted = pipe.insert_fluid(snapshot.fluid)
	if inserted == nil then
		inserted = 0
	end
	if inserted + 0.0001 < snapshot.fluid.amount then
		warn_once(
			"partial-restore:" .. tostring(surface_key) .. ":" .. pos_key,
			"Partial AAI pipe fluid restore at " .. pos_key .. " on surface " .. tostring(surface_key) ..
			": inserted " .. tostring(inserted) .. " of " .. tostring(snapshot.fluid.amount) .. "."
		)
	end

	clear_snapshot_and_pending(surface_key, pos_key)
	return true
end

function compatibility.init_storage()
	ensure_compat_storage()
end

function compatibility.on_pre_replace(entity, new_name, power_up)
	local context = {raise_built = false}
	if not is_aai_loaders_active() then
		return context
	end
	if not entity or not entity.valid then
		return context
	end

	local old_name = entity.name
	if not is_aai_loader_name(old_name) and not is_aai_loader_name(new_name) then
		return context
	end

	if power_up and is_aai_loader_name(new_name) and not utils.is_unpowered_name(new_name) then
		local surface_key = entity.surface and entity.surface.index or nil
		if surface_key ~= nil then
			local pos_key = utils.get_entity_position_key(entity)
			set_skip_built_init_marker(surface_key, pos_key, new_name)
		end
		context.raise_built = true
		return context
	end

	if power_up then
		return context
	end

	local surface = entity.surface
	local surface_key = surface and surface.index or nil
	if surface_key == nil then
		return context
	end
	local pos_key = utils.get_entity_position_key(entity)
	clear_snapshot_and_pending(surface_key, pos_key)

	local pipe_name = get_pipe_name(old_name)
	local pipe = find_pipe_entity(surface, pipe_name, entity.position, entity.force and entity.force.name or nil)
	if pipe == nil then
		warn_once(
			"missing-powerdown-pipe:" .. tostring(surface_key) .. ":" .. pos_key,
			"Could not find AAI pipe on power-down replace at " .. pos_key .. " on surface " .. tostring(surface_key) .. "."
		)
		return context
	end

	local snapshot_fluid = capture_fluid_snapshot(pipe)
	if snapshot_fluid ~= nil then
		set_snapshot(surface_key, pos_key, {
			loader_name = utils.strip_unpowered_prefix(old_name),
			pipe_name = pipe_name,
			force_name = pipe.force and pipe.force.name or nil,
			position = copy_position(entity.position),
			fluid = snapshot_fluid,
		})
	end

	local ok_destroy, destroy_error = pcall(function()
		pipe.destroy()
	end)
	if not ok_destroy then
		warn_once(
			"destroy-pipe-failed:" .. tostring(surface_key) .. ":" .. pos_key,
			"Failed to destroy AAI pipe at " .. pos_key .. " on surface " .. tostring(surface_key) .. ": " .. tostring(destroy_error)
		)
	end

	return context
end

function compatibility.on_post_replace(entity, power_up)
	if not is_aai_loaders_active() then
		return
	end
	if not power_up then
		return
	end
	if not (entity and entity.valid and is_aai_loader_name(entity.name) and not utils.is_unpowered_name(entity.name)) then
		return
	end
	try_restore_pipe_fluid(entity, "post-replace")
end

function compatibility.on_built_entity(entity)
	if not is_aai_loaders_active() then
		return
	end
	if not (entity and entity.valid and is_aai_loader_name(entity.name) and not utils.is_unpowered_name(entity.name)) then
		return
	end
	try_restore_pipe_fluid(entity, "built-event")
end

function compatibility.on_removed_entity(entity)
	if not is_aai_loaders_active() then
		return
	end
	if entity == nil then
		return
	end
	local entity_name = entity.name
	if not is_aai_loader_name(entity_name) then
		return
	end
	local surface = entity.surface
	local position = entity.position
	if surface == nil or position == nil then
		return
	end
	local pos_key = utils.get_position_key(position)
	clear_snapshot_and_pending(surface.index, pos_key)
	clear_skip_built_init_marker(surface.index, pos_key)
end

function compatibility.consume_skip_built_init_marker(entity)
	if not is_aai_loaders_active() then
		return false
	end
	if not (entity and entity.valid and entity.surface and entity.surface.valid and is_aai_loader_name(entity.name)) then
		return false
	end
	local surface_key = entity.surface.index
	local pos_key = utils.get_entity_position_key(entity)
	local expected_name = consume_skip_built_init_marker(surface_key, pos_key)
	if expected_name == nil then
		return false
	end
	if expected_name ~= entity.name then
		return false
	end
	return true
end

function compatibility.clear_skip_built_init_marker(surface, position)
	if surface == nil or position == nil then
		return
	end
	clear_skip_built_init_marker(surface.index, utils.get_position_key(position))
end

function compatibility.on_tick()
	if not is_aai_loaders_active() then
		return
	end

	local compat_storage = ensure_compat_storage()
	local pending_restores = compat_storage.aai_pending_restores
	if pending_restores == nil or next(pending_restores) == nil then
		return
	end

	local processed = 0
	for surface_key, by_surface in pairs(pending_restores) do
		local surface = game.surfaces[surface_key]
		if surface == nil then
			compat_storage.aai_pending_restores[surface_key] = nil
		else
			local to_clear = {}
			for pos_key, pending_entry in pairs(by_surface) do
				if processed >= MAX_PENDING_RESTORES_PER_TICK then
					break
				end
				processed = processed + 1
				local position = pending_entry and pending_entry.position or nil
				if position == nil then
					to_clear[#to_clear + 1] = pos_key
				else
					local loader_entity = find_powered_aai_loader_entity(surface, position)
					if loader_entity ~= nil then
						local restored = try_restore_pipe_fluid(loader_entity, "pending")
						if restored then
							to_clear[#to_clear + 1] = pos_key
						end
					else
						local tries = (pending_entry.tries or 0) + 1
						pending_entry.tries = tries
						if tries > MAX_PENDING_RESTORE_ATTEMPTS then
							warn_once(
								"pending-no-loader-timeout:" .. tostring(surface_key) .. ":" .. pos_key,
								"Timed out waiting for powered AAI loader entity at " .. pos_key ..
								" on surface " .. tostring(surface_key) .. ". Snapshot dropped."
							)
							clear_snapshot(surface_key, pos_key)
							to_clear[#to_clear + 1] = pos_key
						end
					end
				end
			end
			for _, pos_key in pairs(to_clear) do
				by_surface[pos_key] = nil
			end
			if next(by_surface) == nil then
				compat_storage.aai_pending_restores[surface_key] = nil
			end
		end
		if processed >= MAX_PENDING_RESTORES_PER_TICK then
			break
		end
	end
end

return compatibility

