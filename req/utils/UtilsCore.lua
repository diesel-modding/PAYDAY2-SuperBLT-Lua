_G.Utils = _G.Utils or {}

function Utils.MakeValueOutput(value, output)
	if type(value) == "string" then
		output[#output + 1] = '"'
		output[#output + 1] = value
		output[#output + 1] = '"'
	else
		output[#output + 1] = tostring(value)
	end
end

function Utils.MakeTableOutput(tbl, output, has, tabs, depth, maxDepth)
	has[tbl] = true
	output[#output + 1] = tostring(tbl)

	if next(tbl) then
		output[#output + 1] = " {\n"
		local nextTabs = tabs .. "\t"
		depth = depth + 1

		for k, v in pairs(tbl) do
			output[#output + 1] = nextTabs
			Utils.MakeValueOutput(k, output)
			output[#output + 1] = " = "

			if (type(v) == "table") and not has[v] and (depth < maxDepth) then
				Utils.MakeTableOutput(v, output, has, nextTabs, depth, maxDepth)
			else
				Utils.MakeValueOutput(v, output)
			end

			output[#output + 1] = "\n"
		end

		output[#output + 1] = tabs
		output[#output + 1] = "}"
	else
		output[#output + 1] = " {}"
	end
end

---Returns a string representing value
---If value is a table, ToString returns a string representing the table and its contents
---ToString will include the contents of nested tables down to maxDepth or 1
---@param value any @Any value
---@param maxDepth? number @Controls the depth that ToString will read to (defaults to `1`)
---@return string @A string representing value
function Utils.ToString(value, maxDepth)
	local output = {}

	if type(value) == "table" then
		local has = {}
		local tabs = ""
		local depth = 0
		maxDepth = maxDepth or 1
		Utils.MakeTableOutput(value, output, has, tabs, depth, maxDepth)
	else
		Utils.MakeValueOutput(value, output)
	end

	return table.concat(output)
end

---Prints the contents of a table to your console  
---May cause game slowdown if the table is fairly large, only for debugging purposes
---PrintTable will include the contents of nested tables down to maxDepth or 1
---@param tbl table @The table to print to console
---@param maxDepth? number @Controls the depth that PrintTable will read to (defaults to `1`)
function Utils.PrintTable(tbl, maxDepth)
	local output = nil

	if type(tbl) == "table" then
		output = {"\n"} -- Start the output on a new line. Doing this here to avoid a possibly large copy later.
		local has = {}
		local tabs = ""
		local depth = 0
		maxDepth = maxDepth or 1
		Utils.MakeTableOutput(tbl, output, has, tabs, depth, maxDepth)
	else
		output = {}
		Utils.MakeValueOutput(tbl, output)
	end

	log(table.concat(output))
end

---Saves the contents of a table to the specified file
---@param tbl table @The table to save to a file
---@param file string @The path (relative to payday2_win32_release.exe) and file name to save the table to
function Utils.SaveTable(tbl, file)
	Utils.DoSaveTable(tbl, {}, file, nil, "")
end

function Utils.DoSaveTable(tbl, cmp, fileName, fileIsOpen, preText)
	local file = nil
	if fileIsOpen == nil then
		file = io.open(fileName, "w")
	else
		file = fileIsOpen
	end

	cmp = cmp or {}
	if tbl and type(tbl) == "table" then
		for k, v in pairs(tbl) do
			if type(v) == "table" and not cmp[v] then
				cmp[v] = true
				file:write(preText .. string.format("[\"%s\"] -> table", tostring (k)) .. "\n")
				Utils.DoSaveTable(v, cmp, fileName, file, preText .. "\t")
			else
				file:write(preText .. string.format("\"%s\" -> %s", tostring(k), tostring(v)) .. "\n")
			end
		end
	else
		file:write(preText .. tostring(tbl) .. "\n")
	end

	if fileIsOpen == nil then
		file:close()
	end
end

---Returns if a string is empty or `nil`
---@param str string @The string to check
---@return boolean @`true` if the string is `""` or `nil`, `false` otherwise
function string.is_nil_or_empty(str)
	return str == "" or str == nil
end

---Rounds a number to the specified precision (decimal places)
---@param num number @The number to round
---@param idp integer @The number of decimal places to round to (defaults to `0`)
---@return number @The input number rounded to the input precision
function math.round_with_precision(num, idp)
	local mult = 10 ^ (idp or 0)
	return math.floor(num * mult + 0.5) / mult
end

---Returns whether you are in GameState (loadout, ingame, end screens like victory and defeat) or not
---@return boolean @`true` if you are in GameState, `false` otherwise
function Utils:IsInGameState()
	return game_state_machine and string.find(game_state_machine:current_state_name(), "game") and true or false
end

---Returns wether you are currently in a loading state or not
---@return boolean @`true` if you are in a loading state, `false` otherwise
function Utils:IsInLoadingState()
	return BaseNetworkHandler and BaseNetworkHandler._gamestate_filter.waiting_for_players[game_state_machine:last_queued_state_name()] and true or false
end

---Returns wether you are currently in game (you're able to use your weapons, spot, call teammates etc) or not  
---Only returns true if currently ingame, does not check for GameState like `Utils:IsInGameState()`
---@return boolean @`true` if you are in game, `false` otherwise
function Utils:IsInHeist()
	return BaseNetworkHandler and BaseNetworkHandler._gamestate_filter.any_ingame_playing[game_state_machine:last_queued_state_name()] and true or false
end

---Returns whether you are currently in custody or not
---@return boolean @`true` if you are in custody, `false` otherwise
function Utils:IsInCustody()
	local player = managers.player:local_player()
	if not alive(player) and managers and managers.trade then
		local session = managers.network:session()
		return session and session:local_peer() and managers.trade:is_peer_in_custody(session:local_peer():id()) or false
	end
	return false
end

---Checks current primary weapon's weapon category
---@param category string @The weapon category to check for (refer to weapontweakdata.lua)
---@return boolean @`true` if the weapon has `category` as category, `false` otherwise
function Utils:IsCurrentPrimaryOfCategory(category)
	local primary = managers.blackmarket:equipped_primary()
	return primary and table.contains(tweak_data.weapon[primary.weapon_id].categories, category) or false
end

---Checks current secondary weapon's weapon category
---@param category string @The weapon category to check for (refer to weapontweakdata.lua)
---@return boolean @`true` if the weapon has `category` as category, `false` otherwise
function Utils:IsCurrentSecondaryOfCategory(category)
	local secondary = managers.blackmarket:equipped_secondary()
	return secondary and table.contains(tweak_data.weapon[secondary.weapon_id].categories, category) or false
end

---Checks if a specific weapon is currently equipped
---@param id string @The weapon's name ID (refer to weapontweakdata.lua)
---@return boolean @`true` if the currently equipped weapon matches `id`, `false` if not and `nil` if no weapon is equipped
function Utils:IsCurrentWeapon(id)
	local player = managers.player:local_player()
	local weapon = player and player:inventory():equipped_unit()
	return weapon and weapon:base()._name_id == id
end

---Checks if the currently equipped weapon is your primary weapon
---@return boolean? @`true` if the current weapon is a primary, `false` if not and `nil` if no weapon is equipped
function Utils:IsCurrentWeaponPrimary()
	local player = managers.player:local_player()
	local weapon = player and player:inventory():equipped_unit()
	return weapon and weapon:base():selection_index() == 2
end

---Checks if the currently equipped weapon is your secondary weapon
---@return boolean? @`true` if the current weapon is a secondary, `false` if not and `nil` if no weapon is equipped
function Utils:IsCurrentWeaponSecondary()
	local player = managers.player:local_player()
	local weapon = player and player:inventory():equipped_unit()
	return weapon and weapon:base():selection_index() == 1
end

---Gets the point in the world where the player is aiming at as a Vector3
---@param player_unit? userdata @The player unit to get the aiming position of (defaults to the local player)
---@param maximum_range? number @The maximum distance to check for a point in cm (defaults to `100000`)
---@return Vector3? @A Vector3 containing the location that the player is looking at, or `nil` if the player was not looking at anything or was looking at something past the maximum_range
function Utils:GetPlayerAimPos(player_unit, maximum_range)
	player_unit = player_unit or managers.player:local_player()
	maximum_range = maximum_range or 100000

	local from, dir
	if player_unit:base().is_local_player then
		local player_camera = player_unit:camera()
		from = player_camera:position()
		dir = player_camera:forward()
	elseif player_unit:base().is_husk_player then
		local player_movement = player_unit:movement()
		from = player_movement:m_head_pos()
		dir = player_movement:detect_look_dir()
	end

	local ray = self:GetCrosshairRay(from, from + dir * maximum_range)
	return ray and ray.hit_position
end

---Gets a ray between two points and checks for a collision with a slot mask along the ray
---@param from Vector3 @The starting position of the ray (defaults to the current camera position)
---@param to Vector3 @The ending position of the ray (defaults to 200m in the current camera's look direction)
---@param slot_mask? string @The collision group to check against the ray (defaults to all objects the player can shoot)
---@return table? @A table containing the ray information or `nil` if no viewport camera exists
function Utils:GetCrosshairRay(from, to, slot_mask)
	local viewport = managers.viewport
	if not viewport:get_current_camera() then
		return
	end

	slot_mask = slot_mask or "bullet_impact_targets"

	if not from then
		from = viewport:get_current_camera_position()
	end

	if not to then
		to = Vector3()
		mvector3.set(to, viewport:get_current_camera_rotation():y())
		mvector3.multiply(to, 20000)
		mvector3.add(to, from)
	end

	return World:raycast("ray", from, to, "slot_mask", managers.slot:get_mask(slot_mask))
end

---Gets the string value of a toggle menu item and converts it to a boolean value
---@param item table @The toggle menu item to get a boolean value from
---@return boolean @`true` if the toggle item is on, `false` otherwise
function Utils:ToggleItemToBoolean(item)
	return item:value() == "on" and true or false
end

---Escapes special characters in a URL to turn it into a usable URL
---@param input_url string @The url to escape the characters of
---@return string @A url string with escaped characters
function Utils:EscapeURL(input_url)
	local url = input_url:gsub(" ", "%%20")
	url = url:gsub("!", "%%21")
	url = url:gsub("#", "%%23")
	url = url:gsub("-", "%%2D")
	return url
end

---Converts a date given by year, month and day into a timestamp
---@param year integer @Year of the date
---@param month integer @Month of the date
---@param day integer @Day of the date
---@return integer @Timestamp
function Utils:TimestampToEpoch(year, month, day)
	-- Adapted from https://stackoverflow.com/questions/4105012/convert-a-string-date-to-a-timestamp
	local offset = os.time() - os.time(os.date("!*t"))
	local time = os.time({
		day = day,
		month = month,
		year = year,
	})
	return (time or 0) + (offset or 0)
end

---Returns the first value in the list of arguments that isn't `nil`
---@param ... any @List of values
---@return any @First value that isn't `nil`, or `nil` if all of them are
function Utils:FirstNonNil(...)
	for _, v in pairs({...}) do
		if v ~= nil then
			return v
		end
	end
end

---Retrieves a value from a nested table by a sequence of keys
---@param tbl table @The nested table to retrieve the value from
---@param ... any @A sequence of keys to traverse the nested table
---@return any @The value found in the nested table, or `nil` if any key in the sequence is not found
function Utils:GetNestedValue(tbl, ...)
	local value = tbl
	for _, v in ipairs({...}) do
		if type(value) ~= "table" then
			return
		end
		value = value[v]
	end
	return value
end

---Sets a value in a nested table by a sequence of keys  
---Creates keys if needed but will not override existing keys that don't hold table values
---@param tbl table @The nested table to set the value in
---@param val any @The value to set in the table
---@param ... any @A sequence of keys to traverse the nested table
---@return boolean @`true` if the value was set, or `false` if any key in the sequence doesn't hold a table value
function Utils:SetNestedValue(tbl, val, ...)
	local args = {...}
	if #args == 0 then
		return false
	end

	local scope = tbl
	local last_key = table.remove(args)
	for _, v in ipairs(args) do
		if scope[v] == nil then
			scope[v] = {}
		elseif type(scope[v]) ~= "table" then
			return false
		end
		scope = scope[v]
	end

	scope[last_key] = val

	return true
end

---Checks if the given object is an instance of the specified class or a subclass of it
---@param object table @The object to check
---@param c table @The class to check against
---@return boolean @`true` if the object is an instance of the specified class or subclass of it, `false` otherwise
function Utils:IsInstanceOf(object, c)
	local meta = getmetatable(object) or object
	while meta do
		if meta == c then
			return true
		end
		meta = meta.super
	end
	return false
end



-- DEPRECATED FUNCTIONALITY --

---@deprecated @Use hooks or manual cloning instead
function _G.CloneClass(class)
	BLT:DeprecationWarning("CloneClass")
	if not class.orig then
		class.orig = clone(class)
	end
end

---@deprecated @Use `Utils.PrintTable` instead
function _G.PrintTable(...)
	BLT:DeprecationWarning("PrintTable")
	return Utils.PrintTable(...)
end

---@deprecated @Use `Utils.SaveTable` instead
function _G.SaveTable(...)
	BLT:DeprecationWarning("SaveTable")
	return Utils.SaveTable(...)
end

---@deprecated @Use `string.split` instead
function string.blt_split(str, delim, max_num)
	BLT:DeprecationWarning("string.blt_split")
	return string.split(str, delim, true, max_num)
end
