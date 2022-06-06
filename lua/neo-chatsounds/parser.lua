local parser = DEFINE_CHATSOUND_MODULE("parser")

local modifier_lookup = {}
for modifier_name, modifier in pairs(chatsounds.modifiers) do
	if not modifier.only_legacy then
		modifier_lookup[modifier_name] = modifier
	end

	if modifier.legacy_syntax then
		modifier_lookup[modifier.legacy_syntax] = {
			default_value = modifier.legacy_default_value or modifier.default_value,
			parse_args = modifier.legacy_parse_args or modifier.parse_args,
			name = modifier.name,
		}
	end
end

local function parse_sounds(ctx)
	if #ctx.current_str == 0 then return end

	local cur_scope = ctx.scopes[#ctx.scopes]
	if chatsounds.data.lookup[ctx.current_str] then
		cur_scope.sounds = cur_scope.sounds or {}
		table.insert(cur_scope.sounds, { text = ctx.current_str, modifiers = {}, type = "sound" })
	else
		local start_index = 1
		while start_index < #ctx.current_str do
			local matched = false
			local last_space_index = -1
			for i = 0, #ctx.current_str do
				chatsounds.tasks.yield_runner()

				local index = #ctx.current_str - i
				if index <= start_index then break end -- cant go lower than start index

				-- we only want to match with words so account for space chars
				if ctx.current_str[index] == " " then
					last_space_index = index
					local str_chunk = ctx.current_str:sub(start_index, index - 1)
					if chatsounds.data.lookup[str_chunk] then
						cur_scope.sounds = cur_scope.sounds or {}
						table.insert(cur_scope.sounds, { text = ctx.current_str, modifiers = {}, type = "sound" })
						start_index = index + 1
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

	-- assign the modifiers to the last sound parsed, if any
	if cur_scope.sounds then
		cur_scope.sounds[#cur_scope.sounds].modifiers = ctx.modifiers
	end

	-- reset the current string and modifiers
	ctx.current_str = ""
	ctx.last_current_str_space_index = -1
	ctx.modifiers = {}
end

local scope_handlers = {
	["("] = function(raw_str, index, ctx)
		if ctx.in_lua_expression then return end

		parse_sounds(ctx)

		local cur_scope = table.remove(ctx.scopes, #ctx.scopes)
		cur_scope.start_index = index
	end,
	[")"] = function(raw_str, index, ctx)
		if ctx.in_lua_expression then return end

		parse_sounds(ctx) -- will parse sounds and assign modifiers to said sounds if any

		local parent_scope = ctx.scopes[#ctx.scopes]
		local new_scope = {
			children = {},
			parent = parent_scope,
			start_index = -1,
			end_index = index,
			type = "group",
		}

		if #ctx.modifiers > 0 then
			-- if there are modifiers, assign them to the scope
			-- this needs to be flattened into an array later down the line if this scope becomes a modifier itself
			new_scope.modifiers = ctx.modifiers
			ctx.modifiers = {}
		end

		table.insert(parent_scope.children, 1, new_scope)
		table.insert(ctx.scopes, new_scope)
	end,
	[":"] = function(raw_str, index, ctx)
		if ctx.in_lua_expression then return end

		local modifier = { type = "modifier" }
		local modifier_name = ctx.current_str:lower()
		local cur_scope = ctx.scopes[#ctx.scopes]
		if #cur_scope.children > 0 then
			local last_scope_child = cur_scope.children[1]
			if modifier_lookup[modifier_name] then
				last_scope_child.type = "modifier_expression" -- mark the scope as a modifier

				if last_scope_child.modifiers then
					for _, previous_modifier in ipairs(last_scope_child.modifiers) do
						table.insert(ctx.modifiers, previous_modifier)
					end
				end

				modifier.name = modifier_name
				modifier.value = last_scope_child.expression_fn
					and last_scope_child.expression_fn -- if there was a lua expression in the scope, use that
					or modifier_lookup[modifier_name].parse_args(raw_str:sub(last_scope_child.start_index + 1, last_scope_child.end_index - 1))
				modifier.scope = last_scope_child
			end
		else
			if modifier_lookup[modifier_name] then
				modifier.name = modifier_name
				modifier.value = modifier_lookup[modifier_name].default_value
			end
		end

		table.insert(ctx.modifiers, 1, modifier)

		ctx.current_str = ""
		ctx.last_current_str_space_index = -1
	end,
	["["] = function(raw_str, index, ctx)
		ctx.in_lua_expression = false

		local lua_str = raw_str:sub(index + 1, lua_string_end_index)
		local cur_scope = ctx.scopes[#ctx.scopes]
		local fn = chatsounds.expressions.compile(lua_str, "chatsounds_parser_lua_string")

		cur_scope.expression_fn = fn or function() end
	end,
	["]"] = function(raw_str, index, ctx)
		ctx.in_lua_expression = true
		ctx.lua_string_end_index = index - 1
	end,
}

local function parse_legacy_modifiers(ctx, char)
	-- legacy modifiers are 2 chars max, so what we can do is check the current char and the previous
	-- to match against the lookup table

	local found_modifier
	local modifier_start_index = 0
	if modifier_lookup[char] then
		found_modifier = modifier_lookup[char]
		modifier_start_index = 0
	elseif modifier_lookup[char .. ctx.current_str[1]] then
		found_modifier = modifier_lookup[char .. ctx.current_str[1]]
		modifier_start_index = 1
	end

	if found_modifier then
		local modifier = { type = "modifier", name = found_modifier.name }
		local args_end_index = nil
		if ctx.last_current_str_space_index ~= -1 then
			args_end_index = ctx.last_current_str_space_index
		end

		modifier.value = found_modifier.parse_args(ctx.current_str:sub(modifier_start_index + 1, args_end_index))

		table.insert(ctx.modifiers, 1, modifier)
		ctx.current_str = args_end_index and ctx.current_str:sub(ctx.last_current_str_space_index + 1) or ""
		ctx.last_current_str_space_index = -1

		return true
	end

	return false
end

local function parse_str(raw_str)
	local global_scope = { -- global parent scope for the string
		children = {},
		parent = nil,
		start_index = 1,
		end_index = #raw_str,
		type = "group",
		root = true,
	}

	local ctx = {
		scopes = { global_scope },
		in_lua_expression = false,
		lua_string_end_index = -1,
		modifiers = {},
		current_str = "",
		last_current_str_space_index = -1,
	}

	for i = 0, #raw_str do
		chatsounds.tasks.yield_runner()

		local index = #raw_str - i
		local char = raw_str[index]
		if scope_handlers[char] then
			scope_handlers[char](raw_str, index, ctx)
		else
			local standard_iteration = true
			if i % 2 == 0 and parse_legacy_modifiers(ctx, char) then
				-- check every even index so that we match pairs of chars, ideal for legacy modifiers that are 2 chars max in length and overlap
				standard_iteration = false
			end

			if standard_iteration then
				ctx.current_str = char .. ctx.current_str
				if char == " " then
					ctx.last_current_str_space_index = index
				end
			end
		end
	end

	parse_sounds(ctx)

	return coroutine.yield(global_scope)
end

function parser.parse_async(raw_str)
	return chatsounds.tasks.execute_runner(parse_str, raw_str:lower())
end