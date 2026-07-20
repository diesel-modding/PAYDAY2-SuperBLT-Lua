if not _G then
	return
end

local _G = _G
local io = io
local file = file

_G.LogLevel = {
	NONE = 0,
	ERROR = 1,
	WARN = 2,
	INFO = 3,
	ALL = 4
}

_G.BLT = {
	version = 2.0,
	Base = {},
	_PATH = "mods/base/"
}

function BLT:Require(path)
	dofile(BLT._PATH .. path .. ".lua")
end

BLT:Require("req/utils/UtilsClass")
BLT:Require("req/utils/UtilsCore")
BLT:Require("req/utils/UtilsIO")
BLT:Require("req/utils/json-1.0")
BLT:Require("req/utils/json")
BLT:Require("req/core/Hooks")
BLT:Require("req/supermod/BLTSuperMod")
BLT:Require("req/BLTMod")
BLT:Require("req/BLTUpdate")
BLT:Require("req/BLTUpdateCallbacks")
BLT:Require("req/BLTModDependency")
BLT:Require("req/BLTModule")
BLT:Require("req/BLTLogs")
BLT:Require("req/BLTModManager")
BLT:Require("req/BLTDownloadManager")
BLT:Require("req/BLTLocalization")
BLT:Require("req/BLTNotificationsManager")
BLT:Require("req/BLTPersistScripts")
BLT:Require("req/BLTKeybindsManager")
BLT:Require("req/BLTAssetManager")
BLT:Require("req/xaudio/XAudio")

local log_level_prefix = {
	[LogLevel.ERROR] = "[ERROR]",
	[LogLevel.WARN] = "[WARN]",
	[LogLevel.INFO] = "[INFO]"
}

---Writes a message to the log file
---Multiple arguments can be passed to the function and will be concatenated
---@param level integer @The log level of the message
---@param ... any @The message to log
function BLT:Log(level, ...)
	if level > BLTLogs.log_level then
		return
	end

	local out = { log_level_prefix[level] or "", ... }
	local n = select("#", ...) -- allow nil holes
	-- skip prefix, allow for n=0
	for i = 2, n + 1, 1 do
		out[i] = tostring(out[i])
	end
	log(table.concat(out, " "))
end

function BLT:DeprecationWarning(name, level)
	local info = debug.getinfo(level or 3, "Sl")
	BLT:Log(LogLevel.WARN, string.format("%s is deprecated and will be removed in a future version of SuperBLT (%s:%s)", name, info.source, info.currentline))
end

-- BLT base functions
function BLT:Initialize()
	-- Create hook tables
	self.hook_tables = {
		pre = {},
		post = {},
		wildcards = {}
	}

	-- Override require and setup self
	self:OverrideRequire()

	self:Setup()
end

function BLT:IsVr()
	return _G.SystemInfo ~= nil and getmetatable(_G.SystemInfo).is_vr ~= nil and SystemInfo:is_vr()
end

function BLT:Setup()
	-- Load saved data
	if BLT:IsVr() then
		local save_file = BLTModManager.Constants:ModManagerSaveFile(true)
		self.save_data = io.file_is_readable(save_file) and io.load_as_json(save_file)
	end

	if not self.save_data then
		local save_file = BLTModManager.Constants:ModManagerSaveFile(false)
		self.save_data = io.file_is_readable(save_file) and io.load_as_json(save_file) or {}
	end

	-- Setup modules
	self.Logs = BLTLogs:new()
	self.Mods = BLTModManager:new()
	self.Downloads = BLTDownloadManager:new()
	self.Keybinds = BLTKeybindsManager:new()
	self.PersistScripts = BLTPersistScripts:new()
	self.Localization = BLTLocalization:new()
	self.Notifications = BLTNotificationsManager:new()
	self.AssetManager = BLTAssetManager:new()

	-- Create the required base directories, if necessary
	self:CheckDirectory(BLTModManager.Constants:DownloadsDirectory())
	self:CheckDirectory(BLTModManager.Constants:LogsDirectory())
	self:CheckDirectory(BLTModManager.Constants:SavesDirectory())

	-- Initialization functions
	self.Logs:CleanLogs()
	self.Mods:SetModsList(self:ProcessModsList(self:FindMods()))

	-- Some backwards compatibility for v1 mods
	local C = self.Mods.Constants
	_G.LuaModManager = {}
	_G.LuaModManager.Constants = C
	_G.LuaModManager.Mods = {} -- No mods are available via old api
	rawset(_G, C.logs_path_global, C.mods_directory .. C.logs_directory)
	rawset(_G, C.save_path_global, C.mods_directory .. C.saves_directory)
end

---Returns the version of BLT
---@return string @The version of BLT
function BLT:GetVersion()
	return self.version
end

---Returns the operating system that the game is running on
---@return '"windows"'|'"linux"' @The operating system
function BLT:GetOS()
	local info = blt.blt_info()
	if not info then
		return "windows"
	end
	return info.platform == "mswindows" and "windows" or "linux"
end

function BLT:RunHookTable(hooks_table, path)
	if not hooks_table or not hooks_table[path] then
		return false
	end
	for i, hook_data in pairs(hooks_table[path]) do
		self:RunHookFile(path, hook_data)
	end
end

function BLT:SetModGlobals(mod)
	rawset(_G, BLTModManager.Constants.mod_path_global, mod and mod:GetPath() or false)
	rawset(_G, BLTModManager.Constants.mod_instance_global, mod or false)
end

function BLT:RunHookFile(path, hook_data)
	rawset(_G, BLTModManager.Constants.required_script_global, path or false)
	self:SetModGlobals(hook_data.mod)
	dofile(hook_data.mod:GetPath() .. hook_data.script)
end

function BLT:OverrideRequire()
	if self.require then
		return false
	end

	-- Cache original require function
	self.require = _G.require

	-- Override require function to run hooks
	_G.require = function(...)
		local args = { ... }
		local path = args[1]
		local path_lower = path:lower()
		local require_result = nil

		rawset(_G, BLTModManager.Constants.required_script_type_global, "PreHook")
		self:RunHookTable(self.hook_tables.pre, path_lower)
		require_result = self.require(...)
		rawset(_G, BLTModManager.Constants.required_script_type_global, "PostHook")
		self:RunHookTable(self.hook_tables.post, path_lower)

		for k, v in ipairs(self.hook_tables.wildcards) do
			self:RunHookFile(path, v)
		end

		return require_result
	end
end

function BLT:FindMods()
	-- Get all folders in mods directory
	local mods_list = {}
	local mods_directory = BLTModManager.Constants.mods_directory
	local folders = file.GetDirectories(mods_directory)

	-- If we didn't get any folders then return an empty mods list
	if not folders then
		return {}
	end

	for _, directory in pairs(folders) do
		if not self.Mods:IsExcludedDirectory(directory) then
			-- Attempt to create a BLT mod from the mod path
			local mod_path = mods_directory .. directory .. "/"
			local new_mod, valid = BLTMod:new(directory, nil, mod_path)
			if valid then
				table.insert(mods_list, new_mod)
			else
				self:Log(LogLevel.WARN, string.format("[BLT] Could not read or find a valid mod definition in %s", mod_path))
			end
		end
	end

	return mods_list
end

function BLT:ProcessModsList(mods_list)
	-- Prioritize mod load order
	table.sort(mods_list, function(a, b)
		return a:GetPriority() > b:GetPriority()
	end)

	return mods_list
end

function BLT:CheckDirectory(path)
	path = path:sub(1, #path - 1)
	if not file.DirectoryExists(path) then
		self:Log(LogLevel.INFO, "[BLT] Creating missing directory " .. path)
		file.CreateDirectory(path)
	end
end

-- Perform startup
BLT:Initialize()
