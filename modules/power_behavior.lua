local power_behavior = {}

power_behavior.setting_names = {
	startup_preset = "powered-belts-energy-behavior-preset",
	ifl_mult = "powered-belts-input-flow-limit-multiplier",
	ifl_flat = "powered-belts-input-flow-limit-flat",
	bc_mult = "powered-belts-buffer-capacity-multiplier",
	required_pct = "powered-belts-required-energy-percentage",
	required_flat = "powered-belts-required-energy-percentage-flat",
	hysteresis_pct = "powered-belts-required-energy-hysteresis-percentage",
}

power_behavior.presets = {
	default = {
		ifl_mult = 1.0,
		ifl_flat = 10,
		bc_mult = 1.0,
		required_pct = 50,
		required_flat = 0,
		hysteresis_pct = 0,
	},
	synchronized = {
		ifl_mult = 2.0,
		ifl_flat = 0,
		bc_mult = 1.0,
		required_pct = 50,
		required_flat = 0,
		hysteresis_pct = 0,
	},
	responsive = {
		ifl_mult = 5.0,
		ifl_flat = 0,
		bc_mult = 0.25,
		required_pct = 50,
		required_flat = 0,
		hysteresis_pct = 10,
	},
}

local function clamp(value, min_value, max_value)
	if value < min_value then
		return min_value
	end
	if value > max_value then
		return max_value
	end
	return value
end

power_behavior.clamp = clamp

function power_behavior.normalize_preset(value)
	if type(value) ~= "string" then
		return "default"
	end
	if value == "default" or value == "synchronized" or value == "responsive" or value == "custom" then
		return value
	end
	return "default"
end

function power_behavior.normalize_ifl_mult(value)
	if type(value) ~= "number" then
		return 1.0
	end
	return clamp(value, 1.0, 10.0)
end

function power_behavior.normalize_ifl_flat(value)
	if type(value) ~= "number" then
		return 10
	end
	return math.floor(clamp(value, 0, 100))
end

function power_behavior.normalize_bc_mult(value)
	if type(value) ~= "number" then
		return 1.0
	end
	return clamp(value, 0.01, 10.0)
end

function power_behavior.normalize_required_energy_percentage(value)
	if type(value) ~= "number" then
		return 50
	end
	return clamp(value, 0, 100)
end

function power_behavior.normalize_required_energy_flat(value)
	if type(value) ~= "number" then
		return 0
	end
	return clamp(value, 0, 100)
end

function power_behavior.normalize_hysteresis_percentage(value)
	if type(value) ~= "number" then
		return 0
	end
	return clamp(value, 0, 33)
end

local function read_setting_value(setting_table, name)
	if type(setting_table) ~= "table" then
		return nil
	end
	local setting = setting_table[name]
	if setting == nil then
		return nil
	end
	return setting.value
end

function power_behavior.resolve_startup_settings(startup_table)
	local preset = power_behavior.normalize_preset(read_setting_value(startup_table, power_behavior.setting_names.startup_preset))
	if preset ~= "custom" then
		local preset_values = power_behavior.presets[preset] or power_behavior.presets.default
		return {
			preset = preset,
			ifl_mult = preset_values.ifl_mult,
			ifl_flat = preset_values.ifl_flat,
			bc_mult = preset_values.bc_mult,
			required_pct = preset_values.required_pct,
			required_flat = preset_values.required_flat,
			hysteresis_pct = preset_values.hysteresis_pct,
			uses_custom = false,
		}
	end

	return {
		preset = "custom",
		ifl_mult = power_behavior.normalize_ifl_mult(read_setting_value(startup_table, power_behavior.setting_names.ifl_mult)),
		ifl_flat = power_behavior.normalize_ifl_flat(read_setting_value(startup_table, power_behavior.setting_names.ifl_flat)),
		bc_mult = power_behavior.normalize_bc_mult(read_setting_value(startup_table, power_behavior.setting_names.bc_mult)),
		required_pct = nil,
		required_flat = nil,
		hysteresis_pct = nil,
		uses_custom = true,
	}
end

function power_behavior.resolve_runtime_threshold(startup_table, global_table, overrides)
	local startup = power_behavior.resolve_startup_settings(startup_table)

	local required_pct = nil
	local required_flat = nil
	local hysteresis_pct = nil

	if startup.uses_custom then
		local override_table = type(overrides) == "table" and overrides or nil
		required_pct = power_behavior.normalize_required_energy_percentage(
			override_table and override_table.required_energy_percentage or read_setting_value(global_table, power_behavior.setting_names.required_pct)
		)
		required_flat = power_behavior.normalize_required_energy_flat(
			override_table and override_table.required_energy_percentage_flat or read_setting_value(global_table, power_behavior.setting_names.required_flat)
		)
		hysteresis_pct = power_behavior.normalize_hysteresis_percentage(
			override_table and override_table.required_energy_hysteresis_percentage or read_setting_value(global_table, power_behavior.setting_names.hysteresis_pct)
		)
	else
		required_pct = startup.required_pct
		required_flat = startup.required_flat
		hysteresis_pct = startup.hysteresis_pct
	end

	local effective_threshold_pct = clamp(required_pct + required_flat, 0, 100)
	local hysteresis_fraction = hysteresis_pct / 100
	local down_pct = clamp((1 - hysteresis_fraction) * effective_threshold_pct, 0, 100)
	local up_pct = clamp((1 + hysteresis_fraction) * effective_threshold_pct, 0, 100)

	return {
		preset = startup.preset,
		uses_custom = startup.uses_custom,
		required_pct = required_pct,
		required_flat = required_flat,
		effective_threshold_pct = effective_threshold_pct,
		hysteresis_pct = hysteresis_pct,
		down_pct = down_pct,
		up_pct = up_pct,
	}
end

function power_behavior.compute_power_source_values(ei, startup_settings)
	local cfg = startup_settings or {}
	local base_ei = type(ei) == "number" and ei or 0
	local flow_kw = math.max(base_ei, (base_ei * (cfg.ifl_mult or 1.0)) + (0.1 * (cfg.ifl_flat or 0)))
	local buffer_kj = math.max(0.001, base_ei * (cfg.bc_mult or 1.0))
	return flow_kw, buffer_kj
end

return power_behavior
