local utils = require("modules.utils")

local migrations = {}

local function migrate_surface_partition(storage_key)
	local table_root = storage[storage_key]
	if table_root == nil then
		storage[storage_key] = {}
		return
	end

	local needs_migration = false
	for _, value in pairs(table_root) do
		if type(value) ~= "table" then
			needs_migration = true
		end
		break
	end

	if not needs_migration then
		return
	end

	local migrated = {}
	for pos, entity in pairs(table_root) do
		if entity and entity.valid and entity.surface then
			local surface_key = utils.get_surface_key(entity.surface)
			if migrated[surface_key] == nil then
				migrated[surface_key] = {}
			end
			migrated[surface_key][pos] = entity
		end
	end

	storage[storage_key] = migrated
end

local function prune_deleted_surfaces()
	if not game then
		return
	end

	for surface_key, _ in pairs(storage.entities) do
		if game.surfaces[surface_key] == nil then
			storage.entities[surface_key] = nil
		end
	end

	for surface_key, _ in pairs(storage.power_entities) do
		if game.surfaces[surface_key] == nil then
			storage.power_entities[surface_key] = nil
		end
	end
end

function migrations.init_globals()
	if storage.entities == nil then
		storage.entities = {}
	end
	if storage.power_entities == nil then
		storage.power_entities = {}
	end
	if storage.sum_ticks == nil then storage.sum_ticks = 0 end
	if storage.total_num_saved_items == nil then storage.total_num_saved_items = 0 end

	if storage.saved_items == nil then
		storage.saved_items = {}
	end
	if storage.saved_items_true == nil then
		storage.saved_items_true = {}
	end
	if storage.saved_items_per_lane == nil then
		storage.saved_items_per_lane = {}
	end
	
	if storage.num_saved_items_per_lane == nil then
		storage.num_saved_items_per_lane = {}
	end
	
	if storage.spilled_items == nil then
		storage.spilled_items = {}
	end
	if storage.preserve_mode_fallback_items == nil then
		storage.preserve_mode_fallback_items = 0
	end
	if storage.preserve_mode_slot_overflow_items == nil then
		storage.preserve_mode_slot_overflow_items = 0
	end

	if not storage.player_forces then storage.player_forces = {} end
	if storage.test_overrides == nil then
		storage.test_overrides = {}
	end

	migrate_surface_partition("entities")
	migrate_surface_partition("power_entities")
	prune_deleted_surfaces()

	storage.tick_iterator_key = nil
	storage.tick_surface_iterator_key = nil

	storage.belt_check_interval = 0.05
	storage.belt_interval = 0.25
	storage.ground_lanes_max_check = 1.0
	storage.fill_trial_interval = 0.025
	storage.ver = utils.current_version
end

return migrations
