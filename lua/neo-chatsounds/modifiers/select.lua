local MODIFIER = {}

MODIFIER.Name = "select"
MODIFIER.LegacySyntax = "#"
MODIFIER.DefaultValue = 0

function MODIFIER:ParseArgs(args)
	local select_id = tonumber(args)
	if not select_id then return -1 end

	return math.max(1, select_id)
end

function MODIFIER:OnSelection(index, matching_sounds)
	if isfunction(self.ExpressionFn) or self.Value == -1 then return index, matching_sounds end
	return self.Value, matching_sounds
end

local INDEX_SELECTION_PATTERN = "#(%d+)$"
local INDEX_SELECTION_NO_ARGS_PATTERN = "#$"
function MODIFIER.OnCompletion(text, suggestions, added_suggestions)
	local match = text:match(INDEX_SELECTION_PATTERN) or text:match(INDEX_SELECTION_NO_ARGS_PATTERN)
	if not match then return false end

	local index = tonumber(match) or 1

	text = text:gsub(INDEX_SELECTION_PATTERN, ""):gsub(INDEX_SELECTION_NO_ARGS_PATTERN, "")
	local sounds = chatsounds.Parser.ParseSoundTriggers(text)
	if #sounds == 0 then return false end

	local last_sound = sounds[#sounds]
	local existing_sounds = chatsounds.Data.Lookup.List[last_sound.Key]

	index = math.min(index, #existing_sounds)

	for i = index, #existing_sounds + index do
		local relative_index = math.max(1, i % (#existing_sounds + 1))
		local sound_data = existing_sounds[relative_index]
		if not added_suggestions[sound_data.Url] then
			local suggestion = ("%s%s#%d%s"):format(string.sub(text, 1, last_sound.StartIndex - 1), last_sound.Key, relative_index, string.sub(text, last_sound.EndIndex + 1))
			table.insert(suggestions, { Suggestion = suggestion, Extra = (":realm( %s )"):format(sound_data.Realm) })
			added_suggestions[sound_data.Url] = true
		end
	end

	return true
end

return MODIFIER