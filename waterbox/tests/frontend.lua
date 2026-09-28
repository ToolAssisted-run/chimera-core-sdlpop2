-- frontend.lua - SDLPoP2 in Chimera itself: the project plays, and game.*
-- reads the core's properties by name. Job (CHIMERA_JOB): frames=, meta=, out=
local job = {}
for line in io.lines(os.getenv("CHIMERA_JOB")) do
	local k, v = line:match("^([^=]+)=(.*)$")
	if k then job[k] = v end
end
local meta = {}
local function finish(status)
	meta.status = status
	local f = io.open(job.meta, "w")
	for k, v in pairs(meta) do f:write(k .. "=" .. tostring(v) .. "\n") end
	f:close()
	client.exit()
end

local frames = tonumber(job.frames)
while emu.framecount() < frames do emu.frameadvance() end

meta.frames = emu.framecount()
meta.game_list = #game.list()
meta.level = game.get("Level")
meta.kid_x = game.get("Kid.X")
meta.kid_x_bytes = memory.read_s16_le(2, "Kid")
meta.kid_room = game.get("Kid.Room")
meta.room1_tile0 = game.get("Room 1.Tiles[0]")
meta.chars_hp1 = game.get("Chars.HP[1]")
meta.set_minutes = tostring(game.set("Minutes Left", 42))
meta.minutes_after_set = game.get("Minutes Left")
meta.unknown = tostring(game.get("No Such Property"))
local f = io.open(job.out .. "/kid.bin", "wb")
for i = 0, 63 do f:write(string.char(memory.readbyte(i, "Kid"))) end
f:close()
finish("OK")
