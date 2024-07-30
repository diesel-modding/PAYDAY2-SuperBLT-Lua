---@class BLTModProfileGui
---@field new fun(self, ws, panel, x, y):BLTModProfileGui
BLTModProfileGui = BLTModProfileGui or blt_class(MultiProfileItemGui)
BLTModProfileGui.profile_panel_w = 280
BLTModProfileGui.profile_panel_h = tweak_data.menu.pd2_medium_font_size

function BLTModProfileGui:init(ws, panel, x, y)
	self._ws = ws

	self._panel = self._panel or panel:panel({
		w = self.profile_panel_h * 2 + self.profile_panel_w,
		h = self.profile_panel_h
	})

	self._panel:set_center(x, y)

	self._profile_panel = self._panel:panel({
		w = self.profile_panel_w,
		h = self.profile_panel_h
	})

	self._profile_panel:set_center(self._panel:w() / 2, self._panel:h() / 2)

	self._add_profile_icon = self._panel:bitmap({
		texture = "guis/textures/pd2/blackmarket/stat_plusminus",
		texture_rect = { 0, 0, 8, 8 },
		w = self.profile_panel_h * 0.5,
		h = self.profile_panel_h * 0.5,
		color = tweak_data.screen_colors.button_stage_3:with_alpha(1)
	})

	self._add_profile_icon:set_right(self._panel:w() - self.profile_panel_h / 2)
	self._add_profile_icon:set_center_y(self._panel:h() / 2)

	self._delete_profile_icon = self._panel:bitmap({
		texture = "guis/textures/pd2/blackmarket/stat_plusminus",
		texture_rect = { 8, 0, 8, 8 },
		w = self.profile_panel_h * 0.5,
		h = self.profile_panel_h * 0.5,
		color = tweak_data.screen_colors.button_stage_3:with_alpha(1)
	})

	self._delete_profile_icon:set_left(self.profile_panel_h / 2)
	self._delete_profile_icon:set_center_y(self._panel:h() / 2)

	self._box_panel = self._panel:panel()

	self._box_panel:rect({
		layer = -100,
		color = Color.black:with_alpha(0.25)
	})

	self._box = BoxGuiObject:new(self._box_panel, {
		sides = {
			1,
			1,
			1,
			1
		}
	})
	self._caret = self._profile_panel:rect({
		blend_mode = "add",
		name = "caret",
		h = 0,
		y = 0,
		w = 0,
		x = 0,
		color = Color(0.1, 1, 1, 1)
	})
	self._max_length = 20
	self._name_editing_enabled = true

	self._name_text = self._profile_panel:text({
		name = "name",
		vertical = "center",
		align = "center",
		text = BLT.Mods:ProfileName(),
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = tweak_data.screen_colors.button_stage_3,
		w = self._profile_panel:w() - 64
	})

	self._name_text:set_center_x(self._profile_panel:w() * 0.5)

	if managers.menu:is_pc_controller() and not managers.menu:is_steam_controller() then
		self._arrow_left = self._profile_panel:bitmap({
			texture = "guis/textures/menu_arrows",
			name = "self._arrow_left",
			texture_rect = {
				24,
				0,
				24,
				24
			},
			color = tweak_data.screen_colors.button_stage_3
		})
	else
		self._arrow_left = self._profile_panel:text({
			name = "self._arrow_left",
			h = 24,
			vertical = "center",
			w = 24,
			align = "center",
			text = managers.menu:is_steam_controller() and managers.localization:steam_btn("trigger_l") or managers.localization:get_default_macro("BTN_TOP_L"),
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size
		})
	end

	if managers.menu:is_pc_controller() and not managers.menu:is_steam_controller() then
		self._arrow_right = self._profile_panel:bitmap({
			texture = "guis/textures/menu_arrows",
			name = "self._arrow_right",
			size = 32,
			rotation = 180,
			texture_rect = {
				24,
				0,
				24,
				24
			},
			color = tweak_data.screen_colors.button_stage_3
		})
	else
		self._arrow_right = self._profile_panel:text({
			name = "self._arrow_right",
			h = 24,
			vertical = "center",
			w = 24,
			align = "center",
			text = managers.menu:is_steam_controller() and managers.localization:steam_btn("trigger_r") or managers.localization:get_default_macro("BTN_TOP_R"),
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size
		})
	end

	self._arrow_left:set_left(5)
	self._arrow_right:set_right(self._profile_panel:w() - 5)
	self._arrow_left:set_center_y(self._profile_panel:h() / 2)
	self._arrow_right:set_center_y(self._profile_panel:h() / 2)

	self:mouse_moved(0, 0)
end

function BLTModProfileGui:update()
	self._name_text:set_text(BLT.Mods:ProfileName())
	if self._change_clbk then
		self._change_clbk()
	end
end

function BLTModProfileGui:mouse_moved(x, y)
	local function anim_func(o, large)
		local current_width = o:w()
		local current_height = o:h()
		local end_width = large and 32 or 24
		local end_height = end_width
		local cx, cy = o:center()

		over(0.2, function(p)
			o:set_size(math.lerp(current_width, end_width, p), math.lerp(current_height, end_height, p))
			o:set_center(cx, cy)
		end)
	end

	local pointer, used
	self._button_selection = nil

	local prev_available = BLT.Mods.profile_index > 1
	if self._arrow_left:inside(x, y) and prev_available then
		if not self._is_left_selected then
			self._arrow_left:set_color(tweak_data.screen_colors.button_stage_2)
			self._arrow_left:animate(anim_func, true)
			managers.menu_component:post_event("highlight")

			self._is_left_selected = true
		end

		self._button_selection = "left"
		pointer = "link"
		used = true
	else
		self._arrow_left:set_color(prev_available and tweak_data.screen_colors.button_stage_3 or tweak_data.menu.default_disabled_text_color)
		if self._is_left_selected then
			self._arrow_left:animate(anim_func, false)
			self._is_left_selected = false
		end
	end

	local next_available = BLT.Mods.profile_index < #BLT.Mods.profiles
	if self._arrow_right:inside(x, y) and next_available then
		if not self._is_right_selected then
			self._arrow_right:set_color(tweak_data.screen_colors.button_stage_2)
			self._arrow_right:animate(anim_func, true)
			managers.menu_component:post_event("highlight")

			self._is_right_selected = true
		end

		self._button_selection = "right"
		pointer = "link"
		used = true
	else
		self._arrow_right:set_color(next_available and tweak_data.screen_colors.button_stage_3 or tweak_data.menu.default_disabled_text_color)
		if self._is_right_selected then
			self._arrow_right:animate(anim_func, false)
			self._is_right_selected = false
		end
	end

	if self._add_profile_icon:inside(x, y) then
		if self._is_add_button_selected ~= true then
			self._add_profile_icon:set_color(tweak_data.screen_colors.button_stage_2)

			managers.menu_component:post_event("highlight")

			self._is_add_button_selected = true
		end

		self._button_selection = "add"
		pointer = "link"
		used = true
	else
		self._add_profile_icon:set_color(tweak_data.screen_colors.button_stage_3)
		self._is_add_button_selected = false
	end

	if self._delete_profile_icon:inside(x, y) and #BLT.Mods.profiles > 1 then
		if self._is_delete_button_selected ~= true then
			self._delete_profile_icon:set_color(tweak_data.screen_colors.button_stage_2)

			managers.menu_component:post_event("highlight")

			self._is_delete_button_selected = true
		end

		self._button_selection = "delete"
		pointer = "link"
		used = true
	else
		self._delete_profile_icon:set_color(#BLT.Mods.profiles > 1 and tweak_data.screen_colors.button_stage_3 or tweak_data.menu.default_disabled_text_color)
		self._is_delete_button_selected = false
	end

	if self._name_text:inside(x, y) then
		if not self._name_selection then
			self._name_text:set_color(tweak_data.screen_colors.button_stage_2)
			managers.menu_component:post_event("highlight")
		end

		self._name_selection = true
		pointer = "link"
		used = true
	elseif self._name_selection then
		self._name_text:set_color(tweak_data.screen_colors.button_stage_3)
		self._name_selection = false
	end

	return used, pointer
end

function BLTModProfileGui:mouse_pressed(button, x, y)
	if button ~= Idstring("0") then
		return
	end

	if self._button_selection == "left" then
		managers.menu_component:post_event("menu_enter")
		BLT.Mods:SwitchProfile(BLT.Mods.profile_index - 1)
		self:update()
	elseif self._button_selection == "right" then
		managers.menu_component:post_event("menu_enter")
		BLT.Mods:SwitchProfile(BLT.Mods.profile_index + 1)
		self:update()
	elseif self._button_selection == "add" then
		managers.menu_component:post_event("menu_enter")
		BLT.Mods:SwitchProfile(BLT.Mods:CreateProfile())
		self:update()
	elseif self._button_selection == "delete" then
		managers.menu_component:post_event("menu_enter")
		managers.system_menu:show({
			title = managers.localization:text("dialog_warning_title"),
			text = managers.localization:text("blt_profile_delete", { profile = BLT.Mods:ProfileName() }),
			button_list = {
				{
					text = managers.localization:text("dialog_yes"),
					callback_func = function()
						BLT.Mods:DeleteProfile()
						self:update()
					end
				},
				{
					text = managers.localization:text("dialog_no"),
					cancel_button = true
				}
			}
		})
	elseif self._name_selection then
		self:trigger()
	end
end

function BLTModProfileGui:trigger()
	if not self._editing then
		self:set_editing(true)
	else
		self:set_editing(false)
		BLT.Mods:SetProfileName(self._name_text:text())
	end
	self:_update_caret()
end

function BLTModProfileGui:handle_key(k, pressed)
	if not pressed and k == Idstring("esc") then
		self:trigger()
	else
		self.super.handle_key(self, k, pressed)
	end
end

function BLTModProfileGui:register_callback(clbk)
	self._change_clbk = clbk
end
