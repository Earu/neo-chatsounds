local MODIFIER = {}

MODIFIER.Name = "skip"
MODIFIER.LegacySyntax = "++"
MODIFIER.DefaultValue = 0

function MODIFIER:ParseArgs(args)
	local n = tonumber(args)
	if not n then return 0 end

	return math.max(0, n) / 100
end

function MODIFIER:OnStreamThink(stream)
	if not self.StreamStarted then
		self.StreamStarted = true
		stream:SetSamplePosition(stream:GetSampleCount() * self.Value)
	end
end

return MODIFIER