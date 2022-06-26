local MODIFIER = {}

MODIFIER.Name = "loop"
MODIFIER.DefaultValue = 0

function MODIFIER:ParseArgs(args)
	local n = tonumber(args)
	if not n then return 0 end

	return math.max(0, n)
end

function MODIFIER:OnStreamInit(stream)
	stream:SetLooping(self:GetValue() ~= 0) 
end

return MODIFIIER