---@class BLTNotificationsManager : BLTModule
---@field new fun(self):BLTNotificationsManager
BLTNotificationsManager = BLTNotificationsManager or blt_class(BLTModule)
BLTNotificationsManager.__type = "BLTNotificationsManager"

function BLTNotificationsManager:init()
	BLTNotificationsManager.super.init(self)

	self._notifications = {}
	self._uid = 1000
end

function BLTNotificationsManager:_get_uid()
	local uid = self._uid
	self._uid = uid + 1
	return uid
end

function BLTNotificationsManager:_get_notification(uid)
	for i, data in ipairs(self._notifications) do
		if data.id == uid then
			return self._notifications[i], i
		end
	end
	return nil, -1
end

---@class notification_data
---@field title string? @Title of the notification, defaults to `"No Title"`
---@field text string? @Text of the notification, defaults to `""`
---@field icon string? @Texture to use as an icon for the notification
---@field icon_texture_rect { x: number, y: number, w: number, h: number }? @Part of the texture to use as icon, defaults to the full texture
---@field color Color? @Color of the notification, currently unused
---@field priority number? @Priority of the notification, defaults to the order it's created in
---@field callback fun(uid: number)? @Function that is called when the notification is clicked, defaults to opening the mod manager

---Gets the ordered table of all notifications currently being displayed
---@return notification_data[] @Table containing notification data
function BLTNotificationsManager:get_notifications()
	return self._notifications
end

---Adds a notification to the manager, and shows it on the notifications UI
---@param parameters notification_data @Table containing data for the notification
---@return number @ID of the added notification
function BLTNotificationsManager:add_notification(parameters)
	-- Create and store the notification
	local id = self:_get_uid()
	local data = {
		id = id,
		title = parameters.title or "No Title",
		text = parameters.text or "",
		icon = parameters.icon,
		icon_texture_rect = parameters.icon_texture_rect,
		color = parameters.color,
		priority = parameters.priority or (id * -1),
		callback = parameters.callback
	}
	table.insert(self._notifications, data)

	-- Add the notification immediately if the gui is visible
	local notifications = managers.menu_component and managers.menu_component:blt_notifications_gui()
	if notifications then
		notifications:add_notification(data)
	end

	return data.id
end

---Removes the notification with the specified ID
---@param uid number @ID of the notification that should be removed
function BLTNotificationsManager:remove_notification(uid)
	-- Remove the notification
	local _, idx = self:_get_notification(uid)
	if idx > 0 then
		table.remove(self._notifications, idx)

		-- Update the ui
		local notifications = managers.menu_component:blt_notifications_gui()
		if notifications then
			notifications:remove_notification(uid)
		end
	end
end

---@diagnostic disable: deprecated
---@deprecated @Use `BLT.Notifications` instead
NotificationsManager = NotificationsManager or {}

function NotificationsManager:GetNotifications()
	BLT:DeprecationWarning("NotificationsManager.GetNotifications")
	return BLT.Notifications:get_notifications()
end

function NotificationsManager:GetCurrentNotification()
	BLT:DeprecationWarning("NotificationsManager.GetCurrentNotification")
	return BLT.Notifications:get_notifications()[1]
end

function NotificationsManager:GetCurrentNotificationIndex()
	BLT:DeprecationWarning("NotificationsManager.GetCurrentNotificationIndex")
	return 1
end

function NotificationsManager:AddNotification(id, title, message, priority, callback)
	BLT:DeprecationWarning("NotificationsManager.AddNotification")
	self._legacy_ids = self._legacy_ids or {}
	local new_id = BLT.Notifications:add_notification({
		title = title,
		text = message,
		priority = priority
	})
	self._legacy_ids[id] = new_id
end

function NotificationsManager:UpdateNotification(id, new_title, new_message, new_priority, new_callback)
	BLT:DeprecationWarning("NotificationsManager.UpdateNotification")
	self._legacy_ids = self._legacy_ids or {}
	self:RemoveNotification(id)
	self:AddNotification(id, new_title, new_message, new_priority, new_callback)
end

function NotificationsManager:RemoveNotification(id)
	BLT:DeprecationWarning("NotificationsManager.RemoveNotification")
	self._legacy_ids = self._legacy_ids or {}
	if self._legacy_ids[id] then
		BLT.Notifications:remove_notification(self._legacy_ids[id])
		self._legacy_ids[id] = nil
	end
end

function NotificationsManager:ClearNotifications()
	BLT:DeprecationWarning("NotificationsManager.ClearNotifications")
	self._legacy_ids = self._legacy_ids or {}
	for id, new_id in pairs(self._legacy_ids) do
		BLT.Notifications:remove_notification(new_id)
	end
end

function NotificationsManager:NotificationExists(id)
	BLT:DeprecationWarning("NotificationsManager.NotificationExists")
	self._legacy_ids = self._legacy_ids or {}
	return self._legacy_ids[id] ~= nil
end

function NotificationsManager:ShowNextNotification(suppress_sound)
	BLT:DeprecationWarning("NotificationsManager.ShowNextNotification")
end

function NotificationsManager:ShowPreviousNotification(suppress_sound)
	BLT:DeprecationWarning("NotificationsManager.ShowPreviousNotification")
end

function NotificationsManager:ClickNotification(suppress_sound)
	BLT:DeprecationWarning("NotificationsManager.ClickNotification")
end

function NotificationsManager:MarkNotificationAsRead(id)
	BLT:DeprecationWarning("NotificationsManager.MarkNotificationAsRead")
end
