local CS_ENABLE = GetConVar("chatsounds_enable")
local CS_SH_MODE = GetConVar("chatsounds_sh_mode")
local CS_RUNNER_INTERVAL = GetConVar("chatsounds_runner_interval")

local settings = EasyChat.Settings

local category_name = "Chatsounds"
settings:AddCategory(category_name)

settings:AddConvarSetting(category_name, "boolean", CS_ENABLE, "Enable chatsounds")

settings:AddSpacer(category_name)

settings:AddConvarSetting(category_name, "number", CS_SH_MODE, "\'sh\' mode (0: Disable, 1: Only you, 2: Everyone)", 2, 0)
settings:AddConvarSetting(category_name, "number", CS_RUNNER_INTERVAL, "Loading speed (higher is faster and laggier)", 999999, 25)

settings:AddSpacer(category_name)

local setting_local_say = settings:AddSetting(category_name, "string", "Try out sounds")
local setting_play_local = settings:AddSetting(category_name, "action", "Play Text (only for you)")
setting_play_local.DoClick = function()
	local text = setting_local_say:GetText()
	if not text then return end

	text = text:Trim()
	if #text == 0 then return end

	RunConsoleCommand("chatsounds_local_say", text)
end

settings:AddSpacer(category_name)

local setting_re_merge_lists = settings:AddSetting(category_name, "action", "Re-merge lists")
setting_re_merge_lists.DoClick = function()
	RunConsoleCommand("chatsounds_recompile_lists")
end

local setting_recompile_lists = settings:AddSetting(category_name, "action", "Recompile lists (FULL REFRESH!)")
setting_recompile_lists.DoClick = function()
	RunConsoleCommand("chatsounds_recompile_lists_full")
end

local setting_reload = settings:AddSetting(category_name, "action", "Reload chatsounds")
setting_reload.DoClick = function()
	RunConsoleCommand("chatsounds_reload")
end
