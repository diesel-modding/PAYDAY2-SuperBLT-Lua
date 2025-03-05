---@class BLTMod
---@field new fun(self, identifier: string, data: table, path: string):BLTMod, boolean
BLTMod = blt_class()
BLTMod.enabled = true
BLTMod._enabled = true
BLTMod.safe_mode = true

function BLTMod:init(identifier, data, path)
	if not identifier or not data or not path then
		return false
	end

	self._errors = {}
	self._legacy_updates = {}

	-- Mod information
	self.id = identifier
	self.json_data = data
	self.path = path

	self.name = data.name or "Unnamed BLT Mod"
	self.desc = data.description or "No description"
	self.version = data.version or "1.0"
	self.blt_version = data.blt_version or "1.0"
	self.author = data.author or "Unknown"
	self.contact = data.contact or "N/A"
	self.priority = tonumber(data.priority) or 0
	self.dependencies = data.dependencies or {}
	self.color = data.color or nil
	self.image_path = data.image or nil
	self.disable_safe_mode = data.disable_safe_mode or false
	self.undisablable = data.undisablable or false
	self.library = data.is_library or false
	self.vr_disabled = data.vr_disabled or false
	self.desktop_disabled = data.desktop_disabled or false
	self.needs_restart = data.needs_restart or nil

	-- Updates data
	self.updates = {}
	if data.updates then
		for i, update_data in ipairs(data.updates) do
			if not update_data.host then
				-- Old PaydayMods update, server is gone so don't update those
				-- Do keep track of what we have installed though, for dependencies
				if update_data.identifier then -- sanity check
					self._legacy_updates[update_data.identifier] = true
				end
			else
				local new_update, valid = BLTUpdate:new(self, update_data)
				if valid and new_update:IsPresent() then
					table.insert(self.updates, new_update)
				end
			end
		end
	end

	-- Return wether the mod is valid (allowed to run in VR/Non-VR)
	local is_vr = BLT:IsVr()
	return is_vr and not self.vr_disabled or not is_vr and not self.desktop_disabled
end

function BLTMod:Setup()
	BLT:Log(LogLevel.INFO, string.format("[BLT] Setting up mod '%s'", self:GetName()))

	-- Check dependencies are installed for this mod
	if not self:AreDependenciesInstalled() then
		self._dependency_enabled = self._enabled
		table.insert(self._errors, "blt_mod_missing_dependencies")
		self:RetrieveDependencies()
		self:SetEnabled(false, true)
		return
	end

	-- Hooks data
	self.hooks = {}
	self:AddHooks("hooks", BLT.hook_tables.post, BLT.hook_tables.wildcards)
	self:AddHooks("pre_hooks", BLT.hook_tables.pre, BLT.hook_tables.wildcards)

	-- Keybinds
	if BLT.Keybinds then
		for i, keybind_data in ipairs(self.json_data.keybinds or {}) do
			BLT.Keybinds:register_keybind_json(self, keybind_data)
		end
	end

	-- Persist Scripts
	for i, persist_data in ipairs(self.json_data.persist_scripts or {}) do
		if persist_data and persist_data.global and persist_data.script_path then
			self:AddPersistScript(persist_data.global, persist_data.script_path)
		end
	end

	-- Set up the supermod instance
	self.supermod = BLTSuperMod.try_load(self, self.json_data.supermod_definition)
end

function BLTMod:AddHooks(data_key, destination, wildcards_destination)
	for i, hook_data in ipairs(self.json_data[data_key] or {}) do
		local hook_id = hook_data.hook_id and hook_data.hook_id:lower()
		local script = hook_data.script_path

		self:AddHook(data_key, hook_id, script, destination, wildcards_destination)
	end
end

function BLTMod:AddHook(data_key, hook_id, script, destination, wildcards_destination)
	self.hooks[data_key] = self.hooks[data_key] or {}

	-- Add hook to info table
	local unique = true
	for i, hook in ipairs(self.hooks[data_key]) do
		if hook == hook_id then
			unique = false
			break
		end
	end
	if unique then
		table.insert(self.hooks[data_key], hook_id)
	end

	-- Add hook to hooks tables
	if hook_id and script and self:IsEnabled() then
		local data = {
			mod = self,
			script = script
		}

		if hook_id ~= "*" then
			destination[hook_id] = destination[hook_id] or {}
			table.insert(destination[hook_id], data)
		else
			table.insert(wildcards_destination, data)
		end
	end
end

function BLTMod:AddPersistScript(global, file)
	self._persists = self._persists or {}
	table.insert(self._persists, {
		global = global,
		file = file
	})
end

function BLTMod:GetHooks()
	return (self.hooks or {}).hooks
end

function BLTMod:GetPreHooks()
	return (self.hooks or {}).pre_hooks
end

function BLTMod:GetPersistScripts()
	return self._persists or {}
end

function BLTMod:Errors()
	if #self._errors > 0 then
		return self._errors
	else
		return false
	end
end

function BLTMod:LastError()
	local n = #self._errors
	if n > 0 then
		return self._errors[n]
	else
		return false
	end
end

function BLTMod:IsOutdated()
	return self._outdated
end

function BLTMod:IsEnabled()
	return self.enabled
end

function BLTMod:WasEnabledAtStart()
	return self._enabled
end

function BLTMod:SetEnabled(enable, force)
	self.enabled = self:IsUndisablable() or enable
	if force then
		self._enabled = self.enabled
	end
end

function BLTMod:GetPath()
	return self.path
end

function BLTMod:GetDir()
	-- Strip mod folder name from path
	local dir = self:GetPath():gsub("[^/\\]+[/\\]$", "")
	return dir
end

function BLTMod:GetJsonData()
	return self.json_data
end

function BLTMod:GetId()
	return self.id
end

function BLTMod:GetName()
	return self.name
end

function BLTMod:GetDescription()
	return self.desc
end

function BLTMod:GetVersion()
	return self.version
end

function BLTMod:GetBLTVersion()
	return self.blt_version
end

function BLTMod:GetAuthor()
	return self.author
end

function BLTMod:GetContact()
	return self.contact
end

function BLTMod:GetPriority()
	return self.priority
end

function BLTMod:GetColor()
	if not self.color then
		return tweak_data.screen_colors.button_stage_3
	end

	-- Delay evaluation of color until first call
	if type(self.color) == "string" then
		local r, g, b = self.color:match("([.0-9]+)%s+([.0-9]+)%s+([.0-9]+)")
		r = tonumber(r) or 0
		g = tonumber(g) or 0
		b = tonumber(b) or 0
		if r > 1 or g > 1 or b > 1 then
			r = r / 255
			g = g / 255
			b = b / 255
		end
		self.color = Color(r, g, b)
	end

	return self.color
end

function BLTMod:HasModImage()
	return self.image_path ~= nil
end

function BLTMod:GetModImagePath()
	return self:GetPath() .. tostring(self.image_path)
end

function BLTMod:GetModImage()
	if self.mod_image_id then
		return self.mod_image_id
	end

	if not self:HasModImage() or not DB or not DB.create_entry then
		return nil
	end

	-- Check if the file exists on disk and generate if it does
	if file.FileExists(Application:nice_path(self:GetModImagePath())) then
		local type_texture_id = Idstring("texture")
		local path = self:GetModImagePath()
		local texture_id = Idstring(path)

		DB:create_entry(type_texture_id, texture_id, path)

		self.mod_image_id = texture_id

		return texture_id
	else
		BLT:Log(LogLevel.WARN, string.format("Mod image '%s' does not exist", tostring(self:GetModImagePath())))
		return nil
	end
end

function BLTMod:HasUpdates()
	return table.size(self:GetUpdates()) > 0
end

function BLTMod:GetUpdates()
	return self.updates or {}
end

function BLTMod:GetUpdate(id)
	for _, update in ipairs(self:GetUpdates()) do
		if update:GetId() == id then
			return update
		end
	end
end

function BLTMod:HasLegacyUpdate(id)
	return self._legacy_updates[id]
end

function BLTMod:AreUpdatesEnabled()
	for _, update in ipairs(self:GetUpdates()) do
		if not update:IsEnabled() then
			return false
		end
	end
	return true
end

function BLTMod:SetUpdatesEnabled(enable)
	for _, update in ipairs(self:GetUpdates()) do
		update:SetEnabled(enable)
	end
end

function BLTMod:CheckForUpdates(clbk)
	self._update_cache = self._update_cache or {}
	self._update_cache.clbk = clbk

	for _, update in ipairs(self:GetUpdates()) do
		update:CheckForUpdates(callback(self, self, "clbk_check_for_updates"))
	end
end

function BLTMod:IsCheckingForUpdates()
	for _, update in ipairs(self.updates) do
		if update:IsCheckingForUpdates() then
			return true
		end
	end
	return false
end

function BLTMod:GetUpdateError()
	for _, update in ipairs(self:GetUpdates()) do
		if update:GetError() then
			return update:GetError(), update
		end
	end
	return false
end

function BLTMod:clbk_check_for_updates(update, required, reason)
	self._update_cache = self._update_cache or {}
	self._update_cache[update:GetId()] = {
		requires_update = required,
		reason = reason,
		update = update
	}

	if self._update_cache.clbk and not self:IsCheckingForUpdates() then
		local clbk = self._update_cache.clbk
		self._update_cache.clbk = nil
		clbk(self._update_cache)
	end
end

function BLTMod:IsSafeModeEnabled()
	return self.safe_mode
end

function BLTMod:SetSafeModeEnabled(enabled)
	if enabled == nil then
		enabled = true
	end
	if self:DisableSafeMode() then
		enabled = false
	end
	self.safe_mode = enabled
end

function BLTMod:DisableSafeMode()
	if self:IsUndisablable() then
		return true
	end
	return self.disable_safe_mode
end

function BLTMod:IsUndisablable()
	return self.id == "base" or self.undisablable or false
end

function BLTMod:HasDependencies()
	return next(self.dependencies) and true or false
end

function BLTMod:GetDependencies()
	return self.dependencies or {}
end

function BLTMod:GetMissingDependencies()
	return self.missing_dependencies or {}
end

function BLTMod:GetDisabledDependencies()
	return self.disabled_dependencies or {}
end

function BLTMod:AreDependenciesInstalled()
	local installed = true
	self.missing_dependencies = {}
	self.disabled_dependencies = {}

	-- Iterate all mods and updates to find dependencies, store any that are missing
	for id, data in pairs(self:GetDependencies()) do
		local found = false
		for _, mod in ipairs(BLT.Mods:Mods()) do
			if mod:GetName() == id then
				found = true
			elseif mod:HasLegacyUpdate(id) then
				found = true
			else
				for _, update in ipairs(mod:GetUpdates()) do
					if update:GetId() == id then
						found = true
						break
					end
				end
			end

			if found then
				if not mod:IsEnabled() then
					installed = false
					table.insert(self.disabled_dependencies, mod)
					table.insert(self._errors, "blt_mod_dependency_disabled")
				end
				break
			end
		end

		if not found then
			installed = false
			local download_data = type(data) == "table" and data or { download_url = data }
			local new_dependency, valid = BLTModDependency:new(self, id, download_data)
			if valid then
				table.insert(self.missing_dependencies, new_dependency)
			else
				BLT:Log(LogLevel.ERROR, string.format("Invalid dependency '%s' for mod '%s'", id, self:GetName()))
			end
		end
	end

	return installed
end

function BLTMod:RetrieveDependencies()
	for _, dependency in ipairs(self:GetMissingDependencies()) do
		dependency:Retrieve(function(dependency, exists_on_server)
			self:clbk_retrieve_dependency(dependency, exists_on_server)
		end)
	end
end

function BLTMod:clbk_retrieve_dependency(dependency, exists_on_server)
	-- Register the dependency as a download
	if exists_on_server then
		BLT.Downloads:add_pending_download(dependency)
	end
end

function BLTMod:GetDeveloperInfo()
	local str = ""
	local append = function(...)
		for i, s in ipairs({...}) do
			str = str .. (i > 1 and " " or "") .. tostring(s)
		end
		str = str .. "\n"
	end

	local hooks = self:GetHooks() or {}
	local prehooks = self:GetPreHooks() or {}
	local persists = self:GetPersistScripts() or {}

	append("Path:", self:GetPath())
	append("Load Priority:", self:GetPriority())
	append("Version:", self:GetVersion())
	append("BLT-Version:", self:GetBLTVersion())
	append("Disablable:", not self:IsUndisablable())
	append("Allow Safe Mode:", not self:DisableSafeMode())

	if table.size(hooks) < 1 then
		append("No Hooks")
	else
		append("Hooks:")
		for _, hook in ipairs(hooks) do
			append("   ", tostring(hook))
		end
	end

	if table.size(prehooks) < 1 then
		append("No Pre-Hooks")
	else
		append("Pre-Hooks:")
		for _, hook in ipairs(prehooks) do
			append("   ", tostring(hook))
		end
	end

	if table.size(persists) < 1 then
		append("No Persisent Scripts")
	else
		append("Persisent Scripts:")
		for _, script in ipairs(persists) do
			append("   ", script.global, "->", script.file)
		end
	end

	return str
end

function BLTMod:GetSuperMod()
	return self.supermod
end

function BLTMod:IsLibrary()
	return self.library
end

function BLTMod:__tostring()
	return string.format("[BLTMod %s (%s)]", self:GetName(), self:GetId())
end
