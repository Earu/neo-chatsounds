local data = chatsounds.Module("Data")

data.Repositories = data.Repositories or {}
data.Lookup = data.Lookup or {
	List = {
		["sh"] = {} -- needed for stopping sounds
	},
	Dynamic = {},
}

function data.CacheRepository(repo, branch, path)
	if not file.Exists("chatsounds/repos", "DATA") then
		file.CreateDir("chatsounds/repos")
	end

	local json = chatsounds.Json.encode(data.Repositories[("%s/%s/%s"):format(repo, branch, path)])
	file.Write("chatsounds/repos/" .. util.SHA1(repo .. branch .. path) .. ".json", json)
end

function data.LoadCachedRepository(repo, branch, path)
	local repo_cache_path = "chatsounds/repos/" .. util.SHA1(repo .. branch .. path) .. ".json"

	if not file.Exists(repo_cache_path, "DATA") then return end

	local json = file.Read(repo_cache_path, "DATA")
	data.Repositories[("%s/%s/%s"):format(repo, branch, path)] = chatsounds.Json.decode(json)
end

local function update_loading_state()
	if data.Loading then
		data.Loading.Current = data.Loading.Current + 1

		local cur_perc = math.max(0, math.min(100, math.Round((data.Loading.Current / data.Loading.Target) * 100)))
		if cur_perc % 10 == 0 and cur_perc ~= data.Loading.LastLoggedPercent and (CLIENT or (SERVER and game.IsDedicated())) then
			data.Loading.LastLoggedPercent = cur_perc
			chatsounds.Log((data.Loading.Text):format(cur_perc))
		end
	end
end

local function handle_rate_limit(http_res, base_task, task_fn, ...)
	if http_res.Status == 429 or http_res.Status == 503 or http_res.Status == 403 then
		local delay = tonumber(http_res.Headers["Retry-After"] or http_res.Headers["retry-after"])
		if not delay then
			base_task:reject("Github API rate limit exceeded")
			return true
		end

		local args = { ... }
		timer.Simple(delay + 1, function()
			task_fn(unpack(args)):next(function(...)
				base_task:resolve(...)
			end, function(err)
				base_task:reject(err)
			end)
		end)

		chatsounds.Log(("Github API rate limit exceeded, retrying in %s seconds"):format(delay))
		return true
	end

	return false
end

local function check_cache_validity(body, repo, path, branch)
	local hash = util.SHA1(body)
	local cache_path = ("chatsounds/repos/%s.json"):format(util.SHA1(repo .. branch .. path))
	if file.Exists(cache_path, "DATA") then
		chatsounds.Log(("Found cached repository for %s/%s/%s, validating content..."):format(repo, branch, path))

		local cache_contents = file.Read(cache_path, "DATA")
		local cached_repo = chatsounds.Json.decode(cache_contents)
		local cached_hash = cached_repo.Hash
		return cached_hash == hash, hash
	end

	return false, hash
end

function data.BuildFromGitHubMsgPack(repo, branch, base_path, force_recompile)
	branch = branch or "master"

	local msg_pack_url = ("https://raw.githubusercontent.com/%s/%s/%s/list.msgpack"):format(repo, branch, base_path)
	local t = chatsounds.Tasks.new()
	chatsounds.Http.Get(msg_pack_url):next(function(res)
		local rate_limited = handle_rate_limit(res, t, data.BuildFromGitHubMsgPack, repo, branch, base_path, force_recompile)
		if rate_limited then return end

		local is_cache_valid, hash = check_cache_validity(res.Body, repo, base_path, branch)
		if is_cache_valid and not force_recompile then
			chatsounds.Log(("%s/%s/%s is up to date, not re-compiling lists"):format(repo, branch, base_path))
			data.LoadCachedRepository(repo, branch, base_path)
			t:resolve(false)

			return
		else
			chatsounds.Log(("Cached repository for %s/%s/%s is out of date, re-compiling..."):format(repo, branch, base_path))
		end

		local contents = chatsounds.MsgPack.unpack(res.Body)
		if data.Loading then
			data.Loading.Target = data.Loading.Target + #contents
		end

		local start_time = SysTime()
		local sound_count = 0
		local repo_key = ("%s/%s/%s"):format(repo, branch, base_path)
		if not data.Repositories[repo_key] then
			data.Repositories[repo_key] = {
				Hash = hash,
				List = {},
			}
		end

		chatsounds.Runners.Execute(function()
			for i, raw_sound_data in pairs(contents) do
				chatsounds.Runners.Yield()

				update_loading_state()

				sound_count = sound_count + 1

				local realm = raw_sound_data[1]:lower()
				local sound_key = raw_sound_data[2]:lower():gsub("%.ogg$", ""):gsub("[%_%-]", " "):gsub("[%s\t\n\r]+", " ")
				local path = raw_sound_data[3]

				if not data.Repositories[repo_key].List[sound_key] then
					data.Repositories[repo_key].List[sound_key] = {}
				end

				local url = ("https://raw.githubusercontent.com/%s/%s/%s/%s"):format(repo, branch, base_path, path):gsub("%s", "%%20")
				local sound_path = ("chatsounds/cache/%s/%s.ogg"):format(realm, util.SHA1(url))
				local sound_data = {
					Url = url,
					Realm = realm,
					Path = sound_path,
				}

				table.insert(data.Repositories[repo_key].List[sound_key], sound_data)
			end

			data.CacheRepository(repo, branch, base_path)
			t:resolve(true)
			chatsounds.Log(("Compiled %d sounds from %s/%s/%s in %s second(s)"):format(sound_count, repo, branch, base_path, tostring(SysTime() - start_time)))
		end):next(nil, function(err) t:reject(err) end)
	end, function(err) t:reject(err) end)

	return t
end

function data.BuildFromGithub(repo, branch, base_path, force_recompile)
	branch = branch or "master"

	local api_url = ("https://api.github.com/repos/%s/git/trees/%s?recursive=1"):format(repo, branch)
	local t = chatsounds.Tasks.new()
	chatsounds.Http.Get(api_url):next(function(res)
		local rate_limited = handle_rate_limit(res, t, data.BuildFromGithub, repo, branch, base_path, force_recompile)
		if rate_limited then return end

		local is_cache_valid, hash = check_cache_validity(res.Body, repo, base_path, branch)
		if is_cache_valid and not force_recompile then
			chatsounds.Log(("%s/%s/%s is up to date, not re-compiling lists"):format(repo, branch, base_path))
			data.LoadCachedRepository(repo, branch, base_path)
			t:resolve(false)

			return
		else
			chatsounds.Log(("Cached repository for %s/%s/%s is out of date, re-compiling..."):format(repo, branch, base_path))
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
		local repo_key = ("%s/%s/%s"):format(repo, branch, base_path)
		if not data.Repositories[repo_key] then
			data.Repositories[repo_key] = {
				Hash = hash,
				List = {},
			}
		end

		chatsounds.Runners.Execute(function()
			for i, file_data in pairs(resp.tree) do
				chatsounds.Runners.Yield()

				update_loading_state()

				if file_data.path:GetExtensionFromFilename() ~= "ogg" then continue end

				sound_count = sound_count + 1

				local path = file_data.path:gsub("^" .. base_path:PatternSafe(), "")
				local path_chunks = path:Split("/")
				local realm = path_chunks[2]:lower()
				local sound_key = path_chunks[3]:lower():gsub("%.ogg$", ""):gsub("[%_%-]", " "):gsub("[%s\t\n\r]+", " ")

				if not data.Repositories[repo_key].List[sound_key] then
					data.Repositories[repo_key].List[sound_key] = {}
				end

				local url = ("https://raw.githubusercontent.com/%s/%s/%s"):format(repo, branch, file_data.path):gsub("%s", "%%20")
				local sound_path = ("chatsounds/cache/%s/%s.ogg"):format(realm, util.SHA1(url))
				local sound_data = {
					Url = url,
					Realm = realm,
					Path = sound_path,
				}

				table.insert(data.Repositories[repo_key].List[sound_key], sound_data)
			end

			data.CacheRepository(repo, branch, base_path)
			t:resolve(true)
			chatsounds.Log(("Compiled %d sounds from %s/%s/%s in %s second(s)"):format(sound_count, repo, branch, base_path, tostring(SysTime() - start_time)))
		end):next(nil, function(err) t:reject(err) end)
	end, function(err) t:reject(err) end)

	return t
end

-- Dynamically expanding table, this took me a while to figure out so I'll try to explain it.
-- Because the lookup for the sound key of chatsounds is that large, its not appropriate to iterate over it for suggestions.
-- The time complexity would be O(n) and essentially the game would freeze for 5/10 seconds each time you type a character.
-- The idea here is to subdivide the sound keys into recursive chunks of 25 sounds MAX each.
-- They can be then indexed by the depth marked at first level of the table e.g (lookup.Dynamic['g'].__depth or 1).
-- Depending on the depth we may have something like: lookup.Dynamic = { ['g'] = { __depth = 2, ['a'] = { "im looking at gay porno", "gay porno", "gay" } } }
-- By diving sound keys into chunks we ensure that the time complexity needed to build a suggestion list is minimal because accessing a table with a hash key is O(1),
-- that brings the total time complexity to somewhere around O(d + n) where d is the depth and n the amount of sound keys at that depth.
-- Building this kind of lookup however is very expensive, which is why it should only be done ONCE, and then CACHED if possible.
local MAX_DYN_CHUNK_CHUNK_SIZE = 25
local function build_dynamic_lookup(dyn_lookup, sound_key)
	local words = sound_key:Split(" ")
	if data.Loading then
		data.Loading.Target = data.Loading.Target + #words
	end

	for _, word_key in ipairs(words) do
		chatsounds.Runners.Yield()

		local first_char = word_key[1]
		if not dyn_lookup[first_char] then
			dyn_lookup[first_char] = {
				Sounds = {},
				Keys = {},
			}
		end

		local root_lookup = dyn_lookup[first_char]
		local local_lookup = dyn_lookup[first_char]
		if local_lookup.__depth then
			for i = 2, #word_key do
				local char = word_key[i]
				if not local_lookup[char] then
					root_lookup.__depth = i
					local_lookup.Keys[char] = {
						Sounds = {},
						Keys = {},
					}
				end

				local_lookup = local_lookup.Keys[char]
			end
		end

		table.insert(local_lookup.Sounds, sound_key)

		if #local_lookup >= MAX_DYN_CHUNK_CHUNK_SIZE then
			local depth = root_lookup.__depth or 1
			for i, chunked_sound_key in ipairs(local_lookup.Sounds) do
				chatsounds.Runners.Yield()

				local char = chunked_sound_key[depth + 1]
				if char then
					if not local_lookup.Keys[char] then
						local_lookup.Keys[char] = {
							Sounds = {},
							Keys = {},
						}
					end

					table.insert(local_lookup.Keys[char], table.remove(local_lookup.Sounds, i))
				end
			end

			root_lookup.__depth = depth + 1
		end

		update_loading_state()
	end
end

local function merge_repos(rebuild_dynamic_lookup)
	local should_build_dynamic = false
	if CLIENT and (rebuild_dynamic_lookup or not file.Exists("chatsounds/dyn_lookup.json", "DATA")) then
		should_build_dynamic = true
	end

	return chatsounds.Runners.Execute(function()
		local lookup = {
			List = {
				["sh"] = {} -- needed for stopping sounds
			},
			Dynamic = {},
		}

		if not should_build_dynamic then
			local json = file.Read("chatsounds/dyn_lookup.json", "DATA")
			if not json then
				should_build_dynamic = true
			else
				lookup.Dynamic = chatsounds.Json.decode(json)
			end
		end

		for _, repo in pairs(data.Repositories) do
			for sound_key, sound_list in pairs(repo.List) do
				if not lookup.List[sound_key] then
					lookup.List[sound_key] = {}
				end

				for _, sound_data in pairs(sound_list) do
					chatsounds.Runners.Yield()
					table.insert(lookup.List[sound_key], sound_data)
					update_loading_state()
				end

				if should_build_dynamic then
					build_dynamic_lookup(lookup.Dynamic, sound_key)
				end
			end
		end

		if should_build_dynamic then
			local json = chatsounds.Json.encode(lookup.Dynamic)
			file.Write("chatsounds/dyn_lookup.json", json)
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
		data.BuildFromGithub("Metastruct/garrysmod-chatsounds", "master", "sound/chatsounds/autoadd", force_recompile),
		data.BuildFromGithub("PAC3-Server/chatsounds", "master", "sounds/chatsounds", force_recompile),

		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "csgo", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "css", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "ep1", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "ep2", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "hl1", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "hl2", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "l4d", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "l4d2", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "portal", force_recompile),
		data.BuildFromGitHubMsgPack("PAC3-Server/chatsounds-valve-games", "master", "tf2", force_recompile),
	}):next(function(results)
		local rebuild_dynamic_lookup = force_recompile
		if not force_recompile then
			for _, recompiled in ipairs(results) do
				if recompiled then
					rebuild_dynamic_lookup = true
					break
				end
			end
		end

		data.Loading.Current = 0
		data.Loading.Text = "Merging chatsounds repositories... %d%%"

		merge_repos(rebuild_dynamic_lookup):next(function()
			data.Loading = nil
			chatsounds.Log("Done compiling all lists")
			hook.Run("ChatsoundsInitialized")
		end, function(err)
			data.Loading = nil
			chatsounds.Error(err)
			hook.Run("ChatsoundsInitialized")
		end)
	end, function(errors)
		data.Loading = nil
		for _, err in pairs(errors) do
			chatsounds.Error(err)
		end
		hook.Run("ChatsoundsInitialized")
	end)
end

if not concommand.GetTable().chatsounds_recompile_lists then
	data.Loading = {
		Current = -1,
		Target = -1,
		Text = "Initialising chatsounds...",
		DisplayPerc = false,
	}
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
		if not LocalPlayer():IsTyping() then return end
		if not chatsounds.Enabled then return end

		local chat_x, chat_y = chat.GetChatBoxPos()
		local _, chat_h = chat.GetChatBoxSize()
		if data.Loading.DisplayPerc then
			local text = (data.Loading.Text):format(math.min(100, math.Round((data.Loading.Current / data.Loading.Target) * 100)))
			draw_shadowed_text(text, chat_x, chat_y + chat_h + 5, 255, 255, 255, 255)
		else
			draw_shadowed_text(data.Loading.Text, chat_x, chat_y + chat_h + 5, 255, 255, 255, 255)
		end
	end)

	data.Suggestions = data.Suggestions or {}
	data.SuggestionsIndex = -1
	hook.Add("ChatTextChanged", "chatsounds.Data.Completion", function(text)
		if not chatsounds.Enabled then return end

		data.BuildCompletionSuggestions(text)
	end)

	hook.Add("OnChatTab", "chatsounds.Data.Completion", function(text)
		if not chatsounds.Enabled then return end

		local scroll = (input.IsButtonDown(KEY_LSHIFT) or input.IsButtonDown(KEY_RSHIFT) or input.IsKeyDown(KEY_LCONTROL)) and -1 or 1
		data.SuggestionsIndex = (data.SuggestionsIndex + scroll) % #data.Suggestions

		return data.Suggestions[data.SuggestionsIndex + 1]
	end)

	local function add_nested_suggestions(node, text, nested_suggestions, added_suggestions)
		for _, sound_key in ipairs(node.Sounds) do
			if sound_key:find(text, 1, true) and not added_suggestions[sound_key] then
				table.insert(nested_suggestions, sound_key)
				added_suggestions[sound_key] = true
			end
		end

		for key, child_node in pairs(node.Keys) do
			add_nested_suggestions(child_node, text, nested_suggestion)
		end
	end

	function data.BuildCompletionSuggestions(text)
		text = text:gsub("[%s\n\r\t]+"," "):gsub("[\"\']", ""):Trim()

		if #text == 0 then
			data.Suggestions = {}
			data.SuggestionsIndex = -1
			return
		end

		local search_words = text:Split(" ")
		local last_word = search_words[#search_words]

		local sounds = {}
		local suggestions = {}
		local added_suggestions = {}
		local node = data.Lookup.Dynamic[last_word[1]]
		if node then
			if node.__depth then
				for i = 2, #last_word do
					if not last_word[i] then break end

					node = node.Keys[last_word[i]]
				end

				sounds = node.Sounds

				for _, child_node in ipairs(node.Keys) do
					add_nested_suggestions(child_node, text, suggestions, added_suggestions)
				end
			else
				sounds = node.Sounds
			end
		end

		for _, sound_key in ipairs(sounds) do
			if sound_key:find(text, 1, true) and not added_suggestions[sound_key] then
				table.insert(suggestions, sound_key)
				added_suggestions[sound_key] = true
			end
		end

		table.sort(suggestions, function(a, b)
			return a:byte() < b:byte()
		end)

		data.SuggestionsIndex = -1
		data.Suggestions = suggestions
	end

	local FONT_HEIGHT = 20
	local COMPLETION_SEP = "=================="
	hook.Add("HUDPaint", "chatsounds.Data.Completion", function()
		if data.Loading then return end
		if #data.Suggestions == 0 then return end
		if not chatsounds.Enabled then return end

		local chat_x, chat_y = chat.GetChatBoxPos()
		local _, chat_h = chat.GetChatBoxSize()

		local i = 1
		local base_x, base_y = chat_x, chat_y + chat_h + 5
		for index = data.SuggestionsIndex + 1, #data.Suggestions + (#data.Suggestions - data.SuggestionsIndex + 1) do
			local suggestion = data.Suggestions[index]
			if not suggestion then continue end

			local x, y = base_x, base_y + (i - 1) * FONT_HEIGHT
			if y > ScrH() then return end

			draw_shadowed_text(("%03d."):format(index), x, y, 200, 200, 255, 255)

			if index == data.SuggestionsIndex + 1 then
				draw_shadowed_text(suggestion, x + 50, y, 255, 0, 0, 255)
			else
				draw_shadowed_text(suggestion, x + 50, y, 255, 255, 255, 255)
			end

			i = i + 1
		end

		if data.SuggestionsIndex + 1 ~= 1 then
			draw_shadowed_text(COMPLETION_SEP, base_x, base_y + (i - 1) * FONT_HEIGHT, 180, 180, 255, 255)
			i = i + 1
		end

		for j = 1, data.SuggestionsIndex do
			local suggestion = data.Suggestions[j]
			if not suggestion then continue end

			local x, y = base_x, base_y + (i - 1) * FONT_HEIGHT
			if y > ScrH() then return end

			draw_shadowed_text(("%03d."):format(j), x, y, 200, 200, 255, 255)
			draw_shadowed_text(suggestion, x + 50, y, 255, 255, 255, 255)

			i = i + 1
		end
	end)
end