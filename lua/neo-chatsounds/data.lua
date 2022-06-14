local data = chatsounds.Module("Data")

data.Repositories = data.Repositories or {}
data.Lookup = data.Lookup or {
	List = {
		["sh"] = {} -- needed for stopping sounds
	},
	Tree = {},
}

function data.CacheRepository(repo)
	if not file.Exists("chatsounds/repos", "DATA") then
		file.CreateDir("chatsounds/repos")
	end

	local json = chatsounds.Json.encode(data.Repositories[repo])
	file.Write("chatsounds/repos/" .. util.SHA1(repo) .. ".json", json)
end

function data.LoadCachedRepository(repo)
	local repo_cache_path = "chatsounds/repos/" .. util.SHA1(repo) .. ".json"

	if not file.Exists(repo_cache_path, "DATA") then return end

	local json = file.Read(repo_cache_path, "DATA")
	data.Repositories[repo] = chatsounds.Json.decode(json)
end

local function url_encode(str)
	-- ensure all newlines are in CRLF form
	str = str:gsub("\r?\n", "\r\n")

	-- percent-encode all non-unreserved characters
	-- as per RFC 3986, Section 2.3
	-- (except for space, which gets plus-encoded)
	str = str:gsub("([^%w%-%.%_%~ ])", function(c)
		return ("%%%02X"):format(c:byte())
	end)

	-- convert spaces to their encoded form
	str = str:gsub("%s", "%%20")

	return str
end

local function update_loading_state()
	if data.Loading then
		data.Loading.Current = data.Loading.Current + 1

		local cur_perc = math.min(100, math.Round((data.Loading.Current / data.Loading.Target) * 100))
		if cur_perc % 10 == 0 and cur_perc ~= data.Loading.LastLoggedPercent and (CLIENT or (SERVER and game.IsDedicated())) then
			data.Loading.LastLoggedPercent = cur_perc
			chatsounds.Log((data.Loading.Text):format(cur_perc))
		end
	end
end

function data.BuildFromGithub(repo, branch, force_recompile)
	branch = branch or "master"

	local api_url = ("https://api.github.com/repos/%s/git/trees/%s?recursive=1"):format(repo, branch)
	local t = chatsounds.Tasks.new()
	chatsounds.Http.Get(api_url):next(function(res)
		if res.Status == 429 or res.Status == 503 or res.Status == 403 then
			local delay = tonumber(res.Headers["Retry-After"] or res.Headers["retry-after"])
			if not delay then
				t:reject("Github API rate limit exceeded")
				return
			end

			timer.Simple(delay + 1, function()
				data.BuildFromGithub(repo, branch):next(function()
					t:resolve()
				end, function(err)
					t:reject(err)
				end)
			end)

			chatsounds.Log(("Github API rate limit exceeded, retrying in %s seconds"):format(delay))
			return
		end

		local hash = util.SHA1(res.Body)
		local cache_path = ("chatsounds/repos/%s.json"):format(util.SHA1(repo))
		if not force_recompile and file.Exists(cache_path, "DATA") then
			chatsounds.Log(("Found cached repository for %s, validating content..."):format(repo))

			local cache_contents = file.Read(cache_path, "DATA")
			local cached_repo = chatsounds.Json.decode(cache_contents)
			local cached_hash = cached_repo.Hash
			if cached_hash == hash then
				chatsounds.Log(("%s is up to date, not re-compiling lists"):format(repo))
				data.LoadCachedRepository(repo)
				t:resolve()

				return
			else
				chatsounds.Log(("Cached repository for %s is out of date, re-compiling..."):format(repo))
			end
		end

		local resp = chatsounds.Json.decode(res.Body)
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
			if not data.Repositories[repo] then
				data.Repositories[repo] = {
					Hash = hash,
					Tree = {},
					List = {},
				}
			end

			for i, file_data in pairs(resp.tree) do
				chatsounds.Runners.Yield(250)

				update_loading_state()

				if file_data.path:GetExtensionFromFilename() ~= "ogg" then continue end

				sound_count = sound_count + 1

				local path_chunks = file_data.path:Split("/")
				local realm_chunk_index = #path_chunks - 1
				local file_name = file_data.path:GetFileFromFilename():gsub("%.ogg$", "")
				if tonumber(file_name) then
					file_name = path_chunks[#path_chunks - 1]
					realm_chunk_index = realm_chunk_index - 1
				end

				if file_name:match("[a-zA-Z]+") then
					file_name = file_name:gsub("[0-9]", "")
				end

				local sound_key = file_name:gsub("[%_%-]", " "):gsub("[%s\t\n\r]+", " "):lower()
				if not data.Repositories[repo].List[sound_key] then
					data.Repositories[repo].List[sound_key] = {}
				end

				local realm = path_chunks[realm_chunk_index]:lower()
				local url = ("https://raw.githubusercontent.com/%s/%s/%s"):format(repo, branch, table.concat(path_chunks, "/", 1, #path_chunks - 1) .. "/" .. url_encode(path_chunks[#path_chunks])):gsub("%s", "%%20")
				local sound_path = ("chatsounds/cache/%s/%s.ogg"):format(realm, util.SHA1(url))
				local sound_data = {
					Url = url,
					Realm = realm,
					Path = sound_path,
				}

				table.insert(data.Repositories[repo].List[sound_key], sound_data)
			end

			data.CacheRepository(repo)
			t:resolve()
			chatsounds.Log(("Compiled %d sounds from %s/%s in %s second(s)"):format(sound_count, repo, branch, tostring(SysTime() - start_time)))
		end):next(nil, function(err) t:reject(err) end)
	end, function(err) t:reject(err) end)

	return t
end

local function merge_repos()
	return chatsounds.Runners.Execute(function()
		local lookup = {
			List = {
				["sh"] = {} -- needed for stopping sounds
			},
			Tree = {},
		}

		for _, repo in pairs(data.Repositories) do
			for sound_key, sound_list in pairs(repo.List) do
				if not lookup.List[sound_key] then
					lookup.List[sound_key] = {}
				end

				for _, sound_data in pairs(sound_list) do
					chatsounds.Runners.Yield(250)
					table.insert(lookup.List[sound_key], sound_data)
					update_loading_state()
				end

				local key_chunks = sound_key:Split(" ")
				local cur_tree_node = lookup.Tree
				for _, chunk in pairs(key_chunks) do
					chatsounds.Runners.Yield(250)

					if not cur_tree_node[chunk] then
						cur_tree_node[chunk] = {}
					end

					cur_tree_node = cur_tree_node[chunk]
				end
			end
		end

		data.Lookup = lookup
	end)
end

function data.CompileLists(force_recompile)
	data.Loading = {
		Current = 0,
		Target = 0,
		Text = "Loading chatsounds... %d%%",
		DisplayPerc = true,
	}

	chatsounds.Tasks.all({
		data.BuildFromGithub("Metastruct/garrysmod-chatsounds", "master", force_recompile),
		data.BuildFromGithub("PAC3-Server/chatsounds", "master", force_recompile),
	}):next(function()
		data.Loading.Current = 0
		data.Loading.Text = "Merging chatsounds repositories... %d%%"

		merge_repos():next(function()
			data.Loading = nil
			chatsounds.Log("Done compiling all lists")
		end, function(err)
			data.Loading = nil
			chatsounds.Error(err)
		end)
	end, function(errors)
		data.Loading = nil
		for _, err in pairs(errors) do
			chatsounds.Error(err)
		end
	end)
end

concommand.Add("chatsounds_recompile_lists", function()
	data.CompileLists(true)
end)

hook.Add("InitPostEntity", "chatsounds.Data", function()
	data.CompileLists()
end)

if CLIENT then
	surface.CreateFont("chatsounds.Completion", {
		font = "Roboto",
		size = 20,
		weight = 500,
		antialias = true,
		additive = false,
		extended = true,
		shadow = true,
	})

	surface.CreateFont("chatsounds.Completion.Shadow", {
		font = "Roboto",
		size = 20,
		weight = 500,
		antialias = true,
		additive = false,
		blursize = 1,
		extended = true,
		shadow = true,
	})

	local SHADOW_COLOR = Color(0, 0, 0, 255)
	local surface_SetFont = surface.SetFont
	local surface_SetTextPos = surface.SetTextPos
	local surface_SetTextColor = surface.SetTextColor
	local surface_DrawText = surface.DrawText
	local function draw_shadowed_text(text, x, y, r, g, b, a)
		surface_SetFont("chatsounds.Completion.Shadow")
		surface_SetTextColor(SHADOW_COLOR)

		for _ = 1, 5 do
			surface_SetTextPos(x, y)
			surface_DrawText(text)
		end

		surface_SetFont("chatsounds.Completion")
		surface_SetTextColor(r, g, b, a)
		surface_SetTextPos(x, y)
		surface_DrawText(text)
	end

	hook.Add("HUDPaint", "chatsounds.Data.Loading", function()
		if not data.Loading then return end
		if data.Loading.Target == 0 then return end
		if not LocalPlayer():IsTyping() then return end

		local chat_x, chat_y = chat.GetChatBoxPos()
		local _, chat_h = chat.GetChatBoxSize()
		local text = (data.Loading.Text):format(math.min(100, math.Round((data.Loading.Current / data.Loading.Target) * 100)))
		draw_shadowed_text(text, chat_x, chat_y + chat_h + 5, 255, 255, 255, 255)
	end)

	data.Suggestions = data.Suggestions or {}
	data.SuggestionsIndex = -1
	hook.Add("ChatTextChanged", "chatsounds.Data.Completion", function(text)
		data.BuildCompletionSuggestions(text)
	end)

	hook.Add("OnChatTab", "chatsounds.Data.Completion", function(text)
		local scroll = (input.IsButtonDown(KEY_LSHIFT) or input.IsButtonDown(KEY_RSHIFT) or input.IsKeyDown(KEY_LCONTROL)) and -1 or 1
		data.SuggestionsIndex = (data.SuggestionsIndex + scroll) % #data.Suggestions

		return data.Suggestions[data.SuggestionsIndex + 1]
	end)

	local table_count = table.Count
	local function add_nested_suggestions(node, base, ret)
		ret = ret or {}
		for key, child_node in pairs(node) do
			if table_count(child_node) == 0 then
				table.insert(ret, (base .. " " .. key):Trim())
			else
				add_nested_suggestions(child_node, base .. " " .. key, ret)
			end
		end

		return ret
	end

	local completion_sepatator = "=================="
	function data.BuildCompletionSuggestions(text)
		text = text:gsub("[%s\n\r\t]+"," ")

		if #text == 0 then
			data.Suggestions = {}
			data.SuggestionsIndex = -1
			return
		end

		local tree_node = data.Lookup.Tree
		local text_chunks = text:Split(" ")
		local suggestions = {}
		for i, chunk in ipairs(text_chunks) do
			local chunk_text = chunk:lower():Trim()
			if i == #text_chunks then
				local base = table.concat(text_chunks, " ", 1, i - 1)
				for sound_key, child_node in pairs(tree_node) do
					if not sound_key:StartWith(chunk_text) then continue end
					if table_count(child_node) > 0 then
						add_nested_suggestions(child_node, base .. " " .. sound_key, suggestions)
					else
						table.insert(suggestions, (base .. " " .. sound_key):Trim())
					end
				end
			else
				-- if we're not on the last chunk, we need to check if the next chunk is a valid chatsound
				local new_tree_node = tree_node[chunk_text]
				if not new_tree_node then break end

				tree_node = new_tree_node
			end
		end

		table.sort(suggestions, function(a, b)
			return a:len() < b:len()
		end)

		completion_sepatator = ("="):rep((suggestions[#suggestions] or "=================="):len() + 5)

		data.SuggestionsIndex = -1
		data.Suggestions = suggestions
	end

	local FONT_HEIGHT = 20
	hook.Add("HUDPaint", "chatsounds.Data.Completion", function()
		if #data.Suggestions == 0 then return end

		local chat_x, chat_y = chat.GetChatBoxPos()
		local _, chat_h = chat.GetChatBoxSize()

		local i = 1
		local base_x, base_y = chat_x, chat_y + chat_h + 5
		for index = data.SuggestionsIndex + 1, #data.Suggestions + (#data.Suggestions - data.SuggestionsIndex + 1) do
			local suggestion = data.Suggestions[index]
			if not suggestion then continue end

			local x, y = base_x, base_y + (i - 1) * FONT_HEIGHT
			draw_shadowed_text(("%03d."):format(index), x, y, 200, 200, 255, 255)

			if index == data.SuggestionsIndex + 1 then
				draw_shadowed_text(suggestion, x + 50, y, 255, 0, 0, 255)
			else
				draw_shadowed_text(suggestion, x + 50, y, 255, 255, 255, 255)
			end

			i = i + 1
		end

		if data.SuggestionsIndex + 1 ~= 1 then
			draw_shadowed_text(completion_sepatator, base_x, base_y + (i - 1) * FONT_HEIGHT, 180, 180, 255, 255)
			i = i + 1
		end

		for j = 1, data.SuggestionsIndex do
			local suggestion = data.Suggestions[j]
			if not suggestion then continue end

			local x, y = base_x, base_y + (i - 1) * FONT_HEIGHT
			draw_shadowed_text(("%03d."):format(j), x, y, 200, 200, 255, 255)
			draw_shadowed_text(suggestion, x + 50, y, 255, 255, 255, 255)

			i = i + 1
		end
	end)
end