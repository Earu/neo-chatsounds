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

local MAX_LEGACY_MODIFIER_LEN = 2
local function parse_legacy_modifiers(ctx, index)
	local found_modifier
	local args_start_index
	for i = MAX_LEGACY_MODIFIER_LEN, 1, -1 do
		chatsounds.Runners.Yield()

		local modifier_name = ctx.CurrentStr:sub(1, i)
		if modifier_lookup[modifier_name] then
			found_modifier = modifier_lookup[modifier_name]
			args_start_index = i + 1
			break
		end
	end

	if found_modifier then
		local modifier = { Type = "modifier", Name = found_modifier.Name, StartIndex = index }
		local space_index = ctx.CurrentStr:find("[\t\n\r%s]", 1)
		local str_args = ctx.CurrentStr:sub(args_start_index, space_index and space_index - 1 or nil)

		modifier = setmetatable(modifier, { __index = found_modifier })
		modifier.Value = modifier:ParseArgs(str_args)
		modifier.IsLegacy = true

		table.insert(ctx.Modifiers, 1, modifier)

		ctx.CurrentStr = space_index and ctx.CurrentStr:sub(1, space_index - 1) or ""
	end
end

local function parse_sounds(raw_str, index, ctx)
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

		table.insert(cur_scope.Sounds, new_sound)
	else
		local relative_start_index = 1
		while relative_start_index <= #ctx.CurrentStr do
			local matched = false
			local last_space_index = -1
			for relative_index = #ctx.CurrentStr, relative_start_index, -1 do
				chatsounds.Runners.Yield()

				-- we only want to match with words so account for space chars and end of string
				if SPACE_CHARS[ctx.CurrentStr[relative_index]] or relative_index == #ctx.CurrentStr then
					last_space_index = relative_index

					local str_chunk = ctx.CurrentStr:sub(relative_start_index, relative_index):gsub("[\"\']", ""):Trim() -- need to trim here, because the player can chain multiple spaces
					if #str_chunk > 0 and chatsounds.Data.Lookup.List[str_chunk] then
						local chunk_start_index, chunk_end_index = raw_str:find(str_chunk, ctx.LastSoundParsedEndIndex, true) -- :(, forced to do that otherwise the indexes are just wrong
						if not chunk_start_index then continue end

						ctx.LastSoundParsedEndIndex = chunk_end_index
						cur_scope.Sounds = cur_scope.Sounds or {}

						local new_sound = {
							Key = str_chunk,
							Modifiers = {},
							Type = "sound",
							StartIndex = chunk_start_index,
							EndIndex = chunk_end_index,
							ParentScope = cur_scope,
						}

						table.insert(cur_scope.Sounds, new_sound)
						relative_start_index = relative_index + 1
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
					relative_start_index = last_space_index + 1
				end
			end
		end
	end

	-- reset the current string and modifiers
	ctx.CurrentStr = ""
	ctx.LastCurrentStrSpaceIndex = -1
	ctx.Modifiers = {}
end

local scope_handlers = {
	["("] = function(raw_str, index, ctx)
		if ctx.InLuaExpression then return end

		local cur_scope = ctx.Scopes[#ctx.Scopes]
		if cur_scope.Root then return end

		parse_sounds(raw_str, index, ctx)

		local cur_scope = table.remove(ctx.Scopes, #ctx.Scopes)
		cur_scope.StartIndex = index
	end,
	[")"] = function(raw_str, index, ctx)
		if ctx.InLuaExpression then return end

		parse_sounds(raw_str, index, ctx) -- will parse sounds and assign modifiers to said sounds if any

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
						chatsounds.Runners.Yield()

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
					EndIndex = last_scope_child.EndIndex,
					Scope = last_scope_child,
					IsLegacy = false,
				}, { __index = modifier_lookup[modifier_name] })

				if last_scope_child.ExpressionFn then
					modifier.ExpressionFn = last_scope_child.ExpressionFn
				end

				modifier.Value = modifier:ParseArgs(raw_str:sub(last_scope_child.StartIndex + 1, last_scope_child.EndIndex - 1))
			end
		else
			if modifier_lookup[modifier_name] then
				modifier = setmetatable({
					Type = "modifier",
					Name = modifier_name,
					StartIndex = index,
					EndIndex = index + #modifier_name,
					Value = modifier_lookup[modifier_name].DefaultValue,
					IsLegacy = false,
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
		LastSoundParsedEndIndex = 1,
	}

	for index = #raw_str, 1, -1 do
		chatsounds.Runners.Yield()

		local char = raw_str[index]
		if scope_handlers[char] then
			scope_handlers[char](raw_str, index, ctx)
		else
			ctx.CurrentStr = char .. ctx.CurrentStr
			if SPACE_CHARS[char] then
				ctx.LastCurrentStrSpaceIndex = index
			end
		end
	end

	parse_sounds(raw_str, 0, ctx)

	return coroutine.yield(global_scope)
end

function parser.ParseAsync(raw_str)
	return chatsounds.Runners.Execute(parse_str, raw_str:lower())
end