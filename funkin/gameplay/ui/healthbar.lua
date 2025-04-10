local HealthBar = SpriteGroup:extend("HealthBar")
HealthBar.automaticColor = true

function HealthBar:new(bfData, dadData, skin)
	HealthBar.super.new(self, 0, 0)

	self.maxHealth = 2

	self.bg = Sprite():loadTexture(paths.getImage("skins/default/healthBar"))
	self.bg:updateHitbox()

	self.bar = Bar(self.bg.x + 4, self.bg.y + 4,
		math.floor(self.bg.width - 8),
		math.floor(self.bg.height - 8), 0, self.maxHealth, true)

	self:add(self.bg)
	self:add(self.bar)

	local healthPercent = self.bar.percent
	self.iconP1, self.iconP2, self.iconScale =
		HealthIcon(bfData.icon, true, healthPercent),
		HealthIcon(dadData.icon, false, healthPercent),
		1

	local y = self.bar.y
	self.iconP1.y = self.bar.y - 75
	self.iconP2.y = self.bar.y - 75

	self.bar.color = self.automaticColor and HealthIcon.getDominant(bfData.icon)
		or bfData.healthColor or Color.fromHEX(0x66FF33)
	self.bar.color.bg = self.automaticColor and HealthIcon.getDominant(dadData.icon)
		or dadData.healthColor or Color.fromHEX(0xFF0000)

	self:add(self.iconP1)
	self:add(self.iconP2)

	self.value = 1
	self.bar:setValue(1)
end

function HealthBar:setColors(player, enemy)
	if player then self.bar.color = player end
	if enemy then self.bar.color.bg = enemy end
end

local iconOffset = 26
function HealthBar:update(dt)
	HealthBar.super.update(self, dt)
	self.bar:setValue(self.value)
	local lerpValue, healthPercent =
		util.coolLerp(self.iconScale, 1, 15, dt), self.bar.percent
	self.iconScale, self.iconP1.health, self.iconP2.health =
		lerpValue, healthPercent, healthPercent
	self.iconP1:setScale(lerpValue)
	self.iconP2:setScale(lerpValue)
	self.iconP1.x = self.bar.x + self.bar.width *
		(math.remapToRange(healthPercent, 0, 100, 100,
			0) * 0.01) + (150 * self.iconP1.scale.x - 150) / 2 - iconOffset
	self.iconP2.x = self.bar.x + (self.bar.width *
		(math.remapToRange(healthPercent, 0, 100, 100,
			0) * 0.01)) - (150 * self.iconP2.scale.x) / 2 - iconOffset * 2
end

function HealthBar:screenCenter(axes)
	if axes == nil then axes = "xy" end
	if axes:find("x") then self.x = (game.width - self.bg.width) / 2 end
	if axes:find("y") then self.y = (game.height - self.bg.height) / 2 end
	return self
end

function HealthBar:getWidth()
	return self.bg.width
end

function HealthBar:getHeight()
	return self.bg.height
end

return HealthBar
