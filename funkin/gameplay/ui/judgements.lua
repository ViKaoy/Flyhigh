local Judgements = SpriteGroup:extend("Judgements")
Judgements.area = {width = 328, height = 134}

function Judgements:new(x, y, skin)
	Judgements.super.new(self, x, y)

	self.ratingVisible = true
	self.comboNumVisible = true

	self.msGroup = SpriteGroup()
	self:add(self.msGroup)

	self.skin = skin or "default"
	self.antialiasing = not skin:endsWith("-pixel")

	self.noStack = false
end

function Judgements:precache(ratings)
	local path = "skins/" .. self.skin .. "/"
	for _, r in ipairs(ratings) do paths.getImage(path .. r.name) end
	for _, num in ipairs({"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "negative"}) do
		paths.getImage(path .. "num" .. num)
	end
end

function Judgements:createSprite(name, scale, duration)
	local sprite = self:recycle()
	sprite:loadTexture(paths.getImage("skins/" .. self.skin .. "/" .. name))
	sprite:setGraphicSize(math.floor(sprite.width * scale))
	sprite.x, sprite.y = 0, 0
	sprite:updateHitbox()
	sprite.alpha = 1
	sprite.antialiasing = antialias

	sprite.moves = true
	sprite.velocity.x = 0
	sprite.velocity.y = 0
	sprite.acceleration.y = 0
	sprite.antialiasing = self.antialiasing

	local state = game.getState()
	state.tween:cancelTweensOf(sprite)
	if sprite._timer then
		sprite._timer:cancel()
		sprite._timer = nil
	end
	sprite._timer = Timer(state.timer):start(duration, function()
		state.tween:tween(sprite, {alpha = 0}, 0.2, {onComplete = function()
			sprite:kill()
		end})
	end)

	return sprite
end

function Judgements:spawn(rating, combo, timing)
	if not self.visible then return end

	local accel = PlayState.conductor.crotchet * 0.001
	if self.noStack then for _, member in ipairs(self.members) do member:kill() end end

	if rating and self.ratingVisible then
		local areaHeight = self.area.height / 2
		local ratingSpr = self:createSprite(rating, self.antialiasing and 0.65 or 4.2, accel)
		ratingSpr.x = (self.area.width - ratingSpr.width) / 2
		ratingSpr.y = (self.area.height - ratingSpr.height) / 2 - self.area.height / 3
		ratingSpr.acceleration.y = 550
		ratingSpr.velocity.y = ratingSpr.velocity.y - math.random(140, 175)
		ratingSpr.velocity.x = ratingSpr.velocity.x - math.random(0, 10)
		ratingSpr.visible = self.ratingVisible
	end

	local lastComboX = 0
	if combo and self.comboNumVisible and (combo > 9 or combo < 0) then
		combo = string.format(combo < 0 and "-%03d" or "%03d", math.abs(combo))
		local l, x, char, comboNum = #combo, 38
		for i = 1, l do
			char = combo:sub(i, i)
			comboNum = self:createSprite("num" .. (char == "-" and "negative" or char),
				self.antialiasing and 0.45 or 4.2, accel * 2)
			x, comboNum.x, comboNum.y = x + comboNum.width - 8,
				x, self.area.height - comboNum.height
			comboNum.acceleration.y, comboNum.velocity.x, comboNum.velocity.y = math.random(200, 300),
				math.random(-5.0, 5.0), comboNum.velocity.y - math.random(140, 160)
		end

		lastComboX = x
	end

	if timing then
		local char, x = nil, 0
		for i = #self.msGroup.members, 1, -1 do
			local spr = self.msGroup.members[i]
			spr:destroy()
			if spr._timer then spr._timer:cancel(); spr._timer = nil end
			if spr._tween then spr._tween:cancel(); spr._tween = nil end
			self.msGroup:remove(spr)
			spr = nil
		end
	
		self.msGroup.color = Color.fromHEX(0xC1CAFF)
		if timing > 0 then
			self.msGroup.color = Color.fromHEX(0xFF8D63)
		end
		self.msGroup.x = lastComboX + 30

		timing = tostring(timing)
		for i = 1, #timing + 1 do
			local c = timing:sub(i, i)
			if c ~= "-" then
				char = i == #timing + 1 and "ms" or "num" .. c

				local spr = Sprite()
				spr.velocity.x = 0
				spr.velocity.y = 0
				spr.acceleration.y = 0
				spr.moves = false
				spr.alpha = 1

				spr:loadTexture(paths.getImage("skins/" .. self.skin .. "/" .. char))
				spr:setGraphicSize(math.floor(spr.width * 0.4))
				spr:updateHitbox()
				spr.moves = true
				spr.acceleration.y = 300
				spr.velocity.y = - math.random(140, 170)
				spr.velocity.x = - math.random(-6, 4)
				x, spr.x, spr.y = x + spr.width, x, self.area.height - spr.height

				local state = game.getState()
				if spr._timer then spr._timer:cancel(); spr._timer = nil end
				spr._timer = Timer(state.timer):start(0.5, function()
					spr._tween = Tween.tween(spr, {alpha = 0}, 0.2, {
						onComplete = function() spr:kill() end
				}) end)
				self.msGroup:add(spr)
			end
		end
	end
end

function Judgements:screenCenter()
	self.x, self.y = (game.width - self.area.width) / 2,
		(game.height - self.area.height) / 2
	return self
end

return Judgements
