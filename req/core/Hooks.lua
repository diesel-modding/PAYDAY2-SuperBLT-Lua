_G.Hooks = Hooks or {}
Hooks._registered_hooks = Hooks._registered_hooks or {}
Hooks._function_hooks = Hooks._function_hooks or {}

---Registers a hook so that functions can be added to it, and later called
---@param key string @Unique hook name
function Hooks:RegisterHook(key)
	self._registered_hooks[key] = self._registered_hooks[key] or {}
end

---Registers a hook so that functions can be added to it, and later called  
---Functionally the same as `Hooks:RegisterHook`
---@param key string @Unique hook name
function Hooks:Register(key)
	self:RegisterHook(key)
end

---Adds a function call to a hook, so that it will be called when the hook is called
---@param key string @Name of the hook to be called on
---@param id string @Unique name for this specific function call
---@param func function @The function to call with the hook
function Hooks:AddHook(key, id, func)
	self._registered_hooks[key] = self._registered_hooks[key] or {}
	-- Update existing hook
	for k, v in pairs(self._registered_hooks[key]) do
		if type(v) == "table" and v.id == id then
			v.func = func
			return
		end
	end
	-- Add new hook, if id doesn't exist
	table.insert(self._registered_hooks[key], {
		id = id,
		func = func
	})
end

---Adds a function call to a hook, so that it will be called when the hook is called  
---Functionally the same as `Hooks:AddHook`
---@param key string @Name of the hook to be called on
---@param id string @Unique name for this specific function call
---@param func function @Function to call with the hook
function Hooks:Add(key, id, func)
	self:AddHook(key, id, func)
end

---Removes a hook, so that it will not call any functions
---@param key string @Name of the hook to remove
function Hooks:UnregisterHook(key)
	self._registered_hooks[key] = nil
end

---Removes a hook, so that it will not call any functions  
---Functionally the same as `Hooks:UnregisterHook`
---@param key string @Name of the hook to remove
function Hooks:Unregister(key)
	self:UnregisterHook(key)
end

---Removes a hooked function call with the specified id to prevent it from being called
---@param id string @Name of the function call to remove
function Hooks:Remove(id)
	for k, v in pairs(self._registered_hooks) do
		if type(v) == "table" then
			for i, tbl in pairs(v) do
				if tbl.id == id then
					table.remove(v, i)
					break
				end
			end
		end
	end
end

---Calls a specified hook, and all of its hooked functions
---@param key string @Name of the hook to call
---@param ... any @Arguments to pass to the hooked functions
function Hooks:Call(key, ...)
	if not self._registered_hooks[key] then
		return
	end

	for k, v in pairs(self._registered_hooks[key]) do
		if type(v) == "table" and type(v.func) == "function" then
			v.func(...)
		end
	end
end

---Calls a specified hook and returns the first non nil value(s) returned by a hooked function
---@param key string @Name of the hook to call
---@param ... any @Arguments to pass to the hooked functions
---@return any ... @The value(s) returned by a hooked function
function Hooks:ReturnCall(key, ...)
	if not self._registered_hooks[key] then
		return
	end

	for k, v in pairs(self._registered_hooks[key]) do
		if type(v) == "table" and type(v.func) == "function" then
			local r = { v.func(...) }
			if next(r) == 1 then
				return unpack(r)
			end
		end
	end
end

---Hooks a function to be called before the specified function on a specified object  
---If `pre_call` returns anything, it will be used if neither the original function nor any hooks coming after this one return anything
---@param object any @Object for the hooked function to be called on
---@param func string @Name of the function on `object` to run `pre_call` before
---@param id string @Unique name for this prehook
---@param pre_call function @Function to be called before `func` on `object`
function Hooks:PreHook(object, func, id, pre_call)
	if not object or type(pre_call) ~= "function" then
		self:_PrePostHookError(func, id)
		return
	end

	if not self:_ChkCreateTableStructure(object, func) then
		for k, v in pairs(self._function_hooks[object][func].overrides.pre) do
			if v.id == id then
				return
			end
		end
	end

	local func_tbl = {
		id = id,
		func = pre_call
	}
	table.insert(self._function_hooks[object][func].overrides.pre, func_tbl)
end

---Removes a prehook and prevents it from being run
---@param id string @Name of the prehook to remove
function Hooks:RemovePreHook(id)
	for object_i, object in pairs(self._function_hooks) do
		for func_i, func in pairs(object) do
			for override_i, override in ipairs(func.overrides.pre) do
				if override.id == id then
					table.remove(func.overrides.pre, override_i)
				end
			end
		end
	end
end

---Hooks a function to be called after the specified function on a specified object  
---If `post_call` returns anything, it will override the return value(s) of the original function and other hooks coming before this one
---@param object any @Object for the hooked function to be called on
---@param func string @Name of the function on `object` to run `post_call` after
---@param id string @Unique name for this posthook
---@param post_call function @Function to be called after `func` on `object`
function Hooks:PostHook(object, func, id, post_call)
	if not object or type(post_call) ~= "function" then
		self:_PrePostHookError(func, id)
		return
	end

	if not self:_ChkCreateTableStructure(object, func) then
		for k, v in pairs(self._function_hooks[object][func].overrides.post) do
			if v.id == id then
				return
			end
		end
	end

	local func_tbl = {
		id = id,
		func = post_call
	}
	table.insert(self._function_hooks[object][func].overrides.post, func_tbl)
end

---Removes a posthook and prevents it from being run
---@param id string @Name of the posthook to remove
function Hooks:RemovePostHook(id)
	for object_i, object in pairs(self._function_hooks) do
		for func_i, func in pairs(object) do
			for override_i, override in ipairs(func.overrides.post) do
				if override.id == id then
					table.remove(func.overrides.post, override_i)
				end
			end
		end
	end
end

---Overrides a function completely while keeping existing hooks to it intact
---@param object any @Object of the function to override
---@param func string @Name of the function on `object` override
---@param override function @Function to replace the original function `func` with
function Hooks:OverrideFunction(object, func, override)
	local hook_data = self._function_hooks[object] and self._function_hooks[object][func]
	if hook_data then
		self._function_hooks[object][func] = nil

		object[func] = override

		self:_ChkCreateTableStructure(object, func)
		self._function_hooks[object][func].overrides = hook_data.overrides
	else
		object[func] = override
	end
end

---Returns the current original function of an object
---@param object any @Object of the function to get
---@param func string @Name of the function on `object` to get
---@return function @Original function `func` of `object`
function Hooks:GetFunction(object, func)
	if not self._function_hooks[object] or not self._function_hooks[object][func] then
		return object[func]
	else
		return self._function_hooks[object][func].original
	end
end

---Returns the return value(s) of the currently running hook
---@return any ... @Any amount of return values of the current hook
function Hooks:GetReturn()
	if self._current_function_hook and self._current_function_hook.returns then
		return unpack(Hooks._current_function_hook.returns)
	end
end

-- Shared function to log hook errors
function Hooks:_PrePostHookError(func, id)
	BLT:Log(LogLevel.ERROR, string.format("[Hooks] Could not hook function '%s' (%s)", tostring(func), tostring(id)))
end

-- Helper to create the hooks table structure and function override
function Hooks:_ChkCreateTableStructure(object, func)
	if self._function_hooks[object] == nil then
		self._function_hooks[object] = {}
	end

	if self._function_hooks[object][func] then
		return
	end

	self._function_hooks[object][func] = {
		original = object[func],
		overrides = {
			pre = {},
			post = {}
		}
	}

	object[func] = function(...)
		local function_hook = self._function_hooks[object][func]
		local hook_return

		-- Call prehooks
		for k, v in ipairs(function_hook.overrides.pre) do
			self._current_function_hook = function_hook
			hook_return = { v.func(...) }
			if next(hook_return) then
				function_hook.returns = hook_return
			end
		end

		-- Call original function
		hook_return = { function_hook.original(...) }
		if next(hook_return) then
			function_hook.returns = hook_return
		end

		-- Call posthooks
		for k, v in ipairs(function_hook.overrides.post) do
			self._current_function_hook = function_hook
			hook_return = { v.func(...) }
			if next(hook_return) then
				function_hook.returns = hook_return
			end
		end

		if function_hook.returns then
			hook_return = function_hook.returns
			function_hook.returns = nil

			return unpack(hook_return)
		end
	end

	return true
end
