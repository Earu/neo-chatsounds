local api = chatsounds.Module("API")
local data = chatsounds.Module("Data")

local SCOPE = {}

function SCOPE:PushSound(sound_id)
	assert(data.Lookup.List[sound_id], "Sound \'" .. sound_id .. "\' does not exist")

	local sound_data = {
		Id = sound_id,
		Type = "sound",
	}

	table.insert(self.Children, sound_data)
	return sound_data
end

function SCOPE:PushModifier(modifier_id, value_or_expr)
	assert(chatsounds.Modifiers[modifier_id], "Modifier \'" .. modifier_id .. "\' does not exist")

	local modifier_data = {
		Id = modifier_id,
		Value = tostring(value_or_expr),
	}

	table.insert(self.Modifiers, modifier_data)
	return modifier_data
end

function SCOPE:PushScope()
	local scope = setmetatable({
		Children = {},
		Modifiers = {},
		Type = "scope",
	}, { __index = SCOPE })

	table.insert(self.Children, scope)
	return scope
end

function SCOPE:ToString()
	local str = ""
	for _, child in ipairs(self.Children) do
		if child.Type == "sound" then
			str = str .. child.Id .. " "
		elseif child.Type == "scope" then
			str = str .. child:ToString() .. " "
		end
	end

	str = str:TrimRight()

	if #self.Modifiers > 0 then
		str = ("(%s)"):format(str)
		for _, modifier in ipairs(self.Modifiers) do
			str = str .. (":%s(%s)"):format(modifier.Id, modifier.Value)
		end
	end

	return str
end

function api.CreateScope()
	return setmetatable({
		Children = {},
		Modifiers = {}
	}, { __index = SCOPE })
end

function api.SoundExists(sound_id)
	return data.Lookup.List[sound_id] ~= nil
end

function api.GetAllSoundData()
	return data.Lookup.List
end

function api.GetSoundData(sound_id)
	return data.Lookup.List[sound_id]
end

function api.ModifierExists(modifier_id)
	return chatsounds.Modifiers[modifier_id] ~= nil
end

function api.GetAllModifiers()
	return chatsounds.Modifiers
end

function api.GetModifier(modifier_id)
	return chatsounds.Modifiers[modifier_id]
end

if SERVER then
	function api.PlayScope(ply, scope, recipient_filter)
		if not IsValid(ply) then
			error("Provided player was invalid")
		end

		local str = scope:ToString()
		net.Start("chatsounds", true)
			net.WriteEntity(ply)
			net.WriteString(str)

		local t = recipient_filter and type(recipient_filter)
		if t == "CRecipientFilter" or t == "table" then
			net.Send(recipient_filter)
		else
			net.Broadcast()
		end
	end

	function api.PlaySounds(ply, sound_ids, modifiers)
		local scope = api.CreateScope()
		for _, sound_id in ipairs(sound_ids) do
			scope:PushSound(sound_id)
		end

		if modifiers then
			for _, modifier_data in ipairs(modifiers) do
				scope:PushModifier(modifier_data.Id, modifier_data.Value)
			end
		end

		api.PlayScope(ply, scope)
	end

	function api.PlaySound(ply, sound_id, modifiers)
		api.PlaySounds(ply, { sound_id }, modifiers)
	end
end

if CLIENT then
	local STR_NETWORKING_LIMIT = 60000
	function api.PlayScope(scope)
		local str = scope:ToString()
		net.Start("chatsounds_cmd", true)
			net.WriteString(str:sub(1, STR_NETWORKING_LIMIT))
		net.SendToServer()
	end

	function api.PlaySounds(sound_ids, modifiers)
		local scope = api.CreateScope()
		for _, sound_id in ipairs(sound_ids) do
			scope:PushSound(sound_id)
		end

		if modifiers then
			for _, modifier_data in ipairs(modifiers) do
				scope:PushModifier(modifier_data.Id, modifier_data.Value)
			end
		end

		api.PlayScope(scope)
	end

	function api.PlaySound(sound_id, modifiers)
		api.PlaySounds({ sound_id }, modifiers)
	end

	local adding_repo = false
	local added_repos = {}
	function api.GetAddedRepositories()
		return table.GetKeys(added_repos)
	end

	function api.IsAddedRepository(repo, branch, base_path)
		local repo_key = table.concat({ repo, branch, base_path }, "/")
		return added_repos[repo_key] ~= nil
	end

	function api.AddRepository(repo, branch, base_path, on_success, on_error)
		if adding_repo then
			error("Already adding a repo")
		end

		local repo_key = table.concat({ repo, branch, base_path }, "/")
		if added_repos[repo_key] then
			on_success()
			return
		end

		adding_repo = true
		data.BuildFromGithub(repo, branch, base_path, true):next(function()
			data.CompileLists():next(function()
				adding_repo = false
				added_repos[repo_key] = true
				on_success()
			end, function(err)
				adding_repo = false
				on_error(err)
			end)
		end, function(err)
			adding_repo = false
			on_error(err)
		end)
	end

	function api.AddRepositories(repos, on_success, on_error)
		if adding_repo then
			error("Already adding a repo")
		end

		adding_repo = true
		local tasks = {}
		for _, repo_data in ipairs(repos) do
			local repo_key = table.concat({ repo_data.Repo, repo_data.Branch, repo_data.BasePath }, "/")
			if not added_repos[repo_key] then
				table.insert(tasks, data.BuildFromGithub(repo_data.Repo, repo_data.Branch, repo_data.BasePath, true))
			end
		end

		-- everything was cached
		if #repos < 1 then
			on_success()
			return
		end

		chatsounds.Tasks.all(tasks):next(function()
			data.CompileLists():next(function()
				adding_repo = false

				for _, repo_data in ipairs(repos) do
					local repo_key = table.concat({ repo_data.Repo, repo_data.Branch, repo_data.BasePath }, "/")
					added_repos[repo_key] = true
				end

				on_success()
			end, function(err)
				adding_repo = false
				on_error(err)
			end)
		end, function(err)
			adding_repo = false
			on_error(err)
		end)
	end
end

-- EXAMPLES
--[[
	-> CLIENT

	--// PLAY ONE SOUND //--
	local api = chatsounds.Module("API")
	api.PlaySound("mpcat")

	--// PLAY ONE SOUND WITH MODIFIERS //--
	local api = chatsounds.Module("API")
	api.PlaySound("mpcat", {
		{ Id = "pitch", Value = 0.5 },
		{ Id = "volume", Value = 2 },
	})

	--// PLAY MULTIPLE SOUNDS WITH MODIFIERS // --
	local api = chatsounds.Module("API")
	api.PlaySound({ "standing here", "i realize" }, {
		{ Id = "pitch", Value = 0.5 },
		{ Id = "volume", Value = 2 },
	})

	--// ADVANCED USAGE //--
	local api = chatsounds.Module("API")

	local scope = api.CreateScope()
	scope:PushSound("standing here")
	scope:PushSound("i realize")

	local child_scope = scope:PushScope()
	child_scope:PushSound("you were just like me")
	child_scope:PushModifier("volume", 200)

	scope:PushModifier("pitch", 1.5)

	print(scope:ToString())
	api.PlayScope(scope)


	-> SERVER

	--// PLAY ONE SOUND //--
	local api = chatsounds.Module("API")
	api.PlaySound(ply, "mpcat")

	--// PLAY ONE SOUND WITH MODIFIERS //--
	local api = chatsounds.Module("API")
	api.PlaySound(ply, "mpcat", {
		{ Id = "pitch", Value = 0.5 },
		{ Id = "volume", Value = 2 },
	})

	--// PLAY MULTIPLE SOUNDS WITH MODIFIERS // --
	local api = chatsounds.Module("API")
	api.PlaySound(ply, { "standing here", "i realize" }, {
		{ Id = "pitch", Value = 0.5 },
		{ Id = "volume", Value = 2 },
	})

	--// ADVANCED USAGE //--
	local api = chatsounds.Module("API")

	local scope = api.CreateScope()
	scope:PushSound("standing here")
	scope:PushSound("i realize")

	local child_scope = scope:PushScope()
	child_scope:PushSound("you were just like me")
	child_scope:PushModifier("volume", 200)

	scope:PushModifier("pitch", 1.5)

	print(scope:ToString())
	api.PlayScope(ply, scope)

]]--