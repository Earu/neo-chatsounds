local MODIFIER = {}

MODIFIER.Name = "repeat"
MODIFIER.LegacySyntax = "*"
MODIFIER.DefaultValue = 1

function MODIFIER:ParseArgs(args)
	local rep = tonumber(args)
	if not rep then return 1 end

	return math.max(1, rep)
end

function MODIFIER:OnGroupPreProcess(grp)
	return {
		DuplicateCount = self.Value
	}
end

function MODIFIER:OnSoundPreProcess(snd)
	return {
		DuplicateCount = self.Value
	}
end

return MODIFIER