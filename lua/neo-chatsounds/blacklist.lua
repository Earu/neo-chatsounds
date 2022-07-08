if not CLIENT then return end

local blacklist = chatsounds.Module("Blacklist")

blacklist.Config = {
	Repositories = {},
	Realms = {},
	Sounds = {},
}

function blacklist.LoadConfig()
	if not file.Exists("chatsounds/blacklist.json", "DATA") then return end

	local json = file.Read("chatsounds/blacklist.json", "DATA") or ""
	blacklist.Config = chatsounds.Json.decode(json)
end

function blacklist.SaveConfig()
	local json = chatsounds.Json.encode(blacklist.Config)
	file.Write("chatsounds/blacklist.json", json)
end

function blacklist.Update(is_block, block_type, ...)
	block_type = (block_type or "sound"):lower()

	local args = {...}
	if block_type == "repository" or block_type == "repo" then
		local repo = table.concat(args, ""):Trim():lower()
		if #repo == 0 then
			return false, ("Invalid repository name, Proper syntax is: %s repo <repository name>"):format(is_block and "chatsounds_block" or "chatsounds_unblock")
		end

		blacklist.Config.Repositories[repo] = is_block and true or nil
	elseif block_type == "realm" then
		local realm = table.concat(args, ""):Trim():lower()
		if #realm == 0 then
			return false, ("Invalid realm name, Proper syntax is: %s realm <realm>"):format(is_block and "chatsounds_block" or "chatsounds_unblock")
		end

		blacklist.Config.Realms[realm] = is_block and true or nil
	elseif block_type == "sound" then
		local sound_index = tonumber(args[1])
		if not sound_index then
			return false, ("Invalid sound index, not a number. Proper syntax is: %s sound <sound_index> <sound_key>"):format(is_block and "chatsounds_block" or "chatsounds_unblock")
		end

		local sound_key = table.concat(args, "", 2):Trim():lower()
		if #sound_key == 0 then
			return false, ("Invalid sound key. Proper syntax is: %s sound <sound_index> <sound_key>"):format(is_block and "chatsounds_block" or "chatsounds_unblock")
		end

		if is_block then
			if not blacklist.Config.Sounds[sound_key] then
				return false, "Sound key isn't blocked"
			end

			blacklist.Config.Sounds[sound_key][sound_index] = nil
			if table.Count(blacklist.Config.Sounds[sound_key]) == 0 then
				blacklist.Config.Sounds[sound_key] = nil
			end
		else
			local sound_data = chatsounds.Data.Lookup.List[sound_key]
			if not sound_data then
				return false, "Invalid sound key, sound does not exist"
			end

			if not blacklist.Config.Sounds[sound_key] then
				blacklist.Config.Sounds[sound_key] = {}
			end

			blacklist.Config.Sounds[sound_key][sound_data.Path] = true
		end
	else
		-- don't save config if nothing changed
		return false, ("Invalid block type \'%s\', valid blocktypes are: repository, realm, sound"):format(block_type)
	end

	hook.Run("ChatsoundsBlacklistUpdated", is_block, block_type, ...)
	blacklist.SaveConfig()
	return true
end

function blacklist.IsSoundBlocked(sound_key, sound_data)
	if blacklist.Config.Sounds[sound_key] then
		return blacklist.Config.Sounds[sound_key][sound_data.Path]
	end

	if blacklist.Config.Realms[sound_data.Realm] then
		return true
	end

	if blacklist.Config.Repositories[sound_data.Repository] then
		return true
	end

	return false
end

local function command_completion(cmd, str_args)
	local suggestions = {}
	local args = str_args:Trim():Split(" ")
	if #args == 1 or #str_args:Trim() == 0 then
		table.insert(suggestions, cmd .. " repository")
		table.insert(suggestions, cmd .. " realm")
		table.insert(suggestions, cmd .. " sound")
	elseif args[1] == "repository" or args[1] == "repo"  then
		local repos = table.GetKeys(chatsounds.Data.Repositories)
		for _, repo in ipairs(repos) do
			table.insert(suggestions, ("%s %s %s"):format(cmd, "repository", repo))
		end
	end

	return suggestions
end

local function make_block_command(is_block)
	local cmd_name = is_block and "chatsounds_block" or "chatsounds_unblock"
	concommand.Add(cmd_name, function(_, _, args)
		if #args < 2 then
			chatsounds.Error(("Invalid arguments, command syntax is: %s <block_type> <args>"):format(cmd_name))
			return
		end

		local block_type = args[1]
		table.remove(args, 1) -- remove block_type from args
		local success, err = blacklist.Update(is_block, block_type, unpack(args))
		if not success then
			chatsounds.Error(err)
		end
	end, command_completion, table.concat({
		("%s a sound, realm, or repository"):format(cmd_name),
		("%s repository <repository_name>"):format(cmd_name),
		("%s realm <realm_name>"):format(cmd_name),
		("%s sound <sound_index> <sound_key>"):format(cmd_name),
	}, "\n"))
end

make_block_command(true)
make_block_command(false)