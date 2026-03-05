local utils = require("modules.utils")

local tests = {}

function tests.set_test_overrides(overrides)
	if type(overrides) ~= "table" then
		storage.test_overrides = {}
		return storage.test_overrides
	end

	local sanitized = {}
	if overrides.underground_item_transfer_mode ~= nil then
		sanitized.underground_item_transfer_mode = utils.normalize_underground_transfer_mode(overrides.underground_item_transfer_mode)
	end
	if type(overrides.required_energy_percentage) == "number" then
		sanitized.required_energy_percentage = utils.normalize_required_energy_percentage(overrides.required_energy_percentage)
	end
	if type(overrides.operations_per_tick) == "number" then
		sanitized.operations_per_tick = math.max(1, math.floor(overrides.operations_per_tick))
	end
	if type(overrides.update_iteration_probe_ticks) == "table" then
		sanitized.update_iteration_probe_ticks = {}
		for _, tick in pairs(overrides.update_iteration_probe_ticks) do
			if type(tick) == "number" then
				sanitized.update_iteration_probe_ticks[math.floor(tick)] = true
			end
		end
	end

	storage.test_overrides = sanitized
	return storage.test_overrides
end

function tests.register_test_api()
	if rawget(_G, "__PBE_UNIT_TEST_MODE") then
		_G.__PBE_TEST_API = {
			normalize_underground_transfer_mode = utils.normalize_underground_transfer_mode,
			preserve_mode_enabled = utils.preserve_mode_enabled,
			underground_item_transfer_disabled = utils.underground_item_transfer_disabled,
		}
	end
end

function tests.should_probe_update_iteration_tick()
	local overrides = storage.test_overrides
	local probe_ticks = overrides and overrides.update_iteration_probe_ticks
	return probe_ticks ~= nil and probe_ticks[game.tick] == true
end

function tests.maybe_probe_update_iteration(phase, surface_key, entity_key, entity)
	if not tests.should_probe_update_iteration_tick() then
		return
	end
	if not (remote.interfaces and remote.interfaces.pbe_integration_harness and remote.interfaces.pbe_integration_harness.record_update_loop_iteration_probe) then
		return
	end
	local position = nil
	if entity ~= nil and entity.valid and entity.position ~= nil then
		position = {x = entity.position.x, y = entity.position.y}
	end
	remote.call("pbe_integration_harness", "record_update_loop_iteration_probe", {
		phase = phase,
		tick = game.tick,
		surface = surface_key,
		entity_key = entity_key,
		entity_name = entity and entity.valid and entity.name or nil,
		entity_type = entity and entity.valid and entity.type or nil,
		position = position,
	})
end

return tests
