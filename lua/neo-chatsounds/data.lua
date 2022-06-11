local data = chatsounds.Module("Data")

data.Lookup = {}

local function http_get(url)
	local t = chatsounds.Tasks.new()
	http.Fetch(url, function(body, _, headers, http_code)
		t:resolve({
			body = body,
			headers = headers,
			status = http_code,
		})
	end, function(err)
		t:reject(err)
	end)

	return t
end

function data.CacheLookup()
	if not file.Exists("chatsounds", "DATA") then
		file.CreateDir("chatsounds")
	end

	local json = chatsounds.Json.encode(data.Lookup)
	file.Write("chatsounds/lookup.json", json)
end

function data.LoadCachedLookup()
	if not file.Exists("chatsounds/lookup.json", "DATA") then return end

	local json = file.Read("chatsounds/lookup.json", "DATA")
	data.Lookup = chatsounds.Json.decode(json)
end

function data.BuildFromGithub(repo, branch)
	branch = branch or "master"

	local api_url = ("https://api.github.com/repos/%s/git/trees/%s?recursive=1"):format(repo, branch)
	local t = chatsounds.Tasks.new()
	http_get(api_url):next(function(res)
		if res.status == 429 or res.status == 503 or res.status == 403 then
			local delay = tonumber(res.headers["Retry-After"] or res.headers["retry-after"]) + 1
			timer.Simple(delay, function()
				data.BuildFromGithub(repo, branch):next(function(recompiled)
					t:resolve(recompiled)
				end, function(err)
					t:reject(err)
				end)
			end)

			chatsounds.Log(("Github API rate limit exceeded, retrying in %s seconds"):format(delay))
			return
		end

		local cookie_name = ("chatsounds_[%s]_[%s]"):format(repo, branch)
		local hash = util.CRC(res.body)
		if cookie.GetString(cookie_name) == hash then
			chatsounds.Log(("%s/%s, no changes detected, not re-compiling lists"):format(repo, branch))
			t:resolve(false)
			return
		end

		local resp = chatsounds.Json.decode(res.body)
		if not resp or not resp.tree then
			t:reject("Invalid response from GitHub:\n" .. chatsounds.Json.encode(resp))
			return
		end

		if data.Loading then
			data.Loading.Target = data.Loading.Target + #resp.tree
		end

		local start_time = SysTime()
		local sound_count = 0
		chatsounds.Runners.Execute(function()
			for i, file_data in pairs(resp.tree) do
				chatsounds.Runners.Yield()

				if data.Loading then
					data.Loading.Current = data.Loading.Current + 1

					local cur_perc = math.Round((data.Loading.Current / data.Loading.Target) * 100)
					if cur_perc % 5 == 0 and cur_perc ~= data.Loading.LastLoggedPercent and (CLIENT or (SERVER and game.IsDedicated())) then
						data.Loading.LastLoggedPercent = cur_perc

						local display_perc = math.Round(cur_perc / 5)
						local display_emaining = 20 - display_perc
						chatsounds.Log(("[%s%s] %s%%"):format(("="):rep(display_perc), (" "):rep(display_emaining), cur_perc))
					end
				end

				if file_data.path:GetExtensionFromFilename() ~= "ogg" then continue end

				sound_count = sound_count + 1

				local path_chunks = file_data.path:Split("/")
				local realm_chunk_index = #path_chunks - 1
				local file_name = file_data.path:GetFileFromFilename():gsub("%.ogg$", "")
				if tonumber(file_name) then
					file_name = path_chunks[#path_chunks - 1]
					realm_chunk_index = realm_chunk_index - 1
				end

				local sound_key = file_name:gsub("[%_%-]", " "):lower()
				if not data.Lookup[sound_key] then
					data.Lookup[sound_key] = {}
				end

				table.insert(data.Lookup[sound_key], {
					url = ("https://raw.githubusercontent.com/%s/%s/%s"):format(repo, branch, file_data.path),
					realm = path_chunks[realm_chunk_index]:lower()
				})
			end

			cookie.Set(cookie_name, hash)
			t:resolve(true)

			chatsounds.Log(("Compiled %d sounds from %s/%s in %s second(s)"):format(sound_count, repo, branch, tostring(SysTime() - start_time)))
		end):next(nil, function(err) t:reject(err) end)
	end, function(err) t:reject(err) end)

	return t
end

function data.Initialize()
	data.LoadCachedLookup() -- always load the cache for the lookup, it will get overriden later if necessary

	data.Loading = {
		Current = 0,
		Target = 0,
	}

	chatsounds.Tasks.all({
		data.BuildFromGithub("Metastruct/garrysmod-chatsounds", "master"),
		data.BuildFromGithub("PAC3-Server/chatsounds", "master"),
	}):next(function(results)
		for _, recompiled in pairs(results) do
			if recompiled then
				data.CacheLookup()
				break
			end
		end

		data.Loading = nil
		chatsounds.Log("Done compiling lists")
	end, function(errors)
		data.Loading = nil

		for _, err in pairs(errors) do
			chatsounds.Error(err)
		end
	end)
end

concommand.Add("chatsounds_recompile_lists", function()
	data.Initialize()
end)

hook.Add("InitPostEntity", "chatsounds.Data", function()
	data.Initialize()
end)

if CLIENT then
	hook.Add("HUDPaint", "chatsounds.Data", function()
		if not data.Loading then return end
		if data.Loading.Target == 0 then return end
		if not LocalPlayer():IsTyping() then return end

		local chat_x, chat_y = chat.GetChatBoxPos()
		local _, chat_h = chat.GetChatBoxSize()

		surface.SetFont("DermaLarge")
		surface.SetTextColor(255, 255, 255, 255)
		surface.SetTextPos(chat_x, chat_y + chat_h + 20)

		local text = ("Loading chatsounds... %s%%"):format(math.Round((data.Loading.Current / data.Loading.Target) * 100))
		surface.DrawText(text)
	end)
end