local parser = chatsounds.Module("Parser")
local chatsounds = _G.chatsounds

local str_explode = _G.string.Explode
local str_find = _G.string.find
local str_sub = _G.string.sub
local str_gsub = _G.string.gsub
local str_trim = _G.string.Trim

local table_insert = _G.table.insert
local table_remove = _G.table.remove
local table_copy = _G.table.Copy

local ipairs = _G.ipairs
local pairs = _G.pairs
local setmetatable = _G.setmetatable

local SPACE_CHARS_PATTERN = "[\t\n\r%s]"
local IGNORED_CHARS_PATTERN = "[\"\']"
local SPACE_CHARS = {
	["\t"] = true,
	["\n"] = true,
	["\r"] = true,
	[" "] = true,
}

local modifier_lookup = {}
local legacy_modifiers = {}
local rev_legacy_lookup = {}
for modifier_name, modifier in pairs(chatsounds.Modifiers) do
	if not modifier.OnlyLegacy then
		modifier_lookup[modifier_name] = modifier
	end

	if modifier.LegacySyntax then
		local legacy_modifier = table_copy(modifier)
		legacy_modifier.DefaultValue = modifier.LegacyDefaultValue or modifier.DefaultValue
		legacy_modifier.ParseArgs = modifier.LegacyParseArgs or modifier.ParseArgs

		modifier_lookup["legacy_" .. modifier_name] = legacy_modifier
		table_insert(legacy_modifiers, modifier.LegacySyntax)
		rev_legacy_lookup[modifier.LegacySyntax] = "legacy_" .. modifier_name
	end
end

table.sort(legacy_modifiers, function(a, b) return b:len() < a:len() end)

function parser.ParseSoundTriggers(str)
	if not str then return {} end

	str = str_trim(str)
	if #str == 0 then return {} end

	if chatsounds.Data.Lookup.List[str] then
		return {
			{ Key = str, StartIndex = 1, EndIndex = #str }
		}
	end

	local sounds = {}
	local relative_start_index = 1
	while relative_start_index <= #str do
		local matched = false
		local last_space_index = -1
		for relative_index = #str, relative_start_index, -1 do
			chatsounds.Runners.Yield()

			local cur_char = str[relative_index]

			-- we only want to match with words so account for space chars and end of string
			if SPACE_CHARS[cur_char] or relative_index == #str then
				last_space_index = relative_index

				local str_chunk = str_gsub(str_sub(str, relative_start_index, relative_index), IGNORED_CHARS_PATTERN, "")
				str_chunk = str_trim(str_chunk) -- need to trim here, because the player can chain multiple spaces

				if #str_chunk > 0 and chatsounds.Data.Lookup.List[str_chunk] then
					table_insert(sounds, { Key = str_chunk, StartIndex = relative_start_index, EndIndex = relative_start_index + #str_chunk })
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

	return sounds
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

		table_insert(cur_scope.Sounds, new_sound)
	else
		local relative_start_index = 1
		while relative_start_index <= #ctx.CurrentStr do
			local matched = false
			local last_space_index = -1
			for relative_index = #ctx.CurrentStr, relative_start_index, -1 do
				chatsounds.Runners.Yield()

				local cur_char = ctx.CurrentStr[relative_index]

				-- we only want to match with words so account for space chars and end of string
				if SPACE_CHARS[cur_char] or relative_index == #ctx.CurrentStr then
					last_space_index = relative_index

					local str_chunk = str_gsub(str_sub(ctx.CurrentStr, relative_start_index, relative_index), IGNORED_CHARS_PATTERN, "")
					str_chunk = str_trim(str_chunk) -- need to trim here, because the player can chain multiple spaces

					if #str_chunk > 0 and chatsounds.Data.Lookup.List[str_chunk] then
						cur_scope.Sounds = cur_scope.Sounds or {}

						local chunk_index_start, chunk_index_end = str_find(raw_str, str_chunk, ctx.LastParsedSoundEndIndex or index, true)
						if chunk_index_start then
							ctx.LastParsedSoundEndIndex = chunk_index_end

							local new_sound = {
								Key = str_chunk,
								Modifiers = {},
								Type = "sound",
								StartIndex = chunk_index_start,
								EndIndex = chunk_index_end,
								ParentScope = cur_scope,
							}

							table_insert(cur_scope.Sounds, new_sound)
							relative_start_index = relative_index + 1
							matched = true
							break
						end
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

	if cur_scope.Sounds then
		local last_sound = cur_scope.Sounds[#cur_scope.Sounds]
		if last_sound then
			for i = #ctx.Modifiers, 1, -1 do
				chatsounds.Runners.Yield()

				local modifier = ctx.Modifiers[i]
				if modifier.StartIndex < last_sound.EndIndex then break end

				table_insert(last_sound.Modifiers, table_remove(ctx.Modifiers, i, ctx.Modifiers))
			end
		end
	end

	-- reset the current string and modifiers
	ctx.CurrentStr = ""
	ctx.LastCurrentStrSpaceIndex = -1
	ctx.LastParsedSoundEndIndex = nil
end

local scope_handlers = {
	["("] = function(raw_str, index, ctx)
		if ctx.InLuaExpression then return end

		local cur_scope = ctx.Scopes[#ctx.Scopes]
		if cur_scope.Root then return end

		parse_sounds(raw_str, index, ctx)

		local cur_scope = table_remove(ctx.Scopes, #ctx.Scopes)
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

		table_insert(parent_scope.Children, 1, new_scope)
		table_insert(ctx.Scopes, new_scope)
	end,
	[":"] = function(raw_str, index, ctx)
		if ctx.InLuaExpression then return end

		local modifier
		local modifier_name = str_explode(SPACE_CHARS_PATTERN, str_trim(ctx.CurrentStr), true)[1]
		local cur_scope = ctx.Scopes[#ctx.Scopes]
		local end_index = index + #modifier_name
		if #cur_scope.Children > 0 then
			local last_scope_child = cur_scope.Children[1]
			local already_assigned = last_scope_child.Type == "modifier_expression"

			-- careful here the last scope gets assigned as the expression for the parsed modifier
			-- meaning "gay:echo (gay porno)" won't work, fix by not allowing space between args and modifier?
			if modifier_lookup[modifier_name] then
				if not already_assigned then
					last_scope_child.Type = "modifier_expression" -- mark the scope as a modifier

					if last_scope_child.Modifiers then
						for _, previous_modifier in ipairs(last_scope_child.Modifiers) do
							chatsounds.Runners.Yield()

							table_insert(ctx.Modifiers, previous_modifier)
						end

						last_scope_child.Modifiers = nil -- clean that up
					end

					-- don't play the potential sounds in the modifier
					last_scope_child.Sounds = {}
				end

				modifier = setmetatable({
					Type = "modifier",
					Name = modifier_name,
					StartIndex = index,
					EndIndex = already_assigned and index + #modifier_name or last_scope_child.EndIndex,
					Scope = already_assigned and nil or last_scope_child,
					IsLegacy = false,
				}, { __index = modifier_lookup[modifier_name] })

				if last_scope_child.ExpressionFn then
					modifier.ExpressionFn = last_scope_child.ExpressionFn
				end

				modifier.Value = already_assigned
					and modifier_lookup[modifier_name].DefaultValue
					or modifier:ParseArgs(str_sub(raw_str, last_scope_child.StartIndex + 1, last_scope_child.EndIndex - 1))

				end_index = modifier.EndIndex
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

				end_index = modifier.EndIndex
			end
		end

		table_insert(ctx.Modifiers, 1, modifier)

		local space_index = str_find(ctx.CurrentStr, SPACE_CHARS_PATTERN, 1, true)
		ctx.CurrentStr = space_index and str_trim(str_sub(ctx.CurrentStr, space_index)) or ""

		parse_sounds(raw_str, end_index + 1, ctx)

		ctx.LastCurrentStrSpaceIndex = -1
	end,
	["["] = function(raw_str, index, ctx)
		ctx.InLuaExpression = false

		local lua_str = str_sub(raw_str, index + 1, ctx.LuaStringEndIndex)
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
	raw_str = str_gsub(raw_str, IGNORED_CHARS_PATTERN, "")

	local global_scope = { -- global parent scope for the string
		Children = {},
		Sounds = {},
		Parent = nil,
		StartIndex = 1,
		EndIndex = #raw_str,
		Type = "group",
		Root = true,
	}

	if #str_trim(raw_str) == 0 then
		return coroutine.yield(global_scope)
	end

	-- convert legacy modifiers into new ones
	for _, legacy_syntax in ipairs(legacy_modifiers) do
		chatsounds.Runners.Yield()

		local legacy_modifier_name = rev_legacy_lookup[legacy_syntax]
		raw_str = str_gsub(raw_str, legacy_syntax:PatternSafe() .. "([0-9%.]+)", function(str_args)
			return (":%s(%s)"):format(legacy_modifier_name, str_args)
		end)
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

	parse_sounds(raw_str, 1, ctx)

	return coroutine.yield(global_scope)
end

function parser.ParseAsync(raw_str)
	return chatsounds.Runners.Execute(parse_str, raw_str:lower())
end