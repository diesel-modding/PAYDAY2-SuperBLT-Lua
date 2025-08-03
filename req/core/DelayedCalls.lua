DelayedCalls = DelayedCalls or {}
DelayedCalls._calls = DelayedCalls._calls or {}
DelayedCalls._remove_queue = DelayedCalls._remove_queue or {}

Hooks:Add("MenuUpdate", "MenuUpdate_Queue", function(t, dt)
	DelayedCalls:Update(t, dt)
end)

Hooks:Add("GameSetupUpdate", "GameSetupUpdate_Queue", function(t, dt)
	DelayedCalls:Update(t, dt)
end)

function DelayedCalls:Update(t, dt)
	local calls = self._calls
	self._calls = {}

	for k, v in pairs(calls) do
		if self._remove_queue[k] then
			self._remove_queue[k] = nil
		elseif t >= v.executeTime then
			v.functionCall()
		else
			self._calls[k] = self._calls[k] or v
		end
	end
end

---Adds a function to be automatically called after a set delay  
---If a call with the same id already exists, it will be replaced
---@param id string @Unique name for this delayed call
---@param time number @Time in seconds to call the specified function after
---@param func function @Function to call after the time runs out
function DelayedCalls:Add(id, time, func)
	if not id or type(time) ~= "number" or type(func) ~= "function" then
		BLT:Log(LogLevel.ERROR, string.format("[DelayedCalls] Could not add call '%s'", id))
		return
	end

	self._remove_queue[id] = nil
	self._calls[id] = {
		functionCall = func,
		executeTime = Application:time() + time
	}
end

---Removes a scheduled call that hasn't been called yet
---@param id string @Name of the delayed call to remove
function DelayedCalls:Remove(id)
	self._remove_queue[id] = true
end
