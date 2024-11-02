local Events = require "funkin.backend.scripting.events"

---@class PlayState:State
local PlayState = State:extend("PlayState")
PlayState.defaultDifficulty = "normal"

PlayState.inputDirections = {
	note_left = 0,
	note_down = 1,
	note_up = 2,
	note_right = 3
}
PlayState.keysControls = {}
for control, key in pairs(PlayState.inputDirections) do
	PlayState.keysControls[key] = control
end

PlayState.SONG = nil
PlayState.songDifficulty = ""

PlayState.storyPlaylist = {}
PlayState.storyMode = false
PlayState.storyWeek = ""
PlayState.storyScore = 0
PlayState.storyWeekFile = ""

PlayState.seenCutscene = false
PlayState.canFadeInReceptors = true
PlayState.prevCamFollow = nil

function PlayState.loadSong(song, diff)
	diff = diff or PlayState.defaultDifficulty
	PlayState.songDifficulty = diff

	PlayState.SONG = API.chart.parse(song, diff)

	return true
end

function PlayState:new(storyMode, song, diff)
	PlayState.super.new(self)

	if storyMode ~= nil then
		PlayState.storyMode = storyMode
		PlayState.storyWeek = ""
	end

	if song ~= nil then
		if storyMode and type(song) == "table" and #song > 0 then
			PlayState.storyPlaylist = song
			song = song[1]
		end
		if not PlayState.loadSong(song, diff) then
			setmetatable(self, TitleState)
			TitleState.new(self)
		end
	end
end

function PlayState:enter()
	if PlayState.SONG == nil then PlayState.loadSong("test") end
	PlayState.SONG.skin = util.getSongSkin(PlayState.SONG)

	local songName = paths.formatToSongPath(PlayState.SONG.song)

	local conductor = Conductor():setSong(PlayState.SONG)
	conductor.time = - (conductor.crotchet * 5)
	conductor.onStep = bind(self, self.step)
	conductor.onBeat = bind(self, self.beat)
	conductor.onSection = bind(self, self.section)
	PlayState.conductor = conductor

	self.skipConductor = false

	NoteModifier.reset()

	self.timer = TimerManager()
	self.tween = Tween()
	self.camPosTween = nil

	self.scripts = ScriptsHandler()
	self.scripts:loadDirectory("data/scripts", "data/scripts/" .. songName, "songs/" .. songName)

	self.events = table.clone(PlayState.SONG.events)
	self.eventScripts = {}
	for _, e in ipairs(self.events) do
		local scriptPath = "data/events/" .. e.e:gsub(" ", "-"):lower()
		if not self.eventScripts[e.e] then
			self.eventScripts[e.e] = Script(scriptPath)
			self.eventScripts[e.e].belongsTo = e.e
			self.scripts:add(self.eventScripts[e.e])
		end
	end

	if Discord then self:updateDiscordRPC() end

	self.startingSong = true
	self.startedCountdown = false
	self.doCountdownAtBeats = nil
	self.lastCountdownBeats = nil

	self.isDead = false
	GameOverSubstate.resetVars()

	self.usedBotPlay = ClientPrefs.data.botplayMode
	self.downScroll = ClientPrefs.data.downScroll
	self.middleScroll = ClientPrefs.data.middleScroll

	self.playback = 1
	self.timer.timeScale = 1
	self.tween.timeScale = 1

	self.scripts:set("bpm", self.conductor.bpm)
	self.scripts:set("crotchet", self.conductor.crotchet)
	self.scripts:set("stepCrotchet", self.conductor.stepCrotchet)

	self.scripts:call("create")

	self.camNotes = Camera() --Camera will be changed to ActorCamera once that class is done
	self.camHUD = Camera()
	self.camOther = Camera()
	game.cameras.add(self.camHUD, false)
	game.cameras.add(self.camNotes, false)
	game.cameras.add(self.camOther, false)

	self.camHUD.bgColor[4] = ClientPrefs.data.backgroundDim / 100

	if game.sound.music then game.sound.music:reset(true) end
	game.sound.loadMusic(paths.getInst(songName))
	game.sound.music:setLooping(false)
	game.sound.music:setVolume(ClientPrefs.data.musicVolume / 100)
	game.sound.music.onComplete = function() self:endSong() end

	self.stage = Stage(PlayState.SONG.stage)
	self:add(self.stage)
	self.scripts:add(self.stage.script)

	if PlayState.SONG.gfVersion ~= "" then
		self.gf = Character(self.stage.gfPos.x, self.stage.gfPos.y,
			PlayState.SONG.gfVersion, false)
		self.gf:setScrollFactor(0.95, 0.95)
		self:add(self.gf)
		self.scripts:add(self.gf.script)
	end

	if PlayState.SONG.player2 ~= "" then
		self.dad = Character(self.stage.dadPos.x, self.stage.dadPos.y,
			PlayState.SONG.player2, false)
		self:add(self.dad)
		self.scripts:add(self.dad.script)
	end

	if PlayState.SONG.player1 ~= "" then
		self.boyfriend = Character(self.stage.boyfriendPos.x,
			self.stage.boyfriendPos.y, PlayState.SONG.player1,
			true)
		self:add(self.boyfriend)
		self.scripts:add(self.boyfriend.script)
	end

	self:add(self.stage.foreground)

	self.judgeSprites = Judgements(game.width / 3, 264, PlayState.SONG.skin)
	self:add(self.judgeSprites)

	game.camera.zoom, self.camZoom, self.camZooming,
	self.camZoomSpeed, self.camSpeed, self.camTarget =
		self.stage.camZoom, self.stage.camZoom, false,
		self.stage.camZoomSpeed, self.stage.camSpeed
	if PlayState.prevCamFollow then
		self.camFollow = PlayState.prevCamFollow
		PlayState.prevCamFollow = nil
	else
		self.camFollow = {
			x = 0,
			y = 0,
			tweening = false,
			set = function(this, x, y)
				this.x = x
				this.y = y
			end
		}
	end

	local playerVocals, enemyVocals, volume =
		paths.getVoices(songName, PlayState.SONG.player1, true)
		or paths.getVoices(songName, "Player", true)
		or paths.getVoices(songName, nil, true),
		paths.getVoices(songName, PlayState.SONG.player2, true)
		or paths.getVoices(songName, "Opponent", true),
		ClientPrefs.data.vocalVolume / 100
	if playerVocals then
		playerVocals = game.sound.load(playerVocals)
		playerVocals:setVolume(volume)
	end
	if enemyVocals then
		enemyVocals = game.sound.load(enemyVocals)
		enemyVocals:setVolume(volume)
	end
	local y, volume, cam = game.height / 2, ClientPrefs.data.vocalVolume / 100, {self.camNotes}
	self.playerNotefield = Notefield(0, y, 4, PlayState.SONG.skin,
		self.boyfriend, playerVocals, PlayState.SONG.speed)
	self.enemyNotefield = Notefield(0, y, 4, PlayState.SONG.skin,
		self.dad, enemyVocals, PlayState.SONG.speed)

	self.playerNotefield.bot = ClientPrefs.data.botplayMode
	self.enemyNotefield.canSpawnSplash = false
	self.playerNotefield.cameras, self.enemyNotefield.cameras = cam, cam

	self.notefields = {self.playerNotefield, self.enemyNotefield, {character = self.gf}}
	self:positionNotefields()

	self.playerNotefield:generateInputSignals()
	for _, notefield in ipairs(self.notefields) do
		if notefield.is then
			notefield.onNoteHit:add(bind(self, self.goodNoteHit))
			notefield.onSustainHit:add(bind(self, self.goodSustainHit))
			notefield.onNoteMiss:add(bind(self, self.miss))
			notefield.onNoteMash:add(function()
				self.health = self.health - 0.0896
			end)
		end
	end

	for _, n in ipairs(PlayState.SONG.notes.enemy) do
		self:generateNote(self.enemyNotefield, n)
	end
	for _, n in ipairs(PlayState.SONG.notes.player) do
		self:generateNote(self.playerNotefield, n)
	end
	self:add(self.enemyNotefield)
	self:add(self.playerNotefield)

	local notefield
	for i, event in ipairs(self.events) do
		if event.t > 10 then
			break
		elseif event.e == "FocusCamera" then
			self:executeEvent(event)
			table.remove(self.events, i)
			break
		end
	end

	self.countdown = Countdown()
	self.countdown:screenCenter()
	self:add(self.countdown)

	local isPixel = PlayState.SONG.skin:endsWith("-pixel")
	local event = self.scripts:event("onCountdownCreation",
		Events.CountdownCreation({}, isPixel and {x = 7, y = 7} or {x = 1, y = 1}, not isPixel))
	if not event.cancelled then
		self.countdown.data = #event.data == 0 and {
			{
				sound = util.getSkinPath(PlayState.SONG.skin, "intro3", "sound"),
			},
			{
				sound = util.getSkinPath(PlayState.SONG.skin, "intro2", "sound"),
				image = util.getSkinPath(PlayState.SONG.skin, "ready", "image")
			},
			{
				sound = util.getSkinPath(PlayState.SONG.skin, "intro1", "sound"),
				image = util.getSkinPath(PlayState.SONG.skin, "set", "image")
			},
			{
				sound = util.getSkinPath(PlayState.SONG.skin, "introGo", "sound"),
				image = util.getSkinPath(PlayState.SONG.skin, "go", "image")
			}
		} or event.data
		self.countdown.scale = event.scale
		self.countdown.antialiasing = event.antialiasing
	end

	self.healthBar = HealthBar(self.boyfriend, self.dad)
	self.healthBar:screenCenter("x").y = game.height * (self.downScroll and 0.1 or 0.9)
	self:add(self.healthBar)

	local fontScore = paths.getFont("vcr.ttf", 16)
	self.scoreText = Text(0, 0, "", fontScore, Color.WHITE, "right")
	self.scoreText.outline.width = 1
	self.scoreText.antialiasing = false
	self:add(self.scoreText)

	for _, o in ipairs({
		self.judgeSprites, self.countdown, self.healthBar, self.scoreText
	}) do o.cameras = {self.camHUD} end

	self.health = 1

	if love.system.getDevice() == "Mobile" then
		local w, h = game.width / 4, game.height

		self.buttons = VirtualPadGroup()

		local left = VirtualPad("left", 0, 0, w, h, Color.PURPLE)
		local down = VirtualPad("down", w, 0, w, h, Color.BLUE)
		local up = VirtualPad("up", w * 2, 0, w, h, Color.LIME)
		local right = VirtualPad("right", w * 3, 0, w, h, Color.RED)

		self.buttons:add(left)
		self.buttons:add(down)
		self.buttons:add(up)
		self.buttons:add(right)
		self.buttons:set({
			fill = "line",
			lined = false,
			blend = "add",
			releasedAlpha = 0,
			cameras = {self.camOther},
			config = {round = {0, 0}}
		})
	end

	if self.buttons then self.buttons:disable() end

	self.lastTick = love.timer.getTime()

	self.bindedKeyPress = bind(self, self.onKeyPress)
	controls:bindPress(self.bindedKeyPress)

	self.bindedKeyRelease = bind(self, self.onKeyRelease)
	controls:bindRelease(self.bindedKeyRelease)

	if self.downScroll then
		for _, notefield in ipairs(self.notefields) do
			if notefield.is then notefield.downscroll = true end
		end
	end
	self:positionText()

	if self.storyMode and not PlayState.seenCutscene then
		PlayState.seenCutscene = true

		self.cutscene = Cutscene(false, function(event)
			local skipCountdown = event and event.params[1] or false
			if skipCountdown then
				self:startSong(0)
				if self.buttons then self:add(self.buttons) end
				for _, notefield in ipairs(self.notefields) do
					if notefield.is and PlayState.canFadeInReceptors then
						notefield:fadeInReceptors()
					end
				end
				PlayState.canFadeInReceptors = false
			else
				self:startCountdown()
			end
			if not self.cutscene then return end
			self.cutscene:destroy()
			self.cutscene = nil
		end)
	else
		self:startCountdown()
	end
	self:recalculateRating()

	-- PRELOAD STUFF TO GET RID OF THE FATASS LAGS!!
	local path = "skins/" .. PlayState.SONG.skin .. "/"
	for _, r in ipairs(Notefield.ratings) do paths.getImage(path .. r.name) end
	for _, num in ipairs({"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "negative"}) do
		paths.getImage(path .. "num" .. num)
	end
	local sprite
	for i, part in pairs(paths.getSkin(PlayState.SONG.skin)) do
		sprite = part.sprite
		if sprite then paths.getImage(path .. sprite) end
	end
	if ClientPrefs.data.hitSound > 0 then paths.getSound("hitsound") end

	PlayState.super.enter(self)
	collectgarbage()

	self.scripts:call("postCreate")

	game.camera:follow(self.camFollow, nil, 2.4 * self.camSpeed)
	game.camera:snapToTarget()
end

function PlayState:positionNotefields()
	if self.middleScroll then
		self.playerNotefield:screenCenter("x")

		for _, notefield in ipairs(self.notefields) do
			if notefield.is and notefield ~= self.playerNotefield then
				notefield.visible = false
			end
		end
	else
		local baseX = 44
		self.playerNotefield.x = game.width / 2 + baseX
		self.enemyNotefield.x = baseX

		for _, notefield in ipairs(self.notefields) do
			if notefield.is then notefield.visible = true end
		end
	end
end

function PlayState:positionText()
	self.scoreText.x, self.scoreText.y = self.healthBar.x + self.healthBar.bg.width - 190, self.healthBar.y + 30
end

function PlayState:generateNote(notefield, n)
	local sustainTime = n.l or 0
	if sustainTime > 0 then
		sustainTime = math.max(sustainTime / 1000, 0.125)
	end
	local note = notefield:makeNote(n.t / 1000, n.d % 4, sustainTime, n.k)
	if n.gf then note.character = self.gf end
end

function PlayState:startCountdown()
	if self.buttons then self:add(self.buttons) end

	local event = self.scripts:call("startCountdown")
	if event == Script.Event_Cancel then return end

	self:setPlayback(ClientPrefs.data.playback)

	if not self.conductor then return end
	self.doCountdownAtBeats = -4
	self.startedCountdown = true
	self.countdown.duration = self.conductor.crotchet / 1000
	self.countdown.playback = 1

	for _, notefield in ipairs(self.notefields) do
		if notefield.is and PlayState.canFadeInReceptors then
			notefield:fadeInReceptors()
		end
	end
	PlayState.canFadeInReceptors = false
end

function PlayState:setPlayback(playback)
	playback = playback or self.playback
	game.sound.music:setPitch(playback)

	local lastVocals
	for _, notefield in ipairs(self.notefields) do
		if notefield.vocals and lastVocals ~= notefield.vocals then
			notefield.vocals:setPitch(playback)
			lastVocals = notefield.vocals
		end
	end
	lastVocals = nil

	self.playback = playback
	self.timer.timeScale = playback
	self.tween.timeScale = playback
end

function PlayState:playSong(daTime)
	self:setPlayback(self.playback)

	if daTime then game.sound.music:seek(daTime) end
	game.sound.music:play()

	local time, lastVocals = game.sound.music:tell()
	for _, notefield in ipairs(self.notefields) do
		if notefield.vocals and lastVocals ~= notefield.vocals then
			notefield.vocals:seek(time)
			notefield.vocals:play()
			lastVocals = notefield.vocals
		end
	end
	lastVocals = nil
	self.conductor.time = time * 1000

	self.paused = false
end

function PlayState:pauseSong()
	game.sound.music:pause()
	local lastVocals
	for _, notefield in ipairs(self.notefields) do
		if notefield.vocals and lastVocals ~= notefield.vocals then
			notefield.vocals:pause()
			lastVocals = notefield.vocals
		end
	end
	lastVocals = nil

	self.paused = true
end

function PlayState:resyncSong()
	local time, rate = game.sound.music:tell(), math.max(self.playback, 1)
	if math.abs(time - self.conductor.time / 1000) > 0.015 * rate then
		self.conductor.time = time * 1000
	end
	local maxDelay, vocals, lastVocals = 0.0091 * rate
	for _, notefield in ipairs(self.notefields) do
		vocals = notefield.vocals
		if vocals and lastVocals ~= vocals and vocals:isPlaying()
			and math.abs(time - vocals:tell()) > maxDelay then
			vocals:seek(time)
			lastVocals = vocals
		end
	end
	lastVocals = nil
end

function PlayState:getCameraPosition(char)
	local camX, camY = char:getMidpoint()
	if char == self.gf then
		camX, camY = camX - char.cameraPosition.x + self.stage.gfCam.x,
			camY - char.cameraPosition.y + self.stage.gfCam.y
	elseif char.isPlayer then
		camX, camY = camX - 100 - char.cameraPosition.x + self.stage.boyfriendCam.x,
			camY - 100 + char.cameraPosition.y + self.stage.boyfriendCam.y
	else
		camX, camY = camX + 150 + char.cameraPosition.x + self.stage.dadCam.x,
			camY - 100 + char.cameraPosition.y + self.stage.dadCam.y
	end
	return camX, camY
end

function PlayState:cameraMovement(ox, oy, ease, time)
	local event = self.scripts:event("onCameraMove", Events.CameraMove(self.camTarget))
	local camX, camY = (ox or 0) + event.offset.x, (oy or 0) + event.offset.y
	if self.camPosTween then
		self.camPosTween:cancel()
	end
	if ease then
		if game.camera.followLerp then
			game.camera:follow(self.camFollow, nil)
		end
		self.camPosTween = self.tween:tween(self.camFollow, {x = camX, y = camY}, time, {
			ease = Ease[ease],
			onComplete = function()
				self.camFollow.tweening = false
			end})
	else
		if not game.camera.followLerp then
			game.camera:follow(self.camFollow, nil, 2.4 * self.camSpeed)
		end
		self.camPosTween = nil
		self.camFollow:set(camX, camY)
	end
end

function PlayState:step(s)
	if self.skipConductor then return end

	if not self.startingSong then
		self:resyncSong()

		if Discord then
			coroutine.wrap(PlayState.updateDiscordRPC)(self)
		end
	end

	self.scripts:set("curStep", s)
	self.scripts:call("step", s)
	self.scripts:call("postStep", s)
end

function PlayState:beat(b)
	if self.skipConductor then return end

	self.scripts:set("curBeat", b)
	self.scripts:call("beat", b)

	local character
	for _, notefield in ipairs(self.notefields) do
		character = notefield.character
		if character then character:beat(b) end
	end

	local val, healthBar = 1.2, self.healthBar
	healthBar.iconScale = val
	healthBar.iconP1:setScale(val)
	healthBar.iconP2:setScale(val)

	self.scripts:call("postBeat", b)
end

function PlayState:section(s)
	if self.skipConductor then return end

	self.scripts:set("curSection", s)
	self.scripts:call("section", s)

	self.scripts:set("bpm", self.conductor.bpm)
	self.scripts:set("crotchet", self.conductor.crotchet)
	self.scripts:set("stepCrotchet", self.conductor.stepCrotchet)

	if self.camZooming and game.camera.zoom < 1.35 then
		game.camera.zoom = game.camera.zoom + 0.015
		self.camHUD.zoom = self.camHUD.zoom + 0.03
	end

	self.scripts:call("postSection", s)
end

function PlayState:focus(f)
	self.scripts:call("focus", f)
	if Discord and love.autoPause then self:updateDiscordRPC(not f) end
	self.scripts:call("postFocus", f)
end

function PlayState:executeEvent(event)
	for _, s in pairs(self.eventScripts) do
		if s.belongsTo == event.e then s:call("event", event) end
	end
	self.scripts:call("onEvent", event.e, event.v)
end

function PlayState:doCountdown(beat)
	if self.lastCountdownBeats == beat then return end
	self.lastCountdownBeats = beat

	if beat > #self.countdown.data then
		self.doCountdownAtBeats = nil
	else
		self.countdown:doCountdown(beat)
	end
end

function PlayState:update(dt)
	self.timer:update(dt)
	self.tween:update(dt)

	if self.cutscene then self.cutscene:update(dt) end

	self.lastTick = love.timer.getTime()
	dt = dt * self.playback

	if self.startedCountdown then
		self.conductor.time = self.conductor.time + dt * 1000

		if self.startingSong and self.conductor.time >= 0 then
			self.startingSong = false
			self.camZooming = true

			self:playSong(0)
			self:section(0)
			self.scripts:call("songStart")
		else
			local noFocus, events, e = true, self.events
			while events[1] do
				e = events[1]
				if e.t <= self.conductor.time then
					self:executeEvent(e)
					table.remove(events, 1)
					if e.e == "FocusCamera" then noFocus = false end
				else
					break
				end
			end
			if noFocus and self.camTarget and game.camera.followLerp then
				self:cameraMovement(self:getCameraPosition(self.camTarget))
			end
		end

		self.conductor:update()
		if self.skipConductor then self.skipConductor = false end

		if self.startingSong and self.doCountdownAtBeats then
			self:doCountdown(math.floor(
				self.conductor.currentBeatFloat - self.doCountdownAtBeats + 1
			))
		end
	end

	self.scripts:call("update", dt)
	PlayState.super.update(self, dt)

	if self.camZooming then
		game.camera.zoom = util.coolLerp(game.camera.zoom, self.camZoom, 6, dt * self.camZoomSpeed)
		self.camHUD.zoom = util.coolLerp(self.camHUD.zoom, 1, 6, dt * self.camZoomSpeed)
	end
	self.camNotes.zoom = self.camHUD.zoom

	self.healthBar.value = util.coolLerp(self.healthBar.value, self.health, 16, dt)
	if not self.isDead and self.healthBar.value <= 0 then self:tryGameOver() end

	if self.startedCountdown and not self.isDead and controls:pressed("reset") then
		self:tryGameOver()
	end

	self.scripts:call("postUpdate", dt)
end

function PlayState:draw()
	self.scripts:call("draw")
	PlayState.super.draw(self)
	self.scripts:call("postDraw")
end

function PlayState:onSettingChange(category, setting)
	game.camera.freezed = false
	self.camNotes.freezed = false
	self.camHUD.freezed = false

	if category == "gameplay" then
		switch(setting, {
			["downScroll"] = function()
				local downscroll = ClientPrefs.data.downScroll
				for _, notefield in ipairs(self.notefields) do
					if notefield.is then notefield.downscroll = downscroll end
				end

				self.healthBar.y = game.height * (downscroll and 0.1 or 0.9)
				self:positionText()
				self.downScroll = downscroll
			end,
			["middleScroll"] = function()
				self.middleScroll = ClientPrefs.data.middleScroll
				self:positionNotefields()
			end,
			["botplayMode"] = function()
				self.playerNotefield.bot = ClientPrefs.data.botplayMode
				self.usedBotplay = true
				self:recalculateRating()
			end,
			["backgroundDim"] = function()
				self.camHUD.bgColor[4] = ClientPrefs.data.backgroundDim / 100
			end,
			["playback"] = function()
				self:setPlayback(ClientPrefs.data.playback)
			end
		})

		game.sound.music:setVolume(ClientPrefs.data.musicVolume / 100)
		local volume, vocals = ClientPrefs.data.vocalVolume / 100
		for _, notefield in ipairs(self.notefields) do
			vocals = notefield.vocals
			if vocals then vocals:setVolume(volume) end
		end
	elseif category == "controls" then
		controls:unbindPress(self.bindedKeyPress)
		controls:unbindRelease(self.bindedKeyRelease)

		self.bindedKeyPress = bind(self, self.onKeyPress)
		controls:bindPress(self.bindedKeyPress)

		self.bindedKeyRelease = bind(self, self.onKeyRelease)
		controls:bindRelease(self.bindedKeyRelease)
	end

	self.scripts:call("onSettingChange", category, setting)
end

function PlayState:goodNoteHit(note, time, rating)
	self.scripts:call("goodNoteHit", note, rating)

	local notefield, dir, isSustain =
		note.parent, note.direction, note.sustain
	local event = self.scripts:event("onNoteHit",
		Events.NoteHit(notefield, note,
			note.character or notefield.character, rating))
	if not event.cancelled and not note.wasGoodHit then
		note.wasGoodHit = true

		if event.unmuteVocals then
			local vocals = notefield.vocals or self.playerNotefield.vocals
			if vocals then vocals:setVolume(ClientPrefs.data.vocalVolume / 100) end
		end

		local char = event.character
		if char and not event.cancelledAnim then
			local lastSustain, type = notefield.lastSustain, note.type
			char.isOnSustain = lastSustain or note.sustain
			if char.isOnSustain then char._time = char._loopTime end
			if type ~= "alt" then type = nil end
			if lastSustain and not isSustain
				and lastSustain.sustainTime > note.sustainTime then
				local dir = lastSustain.direction
				if char.dirAnim ~= dir then
					char:sing(dir, type, false)
				end
			else
				char:sing(dir, type)
			end
		end

		notefield.lastSustain = isSustain and note or nil
		if (rating.name == "bad" or rating.name == "shit") then
			note:ghost()
		else
			if not isSustain then notefield:removeNote(note) end
		end

		local receptor = notefield.receptors[dir + 1]
		if receptor then
			if not event.strumGlowCancelled then
				local snap = notefield.bot and (receptor.holdTime ~= 0 and receptor.holdTime) or 0
				receptor:play("confirm", true)
				if not note.sustain then
					receptor.holdTime = snap ~= 0 and snap or 0.25
				end
				if ClientPrefs.data.noteSplash and notefield.canSpawnSplash and rating.splash then
					receptor:spawnSplash()
				end
			end
			if isSustain and not event.coverSpawnCancelled then
				receptor:spawnCover(note)
			end
		end

		if self.playerNotefield == notefield then
			self.health = math.min(self.health + 0.023, 2)
			self:recalculateRating(rating.name)

			local hitSoundVolume = ClientPrefs.data.hitSound
			if hitSoundVolume > 0 then
				game.sound.play(paths.getSound("hitsound"), hitSoundVolume / 100)
			end
		end
	end

	self.scripts:call("postGoodNoteHit", note, rating)
end

function PlayState:goodSustainHit(note, time, fullyHeldSustain)
	self.scripts:call("goodSustainHit", note)

	local notefield, dir, fullScore =
		note.parent, note.direction, fullyHeldSustain ~= nil
	local event = self.scripts:event("onSustainHit",
		Events.NoteHit(notefield, note,
			note.character or notefield.character))
	if not event.cancelled and not note.wasGoodSustainHit then
		note.wasGoodSustainHit = true
		local char = note.character or notefield.character
		if char then char.isOnSustain = false end
		self:recalculateRating()

		if not event.cancelledAnim then
			notefield:resetStroke(dir + 1, fullyHeldSustain)
		end
		if fullScore then notefield:removeNote(note) end
	end

	self.scripts:call("postGoodSustainHit", note)
end

-- dir can be nil for non-ghost-tap
function PlayState:miss(note, dir)
	local ghostMiss = dir ~= nil
	if not ghostMiss then dir = note.direction end

	local funcParam = ghostMiss and dir or note
	self.scripts:call(ghostMiss and "miss" or "noteMiss", funcParam)

	local notefield = ghostMiss and note or note.parent
	local event = self.scripts:event(ghostMiss and "onMiss" or "onNoteMiss",
		Events.Miss(notefield, dir, ghostMiss and nil or note,
			note.character or notefield.character))
	if not event.cancelled and (ghostMiss or not note.tooLate) then
		if not ghostMiss then
			note.tooLate = true
			note.killTime = 1
		end

		if event.muteVocals and notefield.vocals then notefield.vocals:setVolume(0) end

		if event.triggerSound then
			util.playSfx(paths.getSound("gameplay/missnote" .. love.math.random(1, 3)),
				love.math.random(1, 2) / 10)
		end

		local char = event.character
		if char and not event.cancelledAnim then
			char:sing(dir, "miss")
			char.isOnSustain = false
		end

		if notefield == self.playerNotefield then
			local combo = self.playerNotefield.combo
			if self.gf and not event.cancelledSadGF and combo >= 10
				and self.gf.__animations.sad then
				self.gf:playAnim("sad", true)
				self.gf.lastHit = notefield.time * 1000
				self.gf.isOnSustain = false
			end

			self.health = math.max(self.health - (ghostMiss and 0.04 or 0.0475), 0)
			self:recalculateRating()
			self:popUpScore()
		end
	end

	self.scripts:call(ghostMiss and "postMiss" or "postNoteMiss", funcParam)
end

function PlayState:recalculateRating(rating)
	local score = self.playerNotefield.score
	self.scoreText.content = "Score: " .. util.formatNumber(math.floor(score)) ..
		(ClientPrefs.data.botplayMode and " [BOTPLAY]" or "")
	if rating then self:popUpScore(rating) end
end

function PlayState:popUpScore(rating)
	local event = self.scripts:event('onPopUpScore', Events.PopUpScore())
	if not event.cancelled then
		self.judgeSprites.ratingVisible = not event.hideRating
		self.judgeSprites.comboNumVisible = not event.hideScore
		self.judgeSprites:spawn(rating, self.playerNotefield.combo)
	end
end

function PlayState:tryPause()
	local event = self.scripts:call("pause")
	if event ~= Script.Event_Cancel then
		game.camera:unfollow()
		game.camera:freeze()
		self.camNotes:freeze()
		self.camHUD:freeze()

		self:pauseSong()

		if self.buttons then self:remove(self.buttons) end

		local pause = PauseSubstate(self.cutscene)
		pause.cameras = {self.camOther}
		self:openSubstate(pause)
	end
end

function PlayState:tryGameOver()
	local event = self.scripts:event("onGameOver", Events.GameOver())
	if not event.cancelled then

		if event.pauseSong then self:pauseSong() end
		self.paused = event.pauseGame

		self.camHUD.visible, self.camNotes.visible = false, false
		self.boyfriend.visible = false

		if self.buttons then self:remove(self.buttons) end

		GameOverSubstate.characterName = event.characterName
		GameOverSubstate.deathSoundName = event.deathSoundName
		GameOverSubstate.loopSoundName = event.loopSoundName
		GameOverSubstate.endSoundName = event.endSoundName
		GameOverSubstate.deaths = GameOverSubstate.deaths + 1

		self.scripts:call("gameOverCreate")

		self:openSubstate(GameOverSubstate(self.stage.boyfriendPos.x,
			self.stage.boyfriendPos.y))
		self.isDead = true

		self.scripts:call("postGameOverCreate")
	end
end

function PlayState:getKeyFromEvent(type, key)
	if self.substate and not self.persistentUpdate then return end
	local controls = controls:getControlsFromSource(type .. ":" .. key)
	if not controls then return end

	for _, control in pairs(controls) do
		local dir = PlayState.inputDirections[control]
		if dir ~= nil then
			return dir
		elseif control == "pause" then
			return "pause"
		end
	end
	return -1
end

function PlayState:onKeyPress(key, t, a, b, time)
	key = self:getKeyFromEvent(t, key)

	if (self.startedCountdown or self.cutscene) and key == "pause" then
		self:tryPause()
		return
	end

	if type(key) ~= "number" then return end
	for _, notefield in ipairs(self.notefields) do
		if notefield.onKeyPress then
			notefield.onKeyPress:dispatch(key + 1, time, self.lastTick)
		end
	end
end

function PlayState:onKeyRelease(key, t, a, time)
	key = self:getKeyFromEvent(t, key)
	if type(key) ~= "number" then return end

	for _, notefield in ipairs(self.notefields) do
		if notefield.onKeyRelease then
			notefield.onKeyRelease:dispatch(key + 1)
		end
	end
end

function PlayState:closeSubstate()
	self.scripts:call("substateClosed")
	PlayState.super.closeSubstate(self)

	game.camera:unfreeze()
	self.camNotes:unfreeze()
	self.camHUD:unfreeze()

	game.camera:follow(self.camFollow, nil, 2.4 * self.camSpeed)

	if not self.startingSong then
		self:playSong()
		if Discord then self:updateDiscordRPC() end
	end

	if self.buttons then self:add(self.buttons) end

	self.scripts:call("postSubstateClosed")
end

function PlayState:endSong(skip)
	if skip == nil then skip = false end
	PlayState.seenCutscene = false
	self.startedCountdown = false

	if self.storyMode and not PlayState.seenCutscene and not skip then
		PlayState.seenCutscene = true
		self.cutscene = Cutscene(true, function(event)
			self:endSong(true)
			self.cutscene:destroy()
			self.cutscene = nil
		end)
		return
	end

	local event = self.scripts:call("endSong")
	if event == Script.Event_Cancel then return end
	game.sound.music.onComplete = nil

	local score = self.playerNotefield.score
	if not self.usedBotPlay then
		Highscore.saveScore(PlayState.SONG.song, score, self.songDifficulty)
	end

	game.sound.music:reset(true)
	if self.storyMode then
		PlayState.canFadeInReceptors = false
		if not self.usedBotPlay then
			PlayState.storyScore = PlayState.storyScore + score
		end

		table.remove(PlayState.storyPlaylist, 1)
		if #PlayState.storyPlaylist > 0 then
			game.sound.music:stop()

			if Discord then
				local detailsText = "Freeplay"
				if self.storyMode then detailsText = "Story Mode: " .. PlayState.storyWeek end

				Discord.changePresence({
					details = detailsText,
					state = 'Loading next song..'
				})
			end

			PlayState.loadSong(PlayState.storyPlaylist[1], PlayState.songDifficulty)
			game.resetState(true)
		else
			GameOverSubstate.deaths = 0
			PlayState.canFadeInReceptors = true
			if not self.usedBotPlay then
				Highscore.saveWeekScore(self.storyWeekFile, self.storyScore, self.songDifficulty)
			end

			local stickers = Stickers(nil, StoryMenuState())
			self:add(stickers)

			util.playMenuMusic()
		end
	else
		GameOverSubstate.deaths = 0
		PlayState.canFadeInReceptors = true
		game.camera:unfollow()

		local stickers = Stickers(nil, FreeplayState())
		self:add(stickers)

		util.playMenuMusic()
	end
	controls:unbindPress(self.bindedKeyPress)
	controls:unbindRelease(self.bindedKeyRelease)

	self.scripts:call("postEndSong")
end

function PlayState:updateDiscordRPC(paused)
	if not Discord then return end

	local detailsText = "Freeplay"
	if self.storyMode then detailsText = "Story Mode: " .. PlayState.storyWeek end

	local diff = PlayState.defaultDifficulty
	if PlayState.songDifficulty ~= "" then
		diff = PlayState.songDifficulty:gsub("^%l", string.upper)
	end

	if paused then
		Discord.changePresence({
			details = "Paused - " .. detailsText,
			state = PlayState.SONG.song .. ' - [' .. diff .. ']'
		})
		return
	end

	if self.startingSong or not game.sound.music or not game.sound.music:isPlaying() then
		Discord.changePresence({
			details = detailsText,
			state = PlayState.SONG.song .. ' - [' .. diff .. ']'
		})
	else
		local startTimestamp = os.time(os.date("*t"))
		local endTimestamp = (startTimestamp + game.sound.music:getDuration()) - self.conductor.time / 1000
		Discord.changePresence({
			details = detailsText,
			state = PlayState.SONG.song .. ' - [' .. diff .. ']',
			startTimestamp = math.floor(startTimestamp),
			endTimestamp = math.floor(endTimestamp)
		})
	end
end

function PlayState:leave()
	self.scripts:call("leave")

	PlayState.prevCamFollow = self.camFollow
	PlayState.conductor = nil

	controls:unbindPress(self.bindedKeyPress)
	controls:unbindRelease(self.bindedKeyRelease)

	self.scripts:call("postLeave")
	self.scripts:close()
end

return PlayState
