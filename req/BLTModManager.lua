---@class BLTModManager : BLTModule
---@field new fun(self):BLTModManager
BLTModManager = blt_class(BLTModule)
BLTModManager.__type = "BLTModManager"

function BLTModManager:init()
	BLTModManager.super.init(self)
end

---Returns all mods managed by BLT
---@return BLTMod[] @Table of mods
function BLTModManager:Mods()
	return self.mods
end

---Returns the mod with the given name
---@param name string @The name of the mod
---@return BLTMod? @The mod instance, or `nil` if not found
function BLTModManager:GetModByName(name)
	for _, mod in pairs(self:Mods()) do
		if mod:GetName() == name then
			return mod
		end
	end
end

---Returns the mod with the given ID
---@param id string @The ID of the mod
---@return BLTMod? @The mod instance, or `nil` if not found
function BLTModManager:GetMod(id)
	for _, mod in ipairs(self:Mods()) do
		if mod:GetId() == id then
			return mod
		end
	end
end

---Returns the mod of which the given file is a part of
---@param file string @The path (relative to payday2_win32_release.exe) of the file
---@return BLTMod? @The mod instance, or `nil` if not found
function BLTModManager:GetModOwnerOfFile(file)
	for _, mod in pairs(self:Mods()) do
		if string.find(file, mod:GetPath(), 1, true) == 1 then
			return mod
		end
	end
end

---@param mods_list BLTMod[]
function BLTModManager:SetModsList(mods_list)
	self.mods = mods_list

	self.profiles = BLT.save_data.profiles
	if not self.profiles or #self.profiles == 0 then
		self.profiles = {
			{
				mods = BLT.save_data.mods or {}
			}
		}
	end
	self.profile_index = math.min(math.max(BLT.save_data.profile_index or 1, 1), #self.profiles)

	self:SwitchProfile(self.profile_index, true)

	-- Setup mods
	for _, mod in ipairs(self.mods) do
		mod:Setup()
	end
end

---@param profile_index integer?
---@return string
function BLTModManager:ProfileName(profile_index)
	profile_index = profile_index or self.profile_index

	return self.profiles[profile_index] and self.profiles[profile_index].name or managers.localization:text("blt_default_profile_name", { number = tostring(profile_index) })
end

---@param name string
---@param profile_index integer?
function BLTModManager:SetProfileName(name, profile_index)
	profile_index = profile_index or self.profile_index

	if self.profiles[profile_index] then
		self.profiles[profile_index].name = name
	end
end

---@param based_on integer?
---@return integer
function BLTModManager:CreateProfile(based_on)
	local profile = deep_clone(self.profiles[based_on or self.profile_index])
	profile.name = nil
	table.insert(self.profiles, profile)
	return #self.profiles
end

---@param profile_index integer?
function BLTModManager:SaveProfile(profile_index)
	profile_index = profile_index or self.profile_index

	local profile = self.profiles[self.profile_index]
	if not profile.mods then
		profile.mods = {}
	end

	for _, mod in pairs(self:Mods()) do
		local updates = {}
		for _, update in pairs(mod:GetUpdates()) do
			updates[update:GetId()] = update:IsEnabled()
		end

		profile.mods[mod:GetId()] = {
			enabled = mod._dependency_enabled or mod:IsEnabled(),
			safe = mod:IsSafeModeEnabled(),
			updates = updates
		}
	end
end

---@param profile_index integer
---@param is_startup boolean?
function BLTModManager:SwitchProfile(profile_index, is_startup)
	if profile_index < 1 or profile_index > #self.profiles then
		return
	end

	if profile_index ~= self.profile_index then
		self:SaveProfile()
	end

	self.profile_index = profile_index

	local mods = self.profiles[self.profile_index].mods or {}
	for _, mod in ipairs(self.mods) do
		local data = mods[mod:GetId()]

		mod:SetEnabled(not data or data.enabled, is_startup)
		mod:SetSafeModeEnabled(data and data.safe)

		for _, update in ipairs(mod:GetUpdates()) do
			local update_enabled = data and data.updates and data.updates[update:GetId()]
			update:SetEnabled(update_enabled == nil or update_enabled)
		end
	end
end

---@param profile_index integer?
function BLTModManager:DeleteProfile(profile_index)
	profile_index = profile_index or self.profile_index

	if #self.profiles < 2 or profile_index < 1 or profile_index > #self.profiles then
		return
	end

	if profile_index < self.profile_index then
		self.profile_index = self.profile_index - 1
	elseif profile_index == self.profile_index then
		self:SwitchProfile(profile_index == 1 and 2 or profile_index - 1)
		if profile_index == 1 then
			self.profile_index = 1
		end
	end

	table.remove(self.profiles, profile_index)
end

function BLTModManager:IsExcludedDirectory(directory)
	return BLTModManager.Constants.ExcludedModDirectories[directory]
end

function BLTModManager:CheckRestartNeeded()
	local needs_restart = {}
	for _, mod in pairs(self:Mods()) do
		if mod.needs_restart and mod:IsEnabled() ~= mod:WasEnabledAtStart() then
			table.insert(needs_restart, mod:GetName())
		end
	end

	if self._restart_notification then
		BLT.Notifications:remove_notification(self._restart_notification)
		self._restart_notification = nil
	end

	if #needs_restart > 0 then
		local icon, rect = tweak_data.hud_icons:get_icon_data("csb_stamina")
		self._restart_notification = BLT.Notifications:add_notification({
			title = managers.localization:text("blt_restart_required"),
			text = managers.localization:text("blt_restart_required_desc"),
			icon = icon,
			icon_texture_rect = rect,
			priority = 2000,
			callback = function()
				managers.system_menu:show({
					title = managers.localization:text("blt_restart_required"),
					text = managers.localization:text("blt_restart_required_details", { mods = table.concat(needs_restart, "\n") }),
					button_list = {
						{
							text = managers.localization:text("dialog_yes"),
							callback_func = function()
								MenuCallbackHandler:_dialog_quit_yes()
							end
						},
						{
							text = managers.localization:text("dialog_no"),
							cancel_button = true
						}
					}
				})
			end
		})
	end
end

--------------------------------------------------------------------------------
-- Autoupdates

function BLTModManager:RunAutoCheckForUpdates()
	-- Don't run the autocheck twice
	if self._has_checked_for_updates then
		return
	end
	self._has_checked_for_updates = true

	call_on_next_update(callback(self, self, "_RunAutoCheckForUpdates"))
end

function BLTModManager:_RunAutoCheckForUpdates()
	-- Place a notification that we're checking for autoupdates
	if BLT.Notifications then
		local icon, rect = tweak_data.hud_icons:get_icon_data("csb_pagers")
		self._updates_notification = BLT.Notifications:add_notification({
			title = managers.localization:text("blt_checking_updates"),
			text = managers.localization:text("blt_checking_updates_help"),
			icon = icon,
			icon_texture_rect = rect,
			color = Color.white,
			priority = 1000
		})
	end

	-- Start checking all enabled mods for updates
	local count = 0
	for _, mod in ipairs(self:Mods()) do
		for _, update in ipairs(mod:GetUpdates()) do
			if update:IsEnabled() then
				update:CheckForUpdates(callback(self, self, "clbk_got_update"))
				count = count + 1
			end
		end
	end

	-- -- Remove notification if not getting updates
	if count < 1 and self._updates_notification then
		BLT.Notifications:remove_notification(self._updates_notification)
		self._updates_notification = nil
	end
end

function BLTModManager:clbk_got_update(update, required, reason)
	-- Add the pending download if required
	if required then
		BLT.Downloads:add_pending_download(update)
	end

	-- Check if any mods are still updating
	local still_checking = false
	for _, mod in ipairs(self:Mods()) do
		if mod:IsCheckingForUpdates() then
			still_checking = true
			break
		end
	end

	if not still_checking then
		-- Remove the old notification
		if self._updates_notification then
			BLT.Notifications:remove_notification(self._updates_notification)
			self._updates_notification = nil
		end

		-- Add notification if we need updates
		if table.size(BLT.Downloads:pending_downloads()) > 0 then
			local icon, rect = tweak_data.hud_icons:get_icon_data("csb_pagers")
			self._updates_notification = BLT.Notifications:add_notification({
				title = managers.localization:text("blt_checking_updates_required"),
				text = managers.localization:text("blt_checking_updates_required_help"),
				icon = icon,
				icon_texture_rect = rect,
				color = Color.white,
				priority = 1000
			})
		else
			local icon, rect = tweak_data.hud_icons:get_icon_data("csb_pagers")
			self._updates_notification = BLT.Notifications:add_notification({
				title = managers.localization:text("blt_checking_updates_none_required"),
				text = managers.localization:text("blt_checking_updates_none_required_help"),
				icon = icon,
				icon_texture_rect = rect,
				color = Color.white,
				priority = 0
			})
		end
	end
end

Hooks:Add("BLTOnSaveData", "BLTOnSaveData.BLTModManager", function(save_data)

	BLT.Mods:SaveProfile()

	save_data.profile_index = BLT.Mods.profile_index
	save_data.profiles = {}

	for _, v in ipairs(BLT.Mods.profiles) do
		table.insert(save_data.profiles, {
			name = v.name,
			mods = v.mods
		})
	end
end)

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

BLTModManager.Constants = BLTModManager.Constants or {
	["mods_directory"] = "mods/",
	["lua_base_directory"] = "base/",
	["downloads_directory"] = "downloads/",
	["logs_directory"] = "logs/",
	["saves_directory"] = "saves/"
}
BLTModManager.Constants.ExcludedModDirectories = {
	["logs"] = true,
	["saves"] = true,
	["downloads"] = true
}
BLTModManager.Constants.required_script_global = "RequiredScript"
BLTModManager.Constants.mod_path_global = "ModPath"
BLTModManager.Constants.logs_path_global = "LogsPath"
BLTModManager.Constants.save_path_global = "SavePath"
BLTModManager.Constants.mod_instance_global = "ModInstance"

BLTModManager.Constants.lua_mods_menu_id = "blt_mods_new"
BLTModManager.Constants.lua_mod_options_menu_id = "blt_options"

function BLTModManager.Constants:ModsDirectory()
	return self["mods_directory"]
end

function BLTModManager.Constants:BaseDirectory()
	return self["mods_directory"] .. self["lua_base_directory"]
end

function BLTModManager.Constants:DownloadsDirectory()
	return self["mods_directory"] .. self["downloads_directory"]
end

function BLTModManager.Constants:LogsDirectory()
	return self["mods_directory"] .. self["logs_directory"]
end

function BLTModManager.Constants:SavesDirectory()
	return self["mods_directory"] .. self["saves_directory"]
end

function BLTModManager.Constants:ModManagerSaveFile(is_vr)
	if is_vr then
		return self:SavesDirectory() .. "blt_data_vr.txt"
	else
		return self:SavesDirectory() .. "blt_data.txt"
	end
end

function BLTModManager.Constants:LuaModsMenuID()
	return self["lua_mods_menu_id"]
end

function BLTModManager.Constants:LuaModOptionsMenuID()
	return self["lua_mod_options_menu_id"]
end

-- Backwards compatibility
BLTModManager.Constants._lua_mods_menu_id = BLTModManager.Constants.lua_mods_menu_id
BLTModManager.Constants._lua_mod_options_menu_id = BLTModManager.Constants.lua_mod_options_menu_id
