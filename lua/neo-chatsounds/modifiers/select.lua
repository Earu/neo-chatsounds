local MODIFIER = {}

MODIFIER.Name = "select"
MODIFIER.LegacySyntax = "#"
MODIFIER.OnlyLegacy = true
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

return MODIFIER