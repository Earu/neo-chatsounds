local MODIFIER = {}

MODIFIER.Name = "overlap"
MODIFIER.DefaultValue = 0

function MODIFIER:ParseArgs(args)
	local n = tonumber(args)
	if not n then return 0 end

	return math.max(0, n)
end

function MODIFIER:GetValue()
	if not self.Value or isfunction(self.ExpressionFn) then return self.DefaultValue end
	return self.Value
end

function MODIFIER:OnStreamInit(stream)
	stream.Overlap = self:GetValue() ~= 0
end

return MODIFIER