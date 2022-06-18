local MODIFIER = {}

MODIFIER.Name = "repeat"
MODIFIER.LegacySyntax = "*"
MODIFIER.DefaultValue = 1

function MODIFIER:ParseArgs(args)
	local rep = tonumber(args)
	if not rep then return 1 end

	return math.max(1, rep)
end

function MODIFIER:OnGroupPreProcess(grp, default_opts)
	default_opts.DuplicateCount = self.Value
	return default_opts
end

function MODIFIER:OnSoundPreProcess(snd, default_opts)
	default_opts.DuplicateCount = self.Value
	return default_opts
end

return MODIFIER