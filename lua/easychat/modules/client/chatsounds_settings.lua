local CS_ENABLE = GetConVar("chatsounds_enable")
local CS_SH_MODE = GetConVar("chatsounds_sh_mode")
local CS_RUNNER_INTERVAL = GetConVar("chatsounds_runner_interval")
local CS_HIDE_TEXT = GetConVar("chatsounds_hide_text")

local COLOR_RED = Color(255, 0, 0)
local function notify_error(err)
	notification.AddLegacy(err, NOTIFY_ERROR, 3)
	surface.PlaySound("buttons/button11.wav")
	chatsounds.Error(err)
	chat.AddText(COLOR_RED, "[Chatsounds] " .. err)
end

local settings = EasyChat.Settings

local category_name = "Chatsounds"
settings:AddCategory(category_name)

settings:AddConvarSetting(category_name, "boolean", CS_ENABLE, "Enable chatsounds")
settings:AddConvarSetting(category_name, "boolean", CS_HIDE_TEXT, "Hide big chatsounds messages")

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

-- block settings
do
	local setting_blocked_sounds = settings:AddSetting(category_name, "list", "Blocked sounds")
	local blocked_sounds_list = setting_blocked_sounds.List
	blocked_sounds_list:SetMultiSelect(true)
	blocked_sounds_list:AddColumn("Key")
	blocked_sounds_list:AddColumn("Index")

	local function play_selected_sounds(selected_lines)
		for _, selected_line in pairs(selected_lines) do
			local sound_key = selected_line:GetColumnText(1)
			local existing_sounds = chatsounds.Data.Lookup.List[sound_key]
			if existing_sounds then
				local sound_index = tonumber(selected_line:GetColumnText(2))
				local sound_data = sound_index and existing_sounds[sound_index]
				if sound_data then
					sound.PlayURL(sound_data.Url, "mono", function(station)
						if not IsValid(station) then
							notification.AddLegacy("Could not play: " .. sound_data.Url, NOTIFY_ERROR, 3)
							surface.PlaySound("buttons/button11.wav")
							return
						end

						station:Play()
					end)
				end
			end
		end
	end

	local function unblock_selected_sounds(selected_lines)
		for _, selected_line in pairs(selected_lines) do
			local sound_key = selected_line:GetColumnText(1)
			local sound_index = selected_line:GetColumnText(2)
			local success, err = chatsounds.Blacklist.Update(false, "sound", sound_index, sound_key)
			if not success then
				notify_error(err)
			end
		end
	end

	blocked_sounds_list.OnRowRightClick = function(_, _, line)
		local sounds_menu = DermaMenu()

		sounds_menu:AddOption("Play", function()
			play_selected_sounds({ line })
		end)
		sounds_menu:AddOption("Unblock", function()
			unblock_selected_sounds({ line })
		end)
		sounds_menu:AddSpacer()
		sounds_menu:AddOption("Cancel", function() sounds_menu:Remove() end)

		sounds_menu:Open()
	end

	blocked_sounds_list.DoDoubleClick = function()
		play_selected_sounds(blocked_sounds_list:GetSelected())
	end

	local setting_block_sound = settings:AddSetting(category_name, "action", "Block a sound")
	setting_block_sound.DoClick = function()
		local frame
		frame = EasyChat.AskForInput("Block a sound", function(sound_key)
			local value = math.max(1, frame.SoundIndex:GetValue())
			local succ, err = chatsounds.Blacklist.Update(true, "sound", tostring(value), sound_key)
			if not succ then
				notify_error(err)
			end
		end, false)

		frame:SetTall(110)
		frame.SoundIndex = frame:Add("DNumberWang")
		frame.SoundIndex:SetMin(1)
		frame.SoundIndex:SetValue(1)
		frame.SoundIndex:Dock(FILL)
	end

	local setting_unblock_sounds = settings:AddSetting(category_name, "action", "Unblock sound(s)")
	setting_unblock_sounds.DoClick = function()
		unblock_selected_sounds(blocked_sounds_list:GetSelected())
	end

	local setting_blocked_realms = settings:AddSetting(category_name, "list", "Blocked realms")
	local blocked_realms_list = setting_blocked_realms.List
	blocked_realms_list:SetMultiSelect(true)
	blocked_realms_list:AddColumn("Name")

	local setting_block_realm = settings:AddSetting(category_name, "action", "Block a realm")
	setting_block_realm.DoClick = function()
		EasyChat.AskForInput("Block a realm", function(realm_name)
			local succ, err = chatsounds.Blacklist.Update(true, "realm", realm_name)
			if not succ then
				notify_error(err)
			end
		end, false)
	end

	local setting_unblock_realms = settings:AddSetting(category_name, "action", "Unblock realm(s)")
	setting_unblock_realms.DoClick = function()
		local selected_lines = blocked_realms_list:GetSelected()
		for _, selected_line in pairs(selected_lines) do
			local realm_name = selected_line:GetColumnText(1)
			local succ, err = chatsounds.Blacklist.Update(false, "realm", realm_name)
			if not succ then
				notification.AddLegacy(err, NOTIFY_ERROR, 3)
				surface.PlaySound("buttons/button11.wav")
				chatsounds.Error(err)
			end
		end
	end

	local setting_blocked_repos = settings:AddSetting(category_name, "list", "Blocked repositories")
	local blocked_repos_list = setting_blocked_repos.List
	blocked_repos_list:SetMultiSelect(true)
	blocked_repos_list:AddColumn("Name")

	local setting_block_repo = settings:AddSetting(category_name, "action", "Block a repo")
	setting_block_repo.DoClick = function()
		EasyChat.AskForInput("Block a repo", function(repo_name)
			local succ, err = chatsounds.Blacklist.Update(true, "repository", repo_name)
			if not succ then
				notify_error(err)
			end
		end, false)
	end

	local setting_unblock_repos = settings:AddSetting(category_name, "action", "Unblock repository(ies)")
	setting_unblock_repos.DoClick = function()
		local selected_lines = setting_unblock_repos:GetSelected()
		for _, selected_line in pairs(selected_lines) do
			local repo_name = selected_line:GetColumnText(1)
			chatsounds.Blacklist.Update(false, "repository", repo_name)
		end
	end

	local function build_block_lists()
		blocked_sounds_list:Clear()
		blocked_realms_list:Clear()
		blocked_repos_list:Clear()

		-- 💀
		for sound_key, sound_paths in pairs(chatsounds.Blacklist.Config.Sounds) do
			local sounds = chatsounds.Data.Lookup.List[sound_key]
			if sounds then
				for i, sound_data in ipairs(sounds) do
					for path, _ in pairs(sound_paths) do
						if sound_data.Path == path then
							blocked_sounds_list:AddLine(sound_key, i)
						end
					end
				end
			end
		end

		for realm, _ in pairs(chatsounds.Blacklist.Config.Realms) do
			blocked_realms_list:AddLine(realm)
		end

		for repo, _ in pairs(chatsounds.Blacklist.Config.Repositories) do
			blocked_repos_list:AddLine(repo)
		end
	end

	hook.Add("ECSettingsOpened", blocked_sounds_list, build_block_lists)
	hook.Add("ChatsoundsBlacklistUpdated", blocked_sounds_list, build_block_lists)
end

settings:AddSpacer(category_name)

local setting_clear_cache_lists = settings:AddSetting(category_name, "action", "Clear sound cache")
setting_clear_cache_lists.DoClick = function()
	RunConsoleCommand("chatsounds_clear_cache")
end

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
