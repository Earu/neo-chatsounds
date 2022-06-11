local MODIFIER = {}

MODIFIER.Name = "select"
MODIFIER.LegacySyntax = "#"
MODIFIER.OnlyLegacy = true
MODIFIER.DefaultValue = 0

function MODIFIER:ParseArgs(self, args)
	local select_id = tonumber(args)
	if not select_id then return 0 end

	return math.max(0, select_id)
end

return MODIFIER