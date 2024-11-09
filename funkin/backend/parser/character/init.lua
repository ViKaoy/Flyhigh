local f = "funkin.backend.parser.character."

local CharacterParser = {}

local psych = require(f .. "psych")
local love = require(f .. "love")
local vslice = require(f .. "vslice")

local base = {
	anims = {
		{
			name = nil,
			prefix = nil,
			indices = nil,
			offsets = {0, 0}
			asset = nil,
			fps = 24,
			loop = false
		}
	},
	pos = {0, 0},
	camPos = {0, 0},
	singDur = 4,
	danceBeats = 2,

	flipX = false,
	icon = "face",
	sprite = "characters/BOYFRIEND",
	antialiasing = true,
	scale = 1
}

for _, module in pairs({psych, love, vslice}) do
	module.base = base
end

function CharacterParser:get(charName)
	return paths.getJSON("data/characters/" .. charName)
end

function CharacterParser:getParser(data)
	if data.version ~= nil then
		return vslice
	elseif data.animations and data.animations[1]
		and data.animations[1].offsets then
		return psych
	end
	return love
end

return CharacterParser
