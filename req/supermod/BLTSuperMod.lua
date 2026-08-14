---@class BLTSuperMod
---@field new fun(self, mod: BLTMod, xml: table):BLTSuperMod
BLTSuperMod = blt_class()

BLT:Require("req/supermod/SuperModAssetLoader")

function BLTSuperMod.try_load(mod, file_name)
	local supermod_path = mod:GetPath() .. (file_name or "supermod.xml")

	-- Attempt to read the mod defintion file
	local file = io.open(supermod_path)
	if file then

		-- Read the file contents
		local file_contents = file:read("*all")
		file:close()

		-- Parse it
		local xml = blt.parsexml(file_contents)
		if not xml then
			return
		end

		xml._doc = {
			filename = supermod_path
		}

		return BLTSuperMod:new(mod, xml)
	end
end

---@param mod BLTMod
---@param xml table
function BLTSuperMod:init(mod, xml)
	self._mod = mod
	self._setup_callbacks = {}

	self:_replace_includes(xml)

	self:_load_xml(xml, {})
end

function BLTSuperMod:Setup()
	for _, func in pairs(self._setup_callbacks) do
		func()
	end
end

function BLTSuperMod:GetAssetLoader()
	return self._assets
end

function BLTSuperMod:_load_xml(xml, parent_scope)
	-- Handle params of the main XML node
	local mapping_func = {
		priority = self._convert_to_number,
		disable_safe_mode = self._convert_to_boolean,
		undisablable = self._convert_to_boolean,
		library = self._convert_to_boolean,
		vr_disabled = self._convert_to_boolean,
		desktop_disabled = self._convert_to_boolean,
		needs_restart = self._convert_to_boolean
	}

	for k, v in pairs(xml.params) do
		if mapping_func[k] then
			v = mapping_func[k](v)
		end
		self._mod.raw_data[k] = v
	end

	BLTSuperMod._recurse_xml(xml, parent_scope, {
		dependencies = function(tag, scope) self:_add_dependencies(tag, scope) end,
		dependency = function(tag, scope) self:_add_dependency(tag, scope) end,
		updates = function(tag, scope) self:_add_updates(tag, scope) end,
		update = function(tag, scope) self:_add_update(tag, scope) end,
		keybinds = function(tag, scope) self:_add_keybinds(tag, scope) end,
		keybind = function(tag, scope) self:_add_keybind(tag, scope) end,
		assets = function(tag, scope) self:_add_assets(tag, scope) end,
		hooks = function(tag, scope) self:_add_hooks(tag, scope) end,
		native_modules = function(tag, scope) self:_add_native_modules(tag, scope) end,
		native_module = function(tag, scope) self:_add_native_module(tag, scope) end,
		-- These tags are used by the Wren-based XML Tweaker
		wren = function(tag, scope)
			self._mod.needs_restart = self._mod.needs_restart == nil and true or self._mod.needs_restart
		end,
		tweak = function(tag, scope)
			self._mod.needs_restart = self._mod.needs_restart == nil and true or self._mod.needs_restart
		end
	})
end

function BLTSuperMod:_add_dependencies(xml, parent_scope)
	BLTSuperMod._recurse_xml(xml, parent_scope, {
		dependency = function(tag, scope) self:_add_dependency(tag, scope) end
	})
end

function BLTSuperMod:_add_dependency(tag, scope)
	if not scope.identifier then
		BLT:Log(LogLevel.ERROR, string.format("[BLT] Invalid dependency definition in mod %s", self._mod:GetName()))
		return
	end

	self._mod.raw_data.dependencies = self._mod.raw_data.dependencies or {}
	self._mod.raw_data.dependencies[scope.identifier] = scope
end

function BLTSuperMod:_add_updates(xml, parent_scope)
	BLTSuperMod._recurse_xml(xml, parent_scope, {
		update = function(tag, scope) self:_add_update(tag, scope) end
	})
end

function BLTSuperMod:_add_update(tag, scope)
	local mapping_func = {
		disallow_update = self._convert_to_boolean,
		hash_file = self._convert_to_boolean,
		critical = self._convert_to_boolean
	}
	local update_data = {}
	for k, v in pairs(scope) do
		if mapping_func[k] then
			v = mapping_func[k](v)
		end
		update_data[k] = v
	end

	self._mod.raw_data.updates = self._mod.raw_data.updates or {}
	table.insert(self._mod.raw_data.updates, update_data)
end

function BLTSuperMod:_add_keybinds(xml, parent_scope)
	BLTSuperMod._recurse_xml(xml, parent_scope, {
		keybind = function(tag, scope) self:_add_keybind(tag, scope) end
	})
end

function BLTSuperMod:_add_keybind(tag, scope)
	local mapping_func = {
		run_in_menu = self._convert_to_boolean,
		run_in_game = self._convert_to_boolean,
		show_in_menu = self._convert_to_boolean,
		localized = self._convert_to_boolean
	}
	local keybind_data = {}
	for k, v in pairs(scope) do
		if mapping_func[k] then
			v = mapping_func[k](v)
		end
		keybind_data[k] = v
	end

	self._mod.raw_data.keybinds = self._mod.raw_data.keybinds or {}
	table.insert(self._mod.raw_data.keybinds, keybind_data)
end

function BLTSuperMod:_add_assets(tag, scope)
	self._mod.raw_data.needs_restart = self._mod.raw_data.needs_restart == nil and true or self._mod.raw_data.needs_restart

	table.insert(self._setup_callbacks, function()
		if not self._mod:IsEnabled() then
			return
		end

		if not self._assets then
			self._assets = self.AssetLoader:new(self)
		end

		self._assets:FromXML(tag, scope)
	end)
end

function BLTSuperMod:_add_hooks(xml, parent_scope)
	BLTSuperMod._recurse_xml(xml, parent_scope, {
		pre = function(tag, scope) self:_add_hook(tag, scope, "pre_hooks") end,
		post = function(tag, scope) self:_add_hook(tag, scope, "hooks") end,
		entry = function(tag, scope) self:_add_entry_script(tag, scope) end,
		persist = function(tag, scope) self:_add_persist_script(tag, scope) end
	})
end

function BLTSuperMod:_add_hook(tag, scope, data_key)
	if not scope.hook_id or not scope.script_path then
		BLT:Log(LogLevel.ERROR, string.format("[BLT] Invalid hook definition in mod %s", self._mod:GetName()))
		return
	end

	self._mod.raw_data[data_key] = self._mod.raw_data[data_key] or {}
	table.insert(self._mod.raw_data[data_key], scope)
end

function BLTSuperMod:_add_entry_script(tag, scope)
	self._mod.raw_data.entry_scripts = self._mod.raw_data.entry_scripts or {}
	table.insert(self._mod.raw_data.entry_scripts, scope)
end

function BLTSuperMod:_add_persist_script(tag, scope)
	self._mod.raw_data.persist_scripts = self._mod.raw_data.persist_scripts or {}
	table.insert(self._mod.raw_data.persist_scripts, scope)
end

function BLTSuperMod:_add_native_modules(xml, parent_scope)
	BLTSuperMod._recurse_xml(xml, parent_scope, {
		native_module = function(tag, scope) self:_add_native_module(tag, scope) end
	})
end

function BLTSuperMod:_add_native_module(tag, scope)
	self._mod.raw_data.native_modules = self._mod.raw_data.native_modules or {}
	table.insert(self._mod.raw_data.native_modules, scope)
end

function BLTSuperMod:_replace_includes(xml)
	for i, tag in ipairs(xml) do
		tag._doc = xml._doc

		if tag.name == ":include" then
			local file_path = self._mod:GetPath() .. tag.params.src

			-- Attempt to read the mod defintion file
			local file = io.open(file_path)
			assert(file, "Could not open " .. file_path)

			-- Read the file contents
			local file_contents = file:read("*all")
			file:close()

			-- Parse it
			local included = blt.parsexml(file_contents)
			if included then
				included._doc = {
					filename = file_path
				}

				-- Substitute it in
				tag = included
				xml[i] = included
			end
		end

		self:_replace_includes(tag)
	end
end

function BLTSuperMod._recurse_xml(xml, parent_scope, callbacks)
	for _, tag in ipairs(xml) do
		local scope = {}
		setmetatable(scope, { __index = parent_scope })

		for name, val in pairs(tag.params) do
			while true do
				local first, last = val:find("#{%a[%w_]-}")
				if not first then break end

				local name = val:sub(first + 2, last - first)
				local target_var = scope[name]

				assert(target_var, "Trying to use missing parameter '" .. name .. "' as a #{value} in " .. tag._doc.filename)

				val = val:sub(1, first - 1) .. target_var .. val:sub(last + 1)
			end

			if name:sub(1, 1) == ":" then
				name = name:sub(2)
				if not scope[name] then
					BLT:Log(LogLevel.WARN, "Trying to append to missing parameter '" .. name .. "' in " .. tag._doc.filename)
				end
				scope[name] = scope[name] .. val
			else
				scope[name] = val
			end
		end

		if tag.name == "group" then
			BLTSuperMod._recurse_xml(tag, scope, callbacks)
		elseif callbacks[tag.name] then
			callbacks[tag.name](tag, scope, callbacks)
		else
			BLT:Log(LogLevel.WARN, "Unknown tag name '" .. tag.name .. "' in: " .. tag._doc.filename)
		end
	end
end

function BLTSuperMod._convert_to_boolean(val)
	if val then
		return tostring(val):lower() == "true"
	end
end

function BLTSuperMod._convert_to_number(val)
	return tonumber(val)
end
