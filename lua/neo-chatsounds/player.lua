if SERVER then
	util.AddNetworkString("chatsounds")

	net.Receive("chatsounds", function(_, ply)
		local str = net.ReadString()
		local ret = hook.Run("ChatsoundsShouldNetwork", ply, str)
		if ret == false then return end

		timer.Simple(0, function()
			if not IsValid(ply) then return end -- can happen in theory

			net.Start("chatsounds", true)
				net.WriteEntity(ply)
				net.WriteString(str:sub(1, 60000))
			net.Broadcast()
		end)
	end)
end

if CLIENT then
	local cs_player = chatsounds.Module("Player")

	function cs_player.GetWantedSound(sound_data)
		local matching_sounds = chatsounds.Data.Lookup.List[sound_data.Key]
		local index = math.random(#matching_sounds)
		local ret_a, ret_b = hook.Run("ChatsoundsOnSelection", index, matching_sounds)

		if isnumber(ret_a) then
			index = ret_a
		end

		if istable(ret_b) then
			matching_sounds = ret_b
		end

		for _, modifier in ipairs(sound_data.Modifiers) do
			if modifier.OnSelection then
				index, matching_sounds = modifier:OnSelection(index, matching_sounds)
			end
		end

		return matching_sounds[math.min(math.max(1, index), #matching_sounds)]
	end

	local function wait_all_tasks_in_order(tasks)
		local i = 1
		local finished_task = chatsounds.Tasks.new()
		if #tasks == 0 then
			finished_task:resolve()
			return finished_task
		end

		local function next_task()
			local task = tasks[i]

			if not task then
				finished_task:resolve()
				return
			end

			task:next(function()
				i = i + 1
				next_task()
			end, function(err)
				finished_task:reject(err)
			end)

			if task.Callback then
				local succ, err = pcall(task.Callback, task)
				if not succ then
					finished_task:reject(err)
					return
				end
			end
		end

		next_task()
		return finished_task
	end

	local function get_all_modifiers(sound_group, ret)
		ret = ret or {}

		if sound_group.Modifiers then
			for _, modifier in ipairs(sound_group.Modifiers) do
				chatsounds.Runners.Yield()
				table.insert(ret, modifier)
			end
		end

		if sound_group.Parent then
			chatsounds.Runners.Yield()
			get_all_modifiers(sound_group.Parent, ret)
		end

		return ret
	end

	local function flatten_sounds(sound_group, ret)
		ret = ret or {}

		if sound_group.Sounds then
			for _, sound_data in ipairs(sound_group.Sounds) do
				chatsounds.Runners.Yield()
				sound_data.Modifiers = table.Merge(get_all_modifiers(sound_data.ParentScope), sound_data.Modifiers)
				table.insert(ret, sound_data)
			end
		end

		for _, child_group in ipairs(sound_group.Children) do
			chatsounds.Runners.Yield()
			flatten_sounds(child_group, ret)
		end

		table.sort(ret, function(a, b)
			chatsounds.Runners.Yield()
			return a.StartIndex < b.StartIndex
		end)

		return ret
	end

	-- TODO: Flatten sound groups so that sounds are played in order even with sub groups
	function cs_player.PlaySoundGroupAsync(ply, sound_group)
		local finished_task = chatsounds.Tasks.new()
		if sound_group.Type ~= "group" then
			finished_task:resolve()
			return finished_task
		end

		chatsounds.Runners.Execute(function()
			local download_tasks = {}
			local sound_tasks = {}
			local sounds = flatten_sounds(sound_group)
			for _, sound_data in ipairs(sounds) do
				if sound_data.Key == "sh" and ply == LocalPlayer() then
					chatsounds.WebAudio.Panic()
					continue
				end

				local _sound = cs_player.GetWantedSound(sound_data)
				local sound_dir_path = _sound.Path:GetPathFromFilename()

				if not file.Exists(sound_dir_path, "DATA") then
					file.CreateDir(sound_dir_path)
				end

				if not file.Exists(_sound.Path, "DATA") then
					chatsounds.Log(("Downloading %s"):format(_sound.Url))

					local download_task = chatsounds.Tasks.new()
					table.insert(download_tasks, download_task)

					chatsounds.Http.Get(_sound.Url):next(function(res)
						if res.Status ~= 200 then
							download_task:reject(("Failed to download %s: %d"):format(_sound.Url, res.Status))
							return
						end

						file.Write(_sound.Path, res.Body)
						chatsounds.Log(("Downloaded %s"):format(_sound.Url))
						download_task:resolve()
					end, function(err)
						download_task:reject(err)
					end)
				end

				local sound_task = chatsounds.Tasks.new()
				sound_task.Callback = function()
					local stream = chatsounds.WebAudio.CreateStream("data/" .. _sound.Path)
					local started = false
					hook.Add("Think", stream, function()
						if not stream:IsReady() then return end

						if not started then
							stream:SetSourceEntity(ply)
							stream:Set3D(true)
							stream.Duration = stream:GetLength()

							for _, modifier in ipairs(sound_data.Modifiers) do
								if modifier.OnStreamInit then
									modifier:OnStreamInit(stream)
								end
							end

							timer.Simple(stream.Duration, function()
								if IsValid(stream) then
									stream:Remove()
								end

								sound_task:resolve()
							end)

							stream:Play()
							started = true
							hook.Run("ChatsoundsSoundInit", ply, _sound, stream, sound_data)
						end

						for _, modifier in ipairs(sound_data.Modifiers) do
							if modifier.OnStreamThink then
								modifier:OnStreamThink(stream)
							end
						end

						hook.Run("ChatsoundsSoundThink", ply, _sound, stream, sound_data)

						stream:Think()
					end)
				end

				table.insert(sound_tasks, sound_task)
			end

			wait_all_tasks_in_order(download_tasks):next(
				function()
					if #sound_tasks > 0 then
						wait_all_tasks_in_order(sound_tasks):next(
							function() finished_task:resolve() end,
							function(err) finished_task:reject(err) end
						)
					else
						finished_task:resolve()
					end
				end,
				function(err) finished_task:reject(err) end
			)
		end, function(err) finished_task:reject(err) end)

		return finished_task
	end

	local CONTEXT_SEPARATOR = ";"
	function cs_player.PlayAsync(ply, text)
		if text[1] == CONTEXT_SEPARATOR then return end
		local tasks = {}
		local text_chunks = text:Split(CONTEXT_SEPARATOR)

		for _, chunk in ipairs(text_chunks) do
			local t = chatsounds.Tasks.new()

			chatsounds.Parser.ParseAsync(chunk):next(function(sound_group)
				local ret = hook.Run("ChatsoundsShouldPlay", ply, chunk, sound_group)
				if ret == false then
					t:resolve()
					return
				end

				cs_player.PlaySoundGroupAsync(ply, sound_group):next(function()
					t:resolve()
				end, function(err)
					t:reject(err)
				end)
			end, function(err)
				t:reject(err)
			end)

			table.insert(tasks, t)
		end

		return chatsounds.Tasks.all(tasks)
	end

	local function handler(ply, text)
		if ply ~= LocalPlayer() then return end

		net.Start("chatsounds", true)
			net.WriteString(text:sub(1, 60000))
		net.SendToServer()
	end

	hook.Add("OnPlayerChat", "chatsounds.Player", handler)

	concommand.Add("saysound", function(ply, _, _, str)
		handler(ply, str)
	end)

	concommand.Add("chatsounds_say", function(ply, _, _, str)
		handler(ply, str)
	end)

	net.Receive("chatsounds", function()
		local ply = net.ReadEntity()
		local text = net.ReadString()

		if not IsValid(ply) then return end

		cs_player.PlayAsync(ply, text):next(nil, function(errors)
			for _, err in ipairs(errors) do
				chatsounds.Error(err)
			end
		end)
	end)

	-- this is necessary otherwise when using the first sounds with webaudio it just fails to play
	hook.Add("Initialize", "chatsounds.Player.WebAudio", function()
		chatsounds.WebAudio.Initialize()
	end)
end