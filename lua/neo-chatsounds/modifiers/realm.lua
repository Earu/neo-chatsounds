local MODIFIER = {}

MODIFIER.Name = "realm"
MODIFIER.DefaultValue = ""

function MODIFIER:ParseArgs(args)
	return args
end

function MODIFIER:OnSelection(index, matching_sounds)
	if not self.Value or self.Value == "" then return index, matching_sounds end

	local ret = {}
	for _, matching_sound in ipairs(matching_sounds) do
		if self.Value ~= matching_sound.Realm then continue end

		table.insert(ret, matching_sound)
	end

	return index, ret
end

return MODIFIER