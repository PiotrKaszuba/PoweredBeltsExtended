local luaunit = require("luaunit")
local mode = _G.__PBE_TEST_API

TestUndergroundTransferMode = {}

function TestUndergroundTransferMode:test_test_api_present()
	luaunit.assertNotNil(mode)
end

function TestUndergroundTransferMode:test_normalize_defaults_to_name_only()
	luaunit.assertEquals(mode.normalize_underground_transfer_mode(nil), "name-only")
	luaunit.assertEquals(mode.normalize_underground_transfer_mode(""), "name-only")
	luaunit.assertEquals(mode.normalize_underground_transfer_mode("unknown"), "name-only")
end

function TestUndergroundTransferMode:test_normalize_accepts_known_modes()
	luaunit.assertEquals(mode.normalize_underground_transfer_mode("name-only"), "name-only")
	luaunit.assertEquals(mode.normalize_underground_transfer_mode("preserve-full-state"), "preserve-full-state")
	luaunit.assertEquals(mode.normalize_underground_transfer_mode("disabled"), "disabled")
end

function TestUndergroundTransferMode:test_mode_checks()
	luaunit.assertTrue(mode.preserve_mode_enabled("preserve-full-state"))
	luaunit.assertFalse(mode.preserve_mode_enabled("name-only"))
	luaunit.assertTrue(mode.underground_item_transfer_disabled("disabled"))
	luaunit.assertFalse(mode.underground_item_transfer_disabled("preserve-full-state"))
end
