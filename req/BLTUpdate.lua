---@class BLTUpdate
---@field new fun(self, parent_mod: BLTMod, data: table):BLTUpdate, boolean
BLTUpdate = blt_class()
BLTUpdate.enabled = true
BLTUpdate.revision = 1
 -- These should be moved into their own classes ideally to encapsulate their functionality
BLTUpdate.providers = {
	mws = {
		get_url = function(self, type) return self[type] and string.format(self[type], self.id) or nil end,
		meta = "https://api.modworkshop.net/mods/%s/version",
		download = "https://api.modworkshop.net/mods/%s/download",
		patchnotes = "https://modworkshop.net/mod/%s?tab=changelog",
		clbk_func = "clbk_got_update_data_version"
	},
	default = {
		get_url = function(self, type) return self[type] end,
		clbk_func = "clbk_got_update_data_default"
	}
}

function BLTUpdate:init(parent_mod, data)
	if not parent_mod or not data or not data.identifier then
		return false
	end

	self.parent_mod = parent_mod
	self.id = data.identifier
	self.name = data.display_name or parent_mod:GetName()
	self.dir = data.install_dir or parent_mod:GetDir()
	self.folder = data.install_folder or parent_mod:GetId()
	self.disallow_update = data.disallow_update or false
	self.hash_file = data.hash_file or false
	self.critical = data.critical or false
	self.present_func = data.present_func

	-- Set up provider from legacy host data
	local provider_data = data.host or {}
	local provider_name = provider_data.provider or data.provider or "default"
	provider_data.id = self.id
	provider_data.meta = provider_data.meta or data.meta
	provider_data.download = provider_data.download or data.download
	provider_data.patchnotes = provider_data.patchnotes or data.patchnotes

	local provider = BLTUpdate.providers[provider_name]
	if not provider then
		BLT:Log(LogLevel.ERROR, string.format("[Updates] Invalid update provider '%s' for '%s' (%s)", provider_name, self.id, self.name))
		return false
	end

	self.provider = setmetatable(provider_data, { __index = provider })

	if not self.provider:get_url("meta") then
		BLT:Log(LogLevel.ERROR, string.format("[Updates] Missing meta for '%s' (%s)", provider_name, self.id, self.name))
		return false
	end

	return true
end

function BLTUpdate:__tostring()
	return string.format("[BLTUpdate %s (%s)]", self:GetName(), self:GetId())
end

function BLTUpdate:IsEnabled()
	return self.enabled
end

function BLTUpdate:SetEnabled(enable)
	self.enabled = enable
end

function BLTUpdate:RequiresUpdate()
	return self._requires_update
end

function BLTUpdate:CheckForUpdates(finished_clbk)
	self._requesting_updates = true

	dohttpreq(self.provider:get_url("meta"), function(data, http_id, request_info)
		self._requesting_updates = false

		if not request_info.querySucceeded or string.is_nil_or_empty(data) then
			BLT:Log(LogLevel.WARN, string.format("[Updates] Could not retrieve update data for '%s' (%s)", self.id, self.name))
			self._error = "Could not retrieve update data."
			return self:_run_update_callback(finished_clbk, false, self._error)
		end

		BLT:Log(LogLevel.INFO, string.format("[Updates] Received update data for '%s' (%s)", self.id, self.name))

		return self[self.provider.clbk_func](self, finished_clbk, data)
	end)
end

function BLTUpdate:clbk_got_update_data_version(finished_clbk, version)
	self._server_version = version
	self._uses_hash = false
	self._update_data = {
		download_url = self.provider:get_url("download"),
		patchnotes_url = self.provider:get_url("patchnotes")
	}

	return self:_run_update_callback(finished_clbk, self.parent_mod.version ~= version)
end

function BLTUpdate:clbk_got_update_data_default(finished_clbk, json_data)
	local server_data = json.decode(json_data)

	for _, data in pairs(server_data or {}) do
		if data.ident == self:GetId() then
			self._update_data = data
			if data.hash then -- Use hash to check
				self._server_hash = data.hash
				self._uses_hash = true
			elseif data.version then -- Use version
				self._server_version = data.version
				self._uses_hash = false
				return self:_run_update_callback(finished_clbk, self.parent_mod.version ~= data.version) -- Request an update if the versions don't equal.
			end

			local dat = { data, finished_clbk }
			local hash_result = self:GetHash(callback(self, self, "_check_hash", dat))

			-- Nil indicates the file to hash was missing
			-- True indicates our callback will be run at a later date
			-- A string is the hashed value
			if not hash_result then
				-- Errored, file does not exist
				self._error = "File to be version checked is missing."
				BLT:Log(LogLevel.ERROR, string.format("[Updates] File to be version checked is missing for '%s' (%s)", self.id, self.name))
				return self:_run_update_callback(finished_clbk, false, self._error)
			elseif hash_result ~= true then
				-- Manually check the hash, since we're running on an old
				-- version of the DLL that doesn't support the callbacks
				return self:_check_hash(dat, hash_result)
			else
				-- At this point we've started the hash callback
				-- Keep 'Checking for Updates' until the hash is complete
				-- as this is set to false above in the check_hash callback
				self._requesting_updates = true
				return
			end
		end
	end

	self._error = "No valid mod ID was returned by the server."
	BLT:Log(LogLevel.ERROR, string.format("[Updates] Invalid or corrupt update data for '%s' (%s)", self.id, self.name))
	return self:_run_update_callback(finished_clbk, false, self._error)
end

function BLTUpdate:_check_hash(dat, local_hash)
	local data, finished_clbk = unpack(dat)

	self._requesting_updates = false

	BLT:Log(LogLevel.INFO, string.format("[Updates] Comparing hash data for '%s':\nServer: %s\n Local: %s", data.ident, data.hash, local_hash))
	if not data.hash then
		BLT:Log(LogLevel.WARN, string.format("[Updates] [WARN] Missing server hash for mod '%s'", data.ident))
		return self:_run_update_callback(finished_clbk, false)
	end

	if data.hash == local_hash then
		return self:_run_update_callback(finished_clbk, false)
	end

	return self:_run_update_callback(finished_clbk, true)
end

function BLTUpdate:_run_update_callback(finished_clbk, requires_update, error_reason)
	self._requires_update = requires_update
	finished_clbk(self, requires_update, error_reason)
	return requires_update
end

function BLTUpdate:IsCheckingForUpdates()
	return self._requesting_updates or false
end

function BLTUpdate:GetParentMod()
	return self.parent_mod
end

function BLTUpdate:GetId()
	return self.id
end

function BLTUpdate:GetName()
	return self.name
end

function BLTUpdate:GetHash(callback)
	if self.hash_file then
		return file.FileExists(self.hash_file) and file.FileHash(self.hash_file, callback) or nil
	else
		local directory = Application:nice_path(self:GetInstallDirectory() .. "/" .. self:GetInstallFolder(), true)
		return file.DirectoryExists(directory) and file.DirectoryHash(directory, callback) or nil
	end
end

function BLTUpdate:GetServerHash()
	return self._server_hash
end

function BLTUpdate:GetServerVersion()
	return self._server_version
end

function BLTUpdate:UsesHash()
	return self._uses_hash
end

function BLTUpdate:GetInstallDirectory()
	return self.dir
end

function BLTUpdate:GetInstallFolder()
	return self.folder
end

function BLTUpdate:DisallowsUpdate()
	return self.disallow_update ~= false
end

function BLTUpdate:GetDisallowCallback()
	return self.disallow_update
end

function BLTUpdate:GetPatchNotes()
	return self._update_data and self._update_data.patchnotes_url or self.provider:get_url("patchnotes")
end

function BLTUpdate:IsCritical()
	return self.critical
end

function BLTUpdate:ViewPatchNotes()
	local url = self:GetPatchNotes()
	if managers.network and managers.network.account and managers.network.account:is_overlay_enabled() then
		managers.network.account:overlay_activate("url", url)
	else
		os.execute("cmd /c start " .. url)
	end
end

function BLTUpdate:GetDownloadURL()
	return self._update_data and self._update_data.download_url or self.provider:get_url("download")
end

function BLTUpdate:GetUpdateMiscData()
	if not self._update_data then
		return nil
	end

	return self._update_data.misc_data
end

function BLTUpdate:IsInstall()
	return false
end

function BLTUpdate:IsPresent()
	if self.present_func then
		return BLTUpdateCallbacks[self.present_func](self)
	end

	return true
end

function BLTUpdate:GetError()
	return self._error
end
