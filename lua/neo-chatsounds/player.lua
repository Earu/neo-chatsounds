if SERVER then
	util.AddNetworkString("chatsounds")
	util.AddNetworkString("chatsounds_cmd")

	local function handler(ply, text)
		local ret = hook.Run("ChatsoundsShouldNetwork", ply, text)
		if ret == false then return end

		net.Start("chatsounds")
			net.WriteEntity(ply)
			net.WriteString(text:sub(1, 60000))
		net.Broadcast()
	end

	hook.Add("PlayerSay", "chatsounds.Player", handler)

	net.Receive("chatsounds_cmd", function(_, ply)
		local text = net.ReadString()
		handler(ply, text)
	end)
end

if CLIENT then
	local cs_player = chatsounds.Module("Player")

	do
		-- this is a hack to detect stopsound
		hook.Add("InitPostEntity", "chatsounds.Player.StopSoundHack", function()
			local snd = CreateSound(LocalPlayer(), "phx/hmetal1.wav")
			snd:PlayEx(0, 100)

			hook.Add("Think", "chatsounds.Player.StopSoundhack", function()
				if not snd or not snd:IsPlaying() then
					snd = CreateSound(LocalPlayer(), "phx/hmetal1.wav")
					snd:PlayEx(0, 100)

					hook.Run("StopSound")
				end
			end)
		end)
	end

	function cs_player.GetWantedSound(sound_data)
		math.randomseed(math.Round(CurTime()))

		local matching_sounds = chatsounds.Data.Lookup.List[sound_data.Key]
		local index = math.random(1, #matching_sounds)
		local ret_a, ret_b = hook.Run("ChatsoundsOnSelection", index, matching_sounds)

		if isnumber(ret_a) then
			index = ret_a
		end

		if istable(ret_b) then
			matching_sounds = ret_b
		end

		for _, modifier in ipairs(sound_data.Modifiers) do
			if modifier.OnSelection then
				ret_a, ret_b = modifier:OnSelection(index, matching_sounds)

				if isnumber(ret_a) then
					index = ret_a
				end

				if istable(ret_b) then
					matching_sounds = ret_b
				end
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
				local succ, err = pcall(task.Callback, task, i)
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

	local DEFAULT_OPTS = {
		DuplicateCount = 1,
	}
	local function sound_pre_process(grp, is_group)
		if not grp.Modifiers then return DEFAULT_OPTS end

		local opts = table.Copy(DEFAULT_OPTS)
		for _, modifier in ipairs(grp.Modifiers) do
			chatsounds.Runners.Yield()
			if is_group then
				if modifier.OnGroupPreProcess then
					return modifier:OnGroupPreProcess(grp, opts) or DEFAULT_OPTS
				end
			else
				if modifier.OnSoundPreProcess then
					local ret = modifier:OnSoundPreProcess(grp, opts) or DEFAULT_OPTS
					return ret
				end
			end
		end

		return DEFAULT_OPTS
	end


	local function flatten_sounds(sound_group, ret)
		ret = ret or {}

		if sound_group.Sounds then
			local opts = sound_pre_process(sound_group, true)
			local iters = opts.DuplicateCount or 1
			for _ = 1, iters do
				for _, sound_data in ipairs(sound_group.Sounds) do
					chatsounds.Runners.Yield()

					local snd_opts = sound_pre_process(sound_data, false)
					local snd_iters = snd_opts.DuplicateCount or 1
					sound_data.Modifiers = table.Merge(get_all_modifiers(sound_data.ParentScope), sound_data.Modifiers)
					for _ = 1, snd_iters do
						table.insert(ret, sound_data)
					end
				end
			end
		end

		for _, child_group in ipairs(sound_group.Children) do
			chatsounds.Runners.Yield()
			flatten_sounds(child_group, ret)
		end

		table.sort(ret, function(a, b)
			return a.StartIndex < b.StartIndex
		end)

		return ret
	end

	local function prepare_stream(snd, task)
		local stream = chatsounds.WebAudio.CreateStream("data/" .. snd.Path)

		timer.Simple(2, function()
			if not stream:IsReady() then
				hook.Remove("Think", stream)
				task:reject(("Failed to stream %s"):format(snd.Url))
			end
		end)

		hook.Add("Think", stream, function()
			if not stream:IsReady() then return end

			hook.Remove("Think", stream)
			task:resolve()
		end)

		return stream
	end

	cs_player.Streams = {}
	function cs_player.StopAllSounds()
		for _, streams in pairs(cs_player.Streams) do
			for k, stream in pairs(streams) do
				stream:Remove()
				streams[k] = nil
			end
		end

		chatsounds.WebAudio.Panic()
	end

	hook.Add("StopSound", "chatsounds.Player.StopSound", function()
		cs_player.StopAllSounds()
		chatsounds.Log("Cleared all sounds!")
	end)

	local CS_SH_MODE = CreateConVar("chatsounds_sh_mode", "1", FCVAR_ARCHIVE, "0: Disable, 1: Enable only for you, 2: Enable for everyone")
	local function should_sh(ply)
		local mode = CS_SH_MODE:GetInt()
		if mode == 1 then
			return ply == LocalPlayer()
		elseif mode <= 0 then
			return false
		else
			return true
		end
	end

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
			local streams = {}
			local streams_index = table.insert(cs_player.Streams, streams)

			local function reject(err)
				table.remove(cs_player.Streams, streams_index)
				finished_task:reject(err)
			end

			local function resolve()
				table.remove(cs_player.Streams, streams_index)
				finished_task:resolve()
			end

			for i, sound_data in ipairs(sounds) do
				if sound_data.Key == "sh" and should_sh(ply) then
					cs_player.StopAllSounds()
					continue
				end

				local _sound = cs_player.GetWantedSound(sound_data)
				local sound_dir_path = _sound.Path:GetPathFromFilename()

				if not file.Exists(sound_dir_path, "DATA") then
					file.CreateDir(sound_dir_path)
				end

				local download_task = chatsounds.Tasks.new()
				table.insert(download_tasks, download_task)

				if not file.Exists(_sound.Path, "DATA") then
					chatsounds.Log(("Downloading %s"):format(_sound.Url))
					chatsounds.Http.Get(_sound.Url):next(function(res)
						if res.Status ~= 200 then
							download_task:reject(("Failed to download %s: %d"):format(_sound.Url, res.Status))
							return
						end

						file.Write(_sound.Path, res.Body)
						chatsounds.Log(("Downloaded %s"):format(_sound.Url))
						streams[i] = prepare_stream(_sound, download_task)
					end, function(err)
						download_task:reject(err)
					end)
				else
					streams[i] = prepare_stream(_sound, download_task)
				end

				local sound_task = chatsounds.Tasks.new()
				sound_task.StartTime = CurTime()
				sound_task.Callback = function(_, i)
					local stream = streams[i]
					if not stream then
						sound_task:resolve()
						return
					end

					if not stream.IsValid then
						stream.IsValid = function() return false end
					end

					local started = false
					hook.Add("Think", stream, function()
						if not IsValid(ply) then
							if not started then
								sound_task:resolve()
							end

							hook.Remove("Think", stream)
							return
						end

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
								if not stream.Overlap then
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

						if ply:IsDormant() then
							stream:SetVolume(0)
						end
					end)
				end

				table.insert(sound_tasks, sound_task)
			end

			wait_all_tasks_in_order(download_tasks):next(function()
				if #sound_tasks > 0 then
					wait_all_tasks_in_order(sound_tasks):next(resolve, reject)
				else
					resolve()
				end
			end, reject)
		end, reject)

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

		net.Start("chatsounds_cmd")
			net.WriteString(text:sub(1, 60000))
		net.SendToServer()
	end

	concommand.Add("saysound", function(ply, _, _, str)
		handler(ply, str)
	end)

	concommand.Add("chatsounds_say", function(ply, _, _, str)
		handler(ply, str)
	end)

	net.Receive("chatsounds", function()
		if not chatsounds.Enabled then return end
		if chatsounds.Data.Loading then return end

		local ply = net.ReadEntity()
		local text = net.ReadString()

		if not IsValid(ply) then return end

		local t = cs_player.PlayAsync(ply, text)
		if t then
			t:next(nil, function(errors)
				for _, err in ipairs(errors) do
					chatsounds.Error(err)
				end
			end)
		end
	end)

	-- this is necessary otherwise when using the first sounds with webaudio it just fails to play
	hook.Add("Initialize", "chatsounds.Player.WebAudio", function()
		chatsounds.WebAudio.Initialize()
	end)
end