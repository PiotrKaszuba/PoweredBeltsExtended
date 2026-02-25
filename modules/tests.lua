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

return tests
