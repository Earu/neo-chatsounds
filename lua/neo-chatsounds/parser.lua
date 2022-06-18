local parser = chatsounds.Module("Parser")

local SPACE_CHARS = {
	["\t"] = true,
	["\n"] = true,
	["\r"] = true,
	[" "] = true,
}

local modifier_lookup = {}
for modifier_name, modifier in pairs(chatsounds.Modifiers) do
	if not modifier.OnlyLegacy then
		modifier_lookup[modifier_name] = modifier
	end

	if modifier.LegacySyntax then
		local legacy_modifier = table.Copy(modifier)
		legacy_modifier.DefaultValue = modifier.LegacyDefaultValue or modifier.DefaultValue
		legacy_modifier.ParseArgs = modifier.LegacyParseArgs or modifier.ParseArgs

		modifier_lookup[modifier.LegacySyntax] = legacy_modifier
	end
end

local function assign_modifiers(ctx, sounds)
	if not sounds then return end

	for i = 0, #sounds do
		local index = #sounds - i
		for j, modifier in pairs(ctx.Modifiers) do
			chatsounds.Runners.Yield()

			local sound_data = sounds[index]
			if not sound_data then continue end

			local next_sound_data = ctx.Modifiers[j + 1]
			if modifier.StartIndex > sound_data.EndIndex and ((next_sound_data and modifier.EndIndex < next_sound_data.StartIndex) or not next_sound_data) then
				table.insert(sound_data.Modifiers, modifier)
				table.remove(ctx.Modifiers, j)
			end
		end
	end
end

local function parse_sounds(index, ctx)
	if #ctx.CurrentStr == 0 then return end

	local cur_scope = ctx.Scopes[#ctx.Scopes]
	if chatsounds.Data.Lookup.List[ctx.CurrentStr] then
		cur_scope.Sounds = cur_scope.Sounds or {}
		local new_sound = {
			Key = ctx.CurrentStr,
			Modifiers = {},
			Type = "sound",
			StartIndex = index,
			EndIndex = index + #ctx.CurrentStr,
			ParentScope = cur_scope,
		}

		ctx.LastSound = new_sound
		table.insert(cur_scope.Sounds, new_sound)
	else
		local start_index = 1
		while start_index <= #ctx.CurrentStr do
			local matched = false
			local last_space_index = -1
			for i = 0, #ctx.CurrentStr do
				chatsounds.Runners.Yield()

				local relative_index = #ctx.CurrentStr - i
				if relative_index < start_index then break end -- cant go lower than start index

				-- we only want to match with words so account for space chars and end of string
				if SPACE_CHARS[ctx.CurrentStr[relative_index]] or i == 0 then
					last_space_index = relative_index

					local str_chunk = ctx.CurrentStr:sub(start_index, relative_index):gsub("[\"\']", ""):Trim() -- need to trim here, because the player can chain multiple spaces
					if chatsounds.Data.Lookup.List[str_chunk] then
						cur_scope.Sounds = cur_scope.Sounds or {}
						local new_sound = {
							Key = str_chunk,
							Modifiers = {},
							Type = "sound",
							StartIndex = index + start_index,
							EndIndex = index + relative_index - 1,
							ParentScope = cur_scope,
						}

						ctx.LastSound = new_sound
						table.insert(cur_scope.Sounds, new_sound)
						start_index = relative_index + 1
						matched = true
						break
					end
				end
			end

			if not matched then
				-- that means there was only one word and it wasnt a sound
				if last_space_index == -1 then
					break -- no more words, break out of this loop
				else
					start_index = last_space_index + 1
				end
			end
		end
	end

	assign_modifiers(ctx, cur_scope.Sounds)

	-- reset the current string and modifiers
	ctx.CurrentStr = ""
	ctx.LastCurrentStrSpaceIndex = -1
	ctx.Modifiers = {}
end

local scope_handlers = {
	["("] = function(raw_str, index, ctx)
		if ctx.InLuaExpression then return end

		parse_sounds(index, ctx)

		local cur_scope = table.remove(ctx.Scopes, #ctx.Scopes)
		cur_scope.StartIndex = index
	end,
	[")"] = function(raw_str, index, ctx)
		if ctx.InLuaExpression then return end

		parse_sounds(index, ctx) -- will parse sounds and assign modifiers to said sounds if any

		local parent_scope = ctx.Scopes[#ctx.Scopes]
		local new_scope = {
			Children = {},
			Parent = parent_scope,
			StartIndex = -1,
			EndIndex = index,
			Type = "group",
		}

		if #ctx.Modifiers > 0 then
			-- if there are modifiers, assign them to the scope
			-- this needs to be flattened into an array later down the line if this scope becomes a modifier itself
			new_scope.Modifiers = ctx.Modifiers
			ctx.Modifiers = {}
		end

		table.insert(parent_scope.Children, 1, new_scope)
		table.insert(ctx.Scopes, new_scope)
	end,
	[":"] = function(raw_str, index, ctx)
		if ctx.InLuaExpression then return end

		local modifier
		local modifier_name = ctx.CurrentStr
		local cur_scope = ctx.Scopes[#ctx.Scopes]
		if #cur_scope.Children > 0 then
			local last_scope_child = cur_scope.Children[1]
			if modifier_lookup[modifier_name] then
				last_scope_child.Type = "modifier_expression" -- mark the scope as a modifier

				if last_scope_child.Modifiers then
					for _, previous_modifier in ipairs(last_scope_child.Modifiers) do
						table.insert(ctx.Modifiers, previous_modifier)
					end

					last_scope_child.Modifiers = nil -- clean that up
				end

				-- don't play the potential sounds in the modifier
				last_scope_child.Sounds = {}

				modifier = setmetatable({
					Type = "modifier",
					Name = modifier_name,
					StartIndex = index,
					Scope = last_scope_child,
				}, { __index = modifier_lookup[modifier_name] })

				modifier.Value = last_scope_child.ExpressionFn
					and last_scope_child.ExpressionFn -- if there was a lua expression in the scope, use that
					or modifier:ParseArgs(raw_str:sub(last_scope_child.StartIndex + 1, last_scope_child.EndIndex - 1))
			end
		else
			if modifier_lookup[modifier_name] then
				modifier = setmetatable({
					Type = "modifier",
					Name = modifier_name,
					StartIndex = index,
					Value = modifier_lookup[modifier_name].DefaultValue,
				}, { __index = modifier_lookup[modifier_name] })
			end
		end

		table.insert(ctx.Modifiers, 1, modifier)

		ctx.CurrentStr = ""
		ctx.LastCurrentStrSpaceIndex = -1
	end,
	["["] = function(raw_str, index, ctx)
		ctx.InLuaExpression = false

		local lua_str = raw_str:sub(index + 1, ctx.LuaStringEndIndex)
		local cur_scope = ctx.Scopes[#ctx.Scopes]
		local fn = chatsounds.Expressions.Compile(lua_str, "chatsounds_parser_lua_string")

		cur_scope.ExpressionFn = fn or function() end
	end,
	["]"] = function(raw_str, index, ctx)
		ctx.InLuaExpression = true
		ctx.LuaStringEndIndex = index - 1
	end,
}

local function parse_legacy_modifiers(ctx, index)
	local found_modifier
	local args_start_index
	if modifier_lookup[ctx.CurrentStr:sub(1, 2)] then
		found_modifier = modifier_lookup[ctx.CurrentStr:sub(1, 2)]
		args_start_index = 3
	elseif modifier_lookup[ctx.CurrentStr[1]] then
		found_modifier = modifier_lookup[ctx.CurrentStr[1]]
		args_start_index = 2
	end

	if found_modifier then
		local modifier = { Type = "modifier", Name = found_modifier.Name, StartIndex = index }
		local space_index = ctx.CurrentStr:find("[\t\n\r%s]", 1)

		modifier = setmetatable(modifier, { __index = found_modifier })
		modifier.Value = modifier:ParseArgs(ctx.CurrentStr:sub(args_start_index, space_index and space_index - 1 or nil))

		table.insert(ctx.Modifiers, 1, modifier)
		ctx.CurrentStr = " " .. (space_index and ctx.CurrentStr:sub(space_index + 1) or "")
	end
end

local function parse_str(raw_str)
	local global_scope = { -- global parent scope for the string
		Children = {},
		Sounds = {},
		Parent = nil,
		StartIndex = 1,
		EndIndex = #raw_str,
		Type = "group",
		Root = true,
	}

	if #raw_str:Trim() == 0 then
		return coroutine.yield(global_scope)
	end

	local ctx = {
		Scopes = { global_scope },
		InLuaExpression = false,
		LuaStringEndIndex = -1,
		Modifiers = {},
		CurrentStr = "",
		LastCurrentStrSpaceIndex = -1,
		LastSound = nil,
	}

	for i = 0, #raw_str do
		chatsounds.Runners.Yield()

		local index = #raw_str - i
		local char = raw_str[index]
		if scope_handlers[char] then
			scope_handlers[char](raw_str, index, ctx)
		else
			ctx.CurrentStr = char .. ctx.CurrentStr
			if SPACE_CHARS[char] then
				ctx.LastCurrentStrSpaceIndex = index
			end

			parse_legacy_modifiers(ctx, index)
		end
	end

	parse_sounds(0, ctx)

	return coroutine.yield(global_scope)
end

function parser.ParseAsync(raw_str)
	return chatsounds.Runners.Execute(parse_str, raw_str:lower())
end