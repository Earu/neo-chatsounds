if SERVER then return end

local completion = chatsounds.Module("Completion")

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
	if not chatsounds.Data.Loading then return end
	if not LocalPlayer():IsTyping() then return end
	if not chatsounds.Enabled then return end

	local chat_x, chat_y = chat.GetChatBoxPos()
	local _, chat_h = chat.GetChatBoxSize()
	if chatsounds.Data.Loading.DisplayPerc then
		local text = (chatsounds.Data.Loading.Text):format(math.max(0, math.min(100, math.Round((chatsounds.Data.Loading.Current / chatsounds.Data.Loading.Target) * 100))))
		draw_shadowed_text(text, chat_x, chat_y + chat_h + 5, 255, 255, 255, 255)
	else
		draw_shadowed_text(chatsounds.Data.Loading.Text, chat_x, chat_y + chat_h + 5, 255, 255, 255, 255)
	end
end)

completion.Suggestions = completion.Suggestions or {}
completion.SuggestionsIndex = -1
hook.Add("ChatTextChanged", "chatsounds.Completion", function(text)
	if not chatsounds.Enabled then return end

	completion.BuildCompletionSuggestions(text)
end)

hook.Add("OnChatTab", "chatsounds.Data.Completion", function(text)
	if not chatsounds.Enabled then return end

	local scroll = (input.IsButtonDown(KEY_LSHIFT) or input.IsButtonDown(KEY_RSHIFT) or input.IsKeyDown(KEY_LCONTROL)) and -1 or 1
	completion.SuggestionsIndex = (completion.SuggestionsIndex + scroll) % #completion.Suggestions

	local choice = completion.Suggestions[completion.SuggestionsIndex + 1]
	if istable(choice) then return choice.Suggestion end

	return choice
end)


local MODIFIER_PATTERN = ":([%w_]+)[%[%]%(%w%s,%.]*$"
local MODIFIER_ARGS_PATTERN = ":[%w_]+%(([%[%]%w%s,%.]*)$"
local function process_modifier_completion(text, suggestions, added_suggestions, is_upper_case)
	local modifier = text:match(MODIFIER_PATTERN)
	local arguments = text:match(MODIFIER_ARGS_PATTERN)
	if modifier then
		local without_modifier = text:gsub(MODIFIER_PATTERN, ""):Trim()
		if #without_modifier == 0 then return false end

		if not arguments then
			for name, _ in pairs(chatsounds.Modifiers) do
				if name:StartWith(modifier) and not added_suggestions[name] then
					local suggestion = ("%s:%s"):format(without_modifier, name)
					table.insert(suggestions, is_upper_case and suggestion:upper() or suggestion)
					added_suggestions[name] = true
				end
			end
		else
			local mod = chatsounds.Modifiers[modifier]
			if not mod then
				completion.SuggestionsIndex = -1
				completion.Suggestions = suggestions
				return
			end

			local suggest_arguments = arguments
			local split_args = arguments:Split(",")

			if type(mod.DefaultValue) == "table" then
				local types = {}
				local current_amount = 0
				local append_comma = true
				for _, v in ipairs(split_args) do
					local is_empty = v:Trim():len() == 0
					append_comma = not is_empty and append_comma
					current_amount = current_amount + (is_empty and 0 or 1)
				end

				for i, value in ipairs(mod.DefaultValue) do
					local comma = append_comma and i == current_amount + 1
					types[math.max(i - current_amount, 1)] = ("%s[%s]"):format(comma and ", " or "", type(value))
				end

				if #mod.DefaultValue ~= current_amount then
					suggest_arguments = suggest_arguments .. table.concat(types, ", "):sub(1, -1)
				end
			elseif split_args[1]:Trim():len() == 0 then
				suggest_arguments = ("%s[%s]"):format(suggest_arguments, type(mod.DefaultValue))
			end

			local suggestion = ("%s:%s(%s)"):format(without_modifier, modifier, suggest_arguments)
			table.insert(suggestions, is_upper_case and suggestion:upper() or suggestion)
		end

		return true
	end

	return false
end

local function add_nested_suggestions(node, text, nested_suggestions, added_suggestions, is_upper_case)
	for _, sound_key in ipairs(node.Sounds) do
		if sound_key:find(text, 1, true) and not added_suggestions[sound_key] then
			table.insert(nested_suggestions, is_upper_case and sound_key:upper() or sound_key)
			added_suggestions[sound_key] = true
		end
	end

	for key, child_node in pairs(node.Keys) do
		add_nested_suggestions(child_node, text, nested_suggestions, added_suggestions, is_upper_case)
	end
end

function completion.BuildCompletionSuggestions(text)
	text = text:gsub("[%s\n\r\t]+"," "):gsub("[\"\']", ""):Trim()

	if #text == 0 then
		completion.Suggestions = {}
		completion.SuggestionsIndex = -1
		return
	end

	local suggestions = {}
	local added_suggestions = {}

	local search_words = text:Split(" ")
	local last_word = search_words[#search_words]
	local is_upper_case = last_word:upper() == last_word

	last_word = last_word:lower()

	for _, modifier_base in pairs(chatsounds.Modifiers) do
		if modifier_base.OnCompletion then
			local ret = modifier_base.OnCompletion(text, suggestions, added_suggestions, is_upper_case)
			if ret then
				completion.Suggestions = suggestions
				completion.SuggestionsIndex = -1
				return
			end
		end
	end

	local processed = process_modifier_completion(text, suggestions, added_suggestions, is_upper_case)
	if processed then
		completion.Suggestions = suggestions
		completion.SuggestionsIndex = -1
		return
	end

	local sounds = {}
	local node = chatsounds.Data.Lookup.Dynamic[last_word[1]]
	if node then
		if node.__depth then
			for i = 2, #last_word do
				if not last_word[i] then break end

				local next_node = node.Keys[last_word[i]]
				if not next_node then break end

				node = next_node
			end

			sounds = node.Sounds

			for _, child_node in pairs(node.Keys) do
				add_nested_suggestions(child_node, text, suggestions, added_suggestions, is_upper_case)
			end
		else
			sounds = node.Sounds
		end
	end

	for _, sound_key in ipairs(sounds) do
		if sound_key:find(text, 1, true) and not added_suggestions[sound_key] then
			table.insert(suggestions, is_upper_case and sound_key:upper() or sound_key)
			added_suggestions[sound_key] = true
		end
	end

	table.sort(suggestions, function(a, b)
		if #a ~= #b then
			return #a < #b
		end
		return a < b
	end)

	completion.SuggestionsIndex = -1
	completion.Suggestions = suggestions
end

local FONT_HEIGHT = 20
local COMPLETION_SEP = "=================="
hook.Add("HUDPaint", "chatsounds.Data.Completion", function()
	if chatsounds.Data.Loading then return end
	if #completion.Suggestions == 0 then return end
	if not chatsounds.Enabled then return end
	if not LocalPlayer():IsTyping() then return end

	local chat_x, chat_y = chat.GetChatBoxPos()
	local _, chat_h = chat.GetChatBoxSize()

	local i = 1
	local base_x, base_y = chat_x, chat_y + chat_h + 5
	for index = completion.SuggestionsIndex + 1, #completion.Suggestions + (#completion.Suggestions - completion.SuggestionsIndex + 1) do
		local extra
		local suggestion = completion.Suggestions[index]
		if istable(suggestion) then
			extra = suggestion.Extra
			suggestion = suggestion.Suggestion
		end

		if suggestion then
			local x, y = base_x, base_y + (i - 1) * FONT_HEIGHT
			if y > ScrH() then return end

			draw_shadowed_text(("%03d."):format(index), x, y, 200, 200, 255, 255)

			local r, g, b, a = 255, 255, 255, 255
			if index == completion.SuggestionsIndex + 1 then
				r, g, b, a = 255, 0, 0, 255
			end

			draw_shadowed_text(suggestion, x + 50, y, r, g, b, a)

			if extra then
				local tw, _ = surface.GetTextSize(suggestion)
				draw_shadowed_text(extra, x + 50 + tw + 20, y, 255, 200, 80, 255)
			end

			i = i + 1
		end
	end

	if completion.SuggestionsIndex + 1 ~= 1 then
		draw_shadowed_text(COMPLETION_SEP, base_x, base_y + (i - 1) * FONT_HEIGHT, 180, 180, 255, 255)
		i = i + 1
	end

	for j = 1, completion.SuggestionsIndex do
		local extra
		local suggestion = completion.Suggestions[j]
		if istable(suggestion) then
			extra = suggestion.Extra
			suggestion = suggestion.Suggestion
		end

		if suggestion then
			local x, y = base_x, base_y + (i - 1) * FONT_HEIGHT
			if y > ScrH() then return end

			draw_shadowed_text(("%03d."):format(j), x, y, 200, 200, 255, 255)
			draw_shadowed_text(suggestion, x + 50, y, 255, 255, 255, 255)

			if extra then
				local tw, _ = surface.GetTextSize(suggestion)
				draw_shadowed_text(extra, x + 50 + tw + 20, y, 255, 200, 80, 255)
			end

			i = i + 1
		end
	end
end)