return function(ent)
	if ent.findheadpos_last_mdl ~= ent:GetModel() then
		ent.findheadpos_head_bone = nil
		ent.findheadpos_head_attachment = nil
		ent.findheadpos_last_mdl = ent:GetModel()
	end

	if not ent.findheadpos_head_bone then
		for i = 0, ent:GetBoneCount() or 0 do
			local name = ent:GetBoneName(i):lower()
			if name:find("head", nil, true) then
				ent.findheadpos_head_bone = i
				break
			end
		end
	end

	if ent.findheadpos_head_bone then
		local m = ent:GetBoneMatrix(ent.findheadpos_head_bone)
		if m then
			local pos = m:GetTranslation()
			if pos ~= ent:GetPos() then
				return pos, m:GetAngles()
			end
		end
	else
		if not ent.findheadpos_attachment_eyes then
			ent.findheadpos_head_attachment = ent:GetAttachments().eyes or ent:GetAttachments().forward
		end

		if ent.findheadpos_head_attachment then
			local angpos = ent:GetAttachment(ent.findheadpos_head_attachment)
			return angpos.Pos, angpos.Ang
		end
	end

	return ent:EyePos(), ent:EyeAngles()
end