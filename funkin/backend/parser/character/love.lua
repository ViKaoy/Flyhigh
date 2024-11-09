local love = {}
{
	"animations": [
		["singLEFT", "left", [], 24, false, [2, -2]],
		["singDOWN", "down", [], 24, false, [0, 1]],
		["singUP", "up", [], 24, false, [0, 0]],
		["singRIGHT", "right", [], 24, false, [-4, 0]],
		["idle", "idle", [], 24, false, [0, 0]]
	],
	"position": [-260, -60],
	"camera_points": [-40, 100],
	"flip_x": false,
	"icon": "4j",
	"sprite": "characters/4j",
	"antialiasing": true,
	"sing_duration": 4,
	"scale": 1
}
function love.parse(data)
	local char = table.clone(love.base)

	if data.animations then
		for _, anim in pairs(data.animations) do
end

return love
