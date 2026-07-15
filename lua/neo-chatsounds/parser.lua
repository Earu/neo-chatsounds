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
local table_sort = _G.table.sort
local table_add = _G.table.Add

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

table_sort(legacy_modifiers, function(a, b) return b:len() < a:len() end)

-- Matching sound keys against every possible substring of the text is quadratic and tanks the framerate
-- on long messages (issue #19). Instead the text is split into word spans ONCE, and chunks are built
-- incrementally from the CLEANED words (quotes stripped, like the sound keys are matched). A cleaned chunk
-- that is longer than the longest key of the lookup can never match, no matter how much text follows,
-- which bounds the amount of work per word to a constant. This yields the exact same matches as trying
-- every substring because chunks can only start/end on word boundaries once trimmed.
local function get_word_spans(str)
	local spans = {}
	local word_start
	for i = 1, #str do
		chatsounds.Runners.Yield()

		if SPACE_CHARS[str[i]] then
			if word_start then
				table_insert(spans, { word_start, i - 1, str_gsub(str_sub(str, word_start, i - 1), IGNORED_CHARS_PATTERN, "") })
				word_start = nil
			end
		elseif not word_start then
			word_start = i
		end
	end

	if word_start then
		table_insert(spans, { word_start, #str, str_gsub(str_sub(str, word_start, #str), IGNORED_CHARS_PATTERN, "") })
	end

	return spans
end

-- returns every sound key matching a chunk of text starting at spans[start_word],
-- from shortest to longest, along with the index of the word each match ends at
local function find_sound_key_matches(str, spans, start_word)
	local matches = {}
	local max_key_length = chatsounds.Data.Lookup.MaxKeyLength or math.huge

	local cleaned_chunk = spans[start_word][3]
	if #cleaned_chunk == 0 then return matches end -- quote chars only, potential matches will be found from the next word

	if #cleaned_chunk <= max_key_length and chatsounds.Data.Lookup.List[cleaned_chunk] then
		table_insert(matches, { Key = cleaned_chunk, EndWord = start_word })
	end

	for j = start_word + 1, #spans do
		chatsounds.Runners.Yield()

		local prev_span, span = spans[j - 1], spans[j]
		cleaned_chunk = cleaned_chunk .. str_sub(str, prev_span[2] + 1, span[1] - 1) .. span[3]
		if #cleaned_chunk > max_key_length then break end -- no sound key is that long, longer chunks cannot match

		-- quote-only words leave trailing spaces behind once cleaned
		local str_chunk = str_trim(cleaned_chunk)
		if chatsounds.Data.Lookup.List[str_chunk] then
			table_insert(matches, { Key = str_chunk, EndWord = j })
		end
	end

	return matches
end

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
	local spans = get_word_spans(str)
	local word_index = 1
	while word_index <= #spans do
		chatsounds.Runners.Yield()

		local matches = find_sound_key_matches(str, spans, word_index)
		local best_match = matches[#matches] -- longest match wins
		if best_match then
			local start_char = spans[word_index][1]
			table_insert(sounds, { Key = best_match.Key, StartIndex = start_char, EndIndex = start_char + #best_match.Key })
			word_index = best_match.EndWord + 1
		else
			word_index = word_index + 1
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
		local current_str = ctx.CurrentStr
		local spans = get_word_spans(current_str)
		local word_index = 1
		while word_index <= #spans do
			chatsounds.Runners.Yield()

			local matches = find_sound_key_matches(current_str, spans, word_index)
			if #matches > 0 then
				cur_scope.Sounds = cur_scope.Sounds or {}
			end

			local matched = false
			for i = #matches, 1, -1 do -- longest match first, fall back on shorter ones if not found in the raw string
				local match = matches[i]
				local chunk_index_start, chunk_index_end = str_find(raw_str, match.Key, ctx.LastParsedSoundEndIndex or index, true)
				if chunk_index_start then
					ctx.LastParsedSoundEndIndex = chunk_index_end

					local new_sound = {
						Key = match.Key,
						Modifiers = {},
						Type = "sound",
						StartIndex = chunk_index_start,
						EndIndex = chunk_index_end,
						ParentScope = cur_scope,
					}

					table_insert(cur_scope.Sounds, new_sound)
					word_index = match.EndWord + 1
					matched = true
					break
				end
			end

			if not matched then
				word_index = word_index + 1
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

				table_insert(last_sound.Modifiers, modifier)
				table_remove(ctx.Modifiers, i)
			end
		end
	end

	-- reset the current string and modifiers
	ctx.CurrentStr = ""
	ctx.LastCurrentStrSpaceIndex = -1
	ctx.LastParsedSoundEndIndex = nil
end

local function process_scope_children(cur_scope)
	if cur_scope.Sounds then
		local data_chunks = table_add(cur_scope.Sounds, cur_scope.Children)
		table_sort(data_chunks, function(a, b) return a.StartIndex < b.StartIndex end)
		cur_scope.Children = data_chunks
		cur_scope.Sounds = nil
	end
end

local scope_handlers = {
	["("] = function(raw_str, index, ctx)
		if ctx.InLuaExpression then return end

		local cur_scope = ctx.Scopes[#ctx.Scopes]
		if cur_scope.Root then return end

		parse_sounds(raw_str, index, ctx)

		local cur_scope = table_remove(ctx.Scopes, #ctx.Scopes)
		cur_scope.StartIndex = index

		process_scope_children(cur_scope)
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
					IsLegacy = str_find(modifier_name, "^legacy_") and true or false,
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
					IsLegacy = str_find(modifier_name, "^legacy_") and true or false,
				}, { __index = modifier_lookup[modifier_name] })

				end_index = modifier.EndIndex
			end
		end

		if modifier then
			table_insert(ctx.Modifiers, 1, modifier)
		end

		local space_index = str_find(ctx.CurrentStr, SPACE_CHARS_PATTERN, 1, true)
		ctx.CurrentStr = space_index and str_trim(str_sub(ctx.CurrentStr, space_index)) or ""

		parse_sounds(raw_str, end_index + 1, ctx)

		ctx.LastCurrentStrSpaceIndex = -1
	end,
	["["] = function(raw_str, index, ctx)
		ctx.InLuaExpression = false

		local lua_str = str_sub(raw_str, index + 1, ctx.LuaStringEndIndex)

		-- this is necessary to restore legacy modifier that were transformed to lua syntax
		lua_str = str_gsub(lua_str, "%:legacy%_([a-z]+)%((.+)%)", function(modifier_name, args)
			local modifier = modifier_lookup["legacy_" .. modifier_name]
			if not modifier then return "" end

			return modifier.LegacySyntax .. args
		end)

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
		StartIndex = 1,
		EndIndex = #raw_str,
		Type = "group",
		Root = true,
	}

	if #str_trim(raw_str) == 0 then
		return chatsounds.Runners.PushValue(global_scope)
	end

	-- convert legacy modifiers into new ones
	for _, legacy_syntax in ipairs(legacy_modifiers) do
		chatsounds.Runners.Yield()

		local legacy_modifier_name = rev_legacy_lookup[legacy_syntax]
		raw_str = str_gsub(raw_str, legacy_syntax:PatternSafe() .. "([0-9%.]+)", function(str_args)
			return (":%s(%s)"):format(legacy_modifier_name, str_args)
		end)
	end

	local ret = hook.Run("ChatsoundsParserPreParse", raw_str)
	if isstring(ret) then raw_str = ret end

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
	process_scope_children(global_scope)

	return chatsounds.Runners.PushValue(global_scope)
end

function parser.ParseAsync(raw_str)
	return chatsounds.Runners.Execute(parse_str, raw_str:lower())
end

function parser.Parse(raw_str)
	chatsounds.Runners.SetSynchronous(true)
	local ret = parse_str(raw_str:lower())
	chatsounds.Runners.SetSynchronous(false)

	return ret
end