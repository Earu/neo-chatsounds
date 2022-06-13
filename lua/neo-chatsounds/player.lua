if not CLIENT then return end

local cs_player = chatsounds.Module("Player")

local function get_wanted_sound(sound_data)
	local matching_sounds = chatsounds.Data.Lookup.List[sound_data.Key]

	local index = math.random(#matching_sounds)
	for _, modifier in ipairs(sound_data.Modifiers) do
		if modifier.OnSelection then
			index, matching_sounds = modifier:OnSelection(index, matching_sounds)
		end
	end

	return matching_sounds[math.min(math.max(1, index), #matching_sounds)]
end

local function play_sound_group_async(ply, sound_group)
	if sound_group.Type ~= "group" then return end

	for _, sound_data in pairs(sound_group.Sounds) do
		if sound_data.Key == "sh" and ply == LocalPlayer() then
			chatsounds.WebAudio.Panic()
			continue
		end

		local _sound = get_wanted_sound(sound_data)
		local sound_dir_path = _sound.Path:GetPathFromFilename()
		if not file.Exists(sound_dir_path, "DATA") then
			file.CreateDir(sound_dir_path)
		end

		local download_task = chatsounds.Tasks.new()
		if not file.Exists(_sound.Path, "DATA") then
			chatsounds.Log("Downloading %s", _sound.Url)
			chatsounds.Http.Get(_sound.Url):next(function(res)
				if res.Status ~= 200 then
					download_task:reject("Failed to download %s: %d", _sound.Url, res.Status)
					return
				end

				file.Write(_sound.Path, res.Body)
				chatsounds.Log("Downloaded %s", _sound.Url)
				download_task:resolve()
			end, chatsounds.Error)
		else
			download_task:resolve()
		end

		download_task:next(function()
			local stream = chatsounds.WebAudio.CreateStream("data/" .. _sound.Path)
			stream:Play()
			-- modifier bs ?
		end)
	end
end

function cs_player.PlayAsync(ply, str)
	local t = chatsounds.Tasks.new()
	chatsounds.Parser.ParseAsync(str):next(function(sound_group)
		play_sound_group_async(ply, sound_group):next(function()
			t:resolve()
		end, chatsounds.Error)
	end, chatsounds.Error)

	return t
end

local CONTEXT_SEPARATOR = ";"
hook.Add("OnPlayerChat", "chatsounds.Player", function(ply, text)
	if text[1] == CONTEXT_SEPARATOR then return end

	local start_time = SysTime()
	local text_chunks = text:Split(CONTEXT_SEPARATOR)
	for _, chunk in ipairs(text_chunks) do
		cs_player.PlayAsync(ply, chunk):next(function()
			chatsounds.Log("parsed and played sounds in " .. (SysTime() - start_time) .. "s")
		end)
	end
end)