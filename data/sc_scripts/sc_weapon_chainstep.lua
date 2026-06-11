--[[
This code is a reimplementation of TNE_CHAINSTEP_LUA.lua from TNE
]]

local vter = mods.multiverse.vter

mods.multiverse.weaponTagParsers = mods.multiverse.weaponTagParsers or {}
local weaponTagParsers = mods.multiverse.weaponTagParsers

mods.sc = mods.sc or {}
mods.sc.chainstep = mods.sc.chainstep or {}

local chainstepWeaponList = mods.sc.chainstep

table.insert(weaponTagParsers, function(weaponNode)
	local nameAttr = weaponNode:first_attribute("name")
	if not nameAttr then return end

	local weaponName = nameAttr:value()

	local tagNode = weaponNode:first_node("sc-chainstep")
	if not tagNode then return end

	local fireThresholdAttr = tagNode:first_attribute("fireThreshold")
	local chainStepAttr = tagNode:first_attribute("chainStep")

	if not fireThresholdAttr or not chainStepAttr then return end

	local fireThreshold = tonumber(fireThresholdAttr:value())
	local chainStep = tonumber(chainStepAttr:value())

	if not fireThreshold or not chainStep or chainStep <= 0 then return end

	chainstepWeaponList[weaponName] = {
		fireThreshold = fireThreshold,
		chainStep = chainStep
	}
end)

--local chainWeaponList = { }
--chainWeaponList["TNE_FOCUS_CAPACITOR"] = { fireThreshold = 7, chainStep = 3.5 }
--chainWeaponList["IRRADIATE_BEAM"] = { fireThreshold = 7, chainStep = 3.5 }
--chainWeaponList["TNE_POLARSTAR_4"] = { fireThreshold = 10, chainStep = 6 }
--chainWeaponList["TNE_BEAM_CAPACITOR"] = { fireThreshold = 11, chainStep = 8 }
--chainWeaponList["TNE_CRYSTAL_SPEAR"] = { fireThreshold = 8, chainStep = 3 }
--chainWeaponList["TNE_CRYSTAL_SPEAR_ELITE"] = { fireThreshold = 8, chainStep = 3 }

------------------------------------------------------------------------------------

script.on_internal_event(Defines.InternalEvents.ON_TICK, function()
	
	local weapons = {}
	pcall(function() weapons[0] = Hyperspace.ships.player.weaponSystem.weapons end)
	pcall(function() weapons[1] = Hyperspace.ships.enemy.weaponSystem.weapons end)

	for i = 0, 1, 1 do
		if weapons[i] then
			for weapon in vter(weapons[i]) do
				local chainWeapon = chainstepWeaponList[weapon and weapon.blueprint and weapon.blueprint.name]

				if chainWeapon then
					local chargeRate = weapon.cooldown.second / weapon.baseCooldown
					local fireThres = chainWeapon.fireThreshold * chargeRate
					local step = chainWeapon.chainStep * chargeRate

					if (weapon.cooldown.first >= fireThres) then
						weapon.chargeLevel = 1
					else
						weapon.chargeLevel = 0
					end

					local overCharge = math.floor(math.max(weapon.cooldown.first - fireThres, 0) / step)
					if (weapon.cooldown.first >= weapon.cooldown.second) then
						overCharge = weapon.blueprint.boostPower.count
					end
					weapon.boostLevel = overCharge
				end
			end
		end
	end

end)