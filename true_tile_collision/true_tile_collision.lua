--Functions by NeZvers
local TIME_MULT		= 1											--For slow motion
local TILE_SIZE		= 16										--default size
local TILE_ROUND	= -TILE_SIZE + 1							--in case of bitwise calculations
local VIEW_SCALE	= 4											--hardcoded for prototyping
local JUMP_BUFFER	= 20										--buffer after player loses ground
local SLOPE_SPD1	= vmath.normalize(vmath.vector3(1,1,0))		--Multiplier for walking slopes
local SLOPE_SPD2	= vmath.normalize(vmath.vector3(1,0.5,0))	--Multiplier for walking slopes

--COLISION TILES
local solid1 = 1					--solid block
local solid2 = 2					--slope 45 righ
local solid3 = 3					--slope 45 left
local solid4 = 4					--slope 22.5 right 1/2
local solid5 = 5					--slope 22.5 right 2/2
local solid6 = 6					--slope 22.5 left 1/2
local solid7 = 7					--slope 22.5 left 2/2
local plat	 = 8					--Jumpthrough platform --NOT IMPLEMENTED

--Will be used as bitmasks to check buttons
local up     = 1
local down   = 2
local left   = 4
local right  = 8
local jump   = 16
local action = 32
local start  = 64

function debug_on(peakTrue)
	timer.delay(1, false, function()
		profiler.enable_ui(true)
		profiler.set_ui_mode(profiler.MODE_RECORD)
		if peakTrue then
			profiler.set_ui_mode(profiler.MODE_SHOW_PEAK_FRAME) -- comment this line to not show peak only
		end
	end)
end

function clamp(v, min, max)
	if v < min then v = min 
	elseif v > max then v = max end
	return v
end

function approach(start, ending, ammount)
	local result = nil
	if start > ending then 
		if start - ammount < ending then result = ending
		else result = start - ammount end
	elseif start < ending then
		if start + ammount > ending then result = ending
		else result = start + ammount end
	else result = ending end
	return result
end

function approach_alt(start, ending, ammount)
	local result = nil
	if start < ending then
		result = math.min(start + ammount, ending)
	else result = math.max(start - ammount, ending) end
	return result
end

function sign(v)
	if v > 0 then return 1
	elseif v < 0 then return -1
	else return 0 end
end

function div(a,b)
	return (a - a % b) / b
end

function round(v)
	return v + 0.5 - (v + 0.5) % 1
end

function round_n(val, multiple)
	return round(val/multiple)*multiple;
end

function round_2d(val)
	val.x = round(val.x)
	val.y = round(val.y)
	return val
end

function round_2d_n(val, multiple)
	val.x = round_n(val.x, multiple)
	val.y = round_n(val.y, multiple)
	return val
end

function lerp(from, to, ammount)
	return from+(to - from) *ammount
end

local ceil	= math.ceil																--Save floor function for simplicity
local floor	= math.floor															--save ceil function for simplicity
local band	= bit.band																--Save bitwise AND
local bor	= bit.bor																--Save bitwise OR
--INIT
function init_physics(inst, id, url, solidMap, solidLayer, tile_size, run_maxspeed, jump_speed, gravity)
	TILE_SIZE         = tile_size
	TILE_ROUND		  = -TILE_SIZE + 1
	inst.MY_ID		  = id
	inst.MY_URL		  = url
	inst.MY_POS		  = go.get_position(url)
	inst.START_POS	  = go.get_position(url)
	inst.WORLD_POS	  = vmath.vector3(0,0,0)
	inst.SOLIDMAP     = solidMap
	inst.SOLIDLAYER   = solidLayer
	inst.GRAVITY      = -gravity

	inst.START_JUMP   = jump_speed
	inst.RELEASE_JUMP = ceil(jump_speed / 3)
	inst.ACC          = run_maxspeed / 10		--Accelerate
	inst.ACCW         = run_maxspeed / 30		--Walk accelerate
	inst.MAX          = run_maxspeed			--max run speed
	--inst.MAXW         = run_maxspeed  * 25 / 64	--Max walk speed
	inst.DCC          = run_maxspeed * 9 / 64	--deaccelerate when no input
	--inst.AIR          = run_maxspeed * 2 / 64
	--inst.AIRW         = run_maxspeed * 1 / 128	--air walk speed
	--inst.AIRS         = run_maxspeed * 2 / 64 	--air stopping speed
	--inst.DRAG         = run_maxspeed * 9 / 64	--deaccelerate when no input
	inst.MAX_DOWN     = -jump_speed				--max fall speed
	inst.MAX_UP       = jump_speed				--max up speed just in case
	inst.WALLSPEED	  = -ceil(jump_speed/5)

	inst.spd          = vmath.vector3(0,0,0)

	inst.buttons	  = 0
	inst.xinput		  = 0								--for platformer
	inst.dir_input	  = vmath.vector3(0, 0, 0)		--for top-down
	inst.jmp_buf_tmr  = 0
	inst.last_wall    = 0
	inst.last_ledge	  = 0
	inst.hurtTimer    = 0
	inst.dashTimer    = 0
	
	--STATES
	inst.grounded	  = false
	inst.jumping	  = false
	inst.doubleJump   = false	--not included yet
	inst.dashing	  = false	--not included yet
	inst.wallsliding  = false
	inst.on_ledge	  = false
	inst.ledge_climb  = false	--not included yet
	inst.hurt		  = false	--not included yet

	--TRIGGERS					--Useful for triggering animations or states
	inst.landed		  = false	--True when happens collision with ground
	inst.ledge_trig   = false	--True for first frame ledge is grabbed
	inst.wallslide_trig = false	--True for first frame wallslide is triggered
	inst.wall_trig	  = false	--True when wall collision is triggered			(useful for enemy to turn arond)
	inst.cliff_trig	  = false	--True when cliff edge collision is triggered	(useful for enemy to turn around)
	inst.fast_fall	  = false	--True if falling is at max speed

	--HITBOX					--Need to be initiated with set_hitbox()
	inst.hitbox_l	  = 0
	inst.hitbox_r	  = 0
	inst.hitbox_t	  = 0
	inst.hitbox_b	  = 0
	inst.hitbox_hc    = 0
	inst.hitbox_vc    = 0
	inst.hitbox_ledge = 0
end

function set_hitbox(inst, hitbox_r, hitbox_l, hitbox_t, hitbox_b)
	inst.hitbox_l  = hitbox_l
	inst.hitbox_r  = hitbox_r
	inst.hitbox_t  = hitbox_t
	inst.hitbox_b  = hitbox_b
	inst.hitbox_hc = math.ceil((inst.hitbox_r + inst.hitbox_l)/2)
	inst.hitbox_vc = math.ceil((inst.hitbox_t + inst.hitbox_b)/2)
	inst.hitbox_ledge = inst.hitbox_t +1
end

function button_up(inst)     inst.buttons = bor(inst.buttons, up)     end
function button_down(inst)   inst.buttons = bor(inst.buttons, down)   end
function button_left(inst)   inst.buttons = bor(inst.buttons, left)   end
function button_right(inst)  inst.buttons = bor(inst.buttons, right)  end
function button_jump(inst)   inst.buttons = bor(inst.buttons, jump)   end
function button_action(inst) inst.buttons = bor(inst.buttons, action) end
function button_start(inst)  inst.buttons = bor(inst.buttons, start)  end

function get_xinput(inst)
	local hin = 0
	if (bit.band(inst.buttons, right)==right) then										--bitmasking for right button
		hin = hin + 1
	end
	if (bit.band(inst.buttons, left)==left) then										--bitmasking for left button
		hin = hin - 1
	end
	inst.xinput = hin
end

function get_dir_input(inst)
	local hin = 0
	if (bit.band(inst.buttons, right)==right) then										--bitmasking for right button
		hin = hin + 1
	end
	if (bit.band(inst.buttons, left)==left) then										--bitmasking for left button
		hin = hin - 1
	end
	local vin = 0
	if (bit.band(inst.buttons, up)==up) then											--bitmasking for right button
		vin = vin + 1
	end
	if (bit.band(inst.buttons, down)==down) then										--bitmasking for left button
		vin = vin - 1
	end
	inst.dir_input.x = hin
	inst.dir_input.y = vin

	if hin~=0 and vin~=0 then															--Diagonal direction input
		inst.dir_input = vmath.normalize(inst.dir_input)								--To get right value for diagonal movement
	end
end
--Get Tile ID from tilesource
function tile_id(inst, x, y)
	x = ceil(x)
	y = ceil(y)
	return tilemap.get_tile(inst.SOLIDMAP, inst.SOLIDLAYER, math.ceil(x/TILE_SIZE), math.ceil(y/TILE_SIZE))
end

--Get y one pixel above the tile
function tile_height(inst, tile_id, x, y)
	x = ceil(x)
	y = ceil(y)
	if tile_id == solid1 then																							--Block tile
		return ceil(y/TILE_SIZE) * TILE_SIZE + 1
	elseif tile_id == solid2 then																						--45 /
		return floor((y-1)/TILE_SIZE) * TILE_SIZE +1 +((x-1) % TILE_SIZE)
	elseif tile_id == solid3 then																						--45 \
		return floor((y-1)/TILE_SIZE) * TILE_SIZE +TILE_SIZE -((x-1) % TILE_SIZE)
	elseif tile_id == solid4 then																						--22.5 / low
		return floor((y-1)/TILE_SIZE) * TILE_SIZE + floor((x -1 - div(x-1, TILE_SIZE)*TILE_SIZE)/2) +1
	elseif tile_id == solid5 then																						--22.5 / high
		return floor((y-1)/TILE_SIZE) * TILE_SIZE + floor((x-1 - div(x-1, TILE_SIZE)*TILE_SIZE)/2) +floor(TILE_SIZE/2) +1
	elseif tile_id == solid6 then																						--22.5 \ low
		return floor((y-1)/TILE_SIZE) * TILE_SIZE +floor(TILE_SIZE/2) - floor((x -1 - div(x-1, TILE_SIZE)*TILE_SIZE)/2)
	elseif tile_id == solid7 then																						--22.5 \ high
		return floor((y-1)/TILE_SIZE) * TILE_SIZE +TILE_SIZE - floor((x -1 - div(x-1, TILE_SIZE)*TILE_SIZE)/2)
	elseif tile_id == 0  then																							--Empty
		return y
	elseif tile_id == nil  then																							--Out of map
		return y
	end
end

function ground_check_blocks(inst)
	--local x = inst.MY_POS.x
	--local y = inst.MY_POS.y
	if inst.landed then inst.landed = false end
	local x = ceil(inst.MY_POS.x)
	local y = ceil(inst.MY_POS.y)
	if inst.spd.y <= 0 then															--Bypass in case going up
		local L = tile_id(inst, x+inst.hitbox_l+1,	y+inst.hitbox_b)
		local M = tile_id(inst, x+inst.hitbox_hc,	y+inst.hitbox_b)
		local R = tile_id(inst, x+inst.hitbox_r,	y+inst.hitbox_b)
		if L>0 or M>0 or R>0 then
			inst.grounded = true
		else
			inst.grounded = false
		end
	else
		inst.grounded = false
	end
end

function ground_check_slopes(inst)
	--local x = inst.MY_POS.x
	--local y = inst.MY_POS.y
	local x = ceil(inst.MY_POS.x)
	local y = ceil(inst.MY_POS.y)
	if inst.landed then inst.landed = false end
	inst.grounded = false															--Default to false
	if inst.spd.y <= 0 then															--Bypass if going up
		local M = tile_id(inst, x+inst.hitbox_hc, y+inst.hitbox_b)					--Get tile id
		if M~=plat then																	--Not jump through platform
			if M~=nil and M~=0 then														--Center bottom is inside solid tile
				local h = tile_height(inst, M, x+inst.hitbox_hc, y+inst.hitbox_b)
				if y+inst.hitbox_b < h then												--If feet is on or below tile height
					inst.grounded = true
				end
			end
			if inst.grounded == false then												--If middle isn't on ground
				local L = tile_id(inst, x+inst.hitbox_l+1, y+inst.hitbox_b)
				local R = tile_id(inst, x+inst.hitbox_r, y+inst.hitbox_b)
				if L~=nil and L~=0 and L~=plat then
					local h = tile_height(inst, L, x+inst.hitbox_l+1, y+inst.hitbox_b)
					if y+inst.hitbox_b < h then
						inst.grounded = true
					end
				end
				if not inst.grounded and R~=nil and R~=0 and R~=plat then
					local h = tile_height(inst, R, x+inst.hitbox_r, y+inst.hitbox_b)
					if y+inst.hitbox_b < h then
						inst.grounded = true
					end
				end
			end
		end
		if not (band(inst.buttons, down)==down and band(inst.buttons, jump)==jump) then
			local bottom = inst.hitbox_b
			local L = tile_id(inst, x+inst.hitbox_l+1, y+bottom +1)
			local C = tile_id(inst, x+inst.hitbox_hc, y+bottom +1)
			local R = tile_id(inst, x+inst.hitbox_r, y+bottom +1)
			if L==0 and C==0 and R==0 then												--Above platform or in free tile
				L = tile_id(inst, x+inst.hitbox_l+1,	y+bottom)
				C = tile_id(inst, x+inst.hitbox_hc,		y+bottom)
				R = tile_id(inst, x+inst.hitbox_r,		y+bottom)
				if L==plat or C==plat or R==plat then
					inst.grounded = true
				end
			end
		end
	end
end

function ledge_collision(inst)
	if inst.spd.y <= 0 or band(inst.buttons, down)==down then                       --Going down
		if not inst.on_ledge then                                                   --NOT ON LEDGE
			if inst.xinput~=0 then                                                  --HAVE DIRECTION
				local x = inst.MY_POS.x
				local y = inst.MY_POS.y
				local vsp = inst.spd.y
				local side = nil
				if inst.xinput > 0 then
					side = inst.hitbox_r+1
				else
					side = inst.hitbox_l
				end
				local ledge = inst.hitbox_ledge
				local tnow = tile_id(inst, x+side, y+ledge)
				if tnow==0 or tnow==nil then                                        --ISN'T AGAINST A BLOCK
					local tnext = tile_id(inst, x+side, y+ledge+vsp)
					local tfeet = tile_id(inst, x+inst.hitbox_hc, y+inst.hitbox_b+1+vsp)	--check if free below feet
					if tnext == solid1 and (tfeet==0 or tfeet==nil) then
						local h = tile_height(inst, tnext, x+side, y+ledge+vsp)
						if h>= y+ledge+vsp then                                     --Was going below ledge
							inst.on_ledge = true
							inst.MY_POS.y = h-ledge
						else                                                        --Bellow ledge to catch it
							inst.on_ledge = false
						end
					else                                                            --Next tile is not solid block
						inst.on_ledge = false
					end
				else                                                                --is presing against a block
					local h = tile_height(inst, tnow, x+side, y+ledge)
					if h== y+ledge then                                             --On the right height for latching to a ledge
						inst.on_ledge = true
						inst.MY_POS.y = h-ledge
					else                                                            --Bellow ledge to catch it
						inst.on_ledge = false
					end
				end
			else                                                                    --No direction
				inst.on_ledge = false
			end
		else                                                                        --WAS ON LEDGE
			if band(inst.buttons, jump)==jump and not inst.jumping then
				inst.on_ledge = false
				inst.spd.y = inst.START_JUMP
				inst.jumping = true
			end
		end
	else                                                                            --Going up
		inst.on_ledge = false
	end

	if inst.on_ledge then
		if inst.last_ledge == 0 then
			inst.last_ledge = inst.xinput
			--PLACE FOR LATCH FLAG
		end
		inst.spd.y = 0
	else
		inst.last_ledge = 0
	end
end

function ledge_collision_dt(inst, dt)
	if inst.spd.y <= 0 and band(inst.buttons, down)~=down then                       --Going down
		if not inst.on_ledge then                                                   --NOT ON LEDGE
			if inst.xinput~=0 then                                                  --HAVE DIRECTION
				local x = inst.MY_POS.x
				local y = inst.MY_POS.y
				local vsp = inst.spd.y
				local side = nil
				if inst.xinput > 0 then
					side = inst.hitbox_r+1
				else
					side = inst.hitbox_l
				end
				local ledge = inst.hitbox_ledge
				local tnow = tile_id(inst, x+side, y+ledge)
				if tnow==0 or tnow==nil then                                        --ISN'T AGAINST A BLOCK
					local tnext = tile_id(inst, x+side, y+ledge+vsp)
					local tfeet = tile_id(inst, x+inst.hitbox_hc, y+inst.hitbox_b+1+vsp)	--check if free below feet
					if tnext == solid1 and (tfeet==0 or tfeet==nil) then
						local h = tile_height(inst, tnext, x+side, y+ledge+vsp)
						if h>= y+ledge+vsp then                                     --Was going below ledge
							inst.on_ledge = true
							inst.MY_POS.y = h-ledge
						else                                                        --Bellow ledge to catch it
							inst.on_ledge = false
						end
					else                                                            --Next tile is not solid block
						inst.on_ledge = false
					end
				else                                                                --is presing against a block
					local h = tile_height(inst, tnow, x+side, y+ledge)
					if h== y+ledge then                                             --On the right height for latching to a ledge
						inst.on_ledge = true
						inst.MY_POS.y = h-ledge
					else                                                            --Bellow ledge to catch it
						inst.on_ledge = false
					end
				end
			else                                                                    --No direction
				inst.on_ledge = false
			end
		else                                                                        --WAS ON LEDGE
			if band(inst.buttons, jump)==jump and not inst.jumping then
				inst.on_ledge = false
				inst.spd.y = inst.START_JUMP*dt
				inst.jumping = true
			end
		end
	else                                                                            --Going up
		inst.on_ledge = false
	end

	if inst.on_ledge then
		if inst.last_ledge == 0 then
			inst.last_ledge = inst.xinput
			inst.ledge_trig = true
		else
			inst.ledge_trig = false
		end
		inst.spd.y = 0
		--RESET WALLSLIDE VARIABLES
		inst.wallsliding = false
		inst.wallslide_trig = false
		inst.last_wall = 0
	else
		inst.last_ledge = 0
	end
end

function cliff_collision(inst)														--Useful for enemies not to run over a cliff
	if inst.cliff_trig then																--Reset trigger flag
		inst.cliff_trig = false
	end
	if inst.grounded then
		local hsp = inst.spd.x
		if hsp~=0 then
			local x = inst.MY_POS.x
			local y = inst.MY_POS.y + inst.hitbox_b +1
			y = floor(y/TILE_SIZE) * TILE_SIZE +1
			local side = nil
			if hsp > 0 then
				side = inst.hitbox_r
			else
				side = inst.hitbox_l
			end
			local tile = tile_id(inst, x+side+hsp, y-1)
			if tile==0 or tile==nil then												--Cliff is there
				if hsp > 0 then															--Moving to the right
					x = math.ceil((x+side+hsp)/TILE_SIZE) * TILE_SIZE -TILE_SIZE -side	--Snap to the tiles left side
				else																	-- Moving to the left or idle
					x = math.ceil((x+side+hsp)/TILE_SIZE) * TILE_SIZE -side				--Snap to the tiles right side
				end
				--COLLIDE
				inst.MY_POS.x = x
				inst.spd.x = 0
				inst.cliff_trig = true
			end
		end
	end
end

function can_wallslide(inst, h_dir)													--Check if can wallslide
	if band(inst.buttons, down)~=down and not inst.on_ledge then
		if not inst.wallsliding then													--Not attached
			if h_dir==0 then															--Not pressing any direction
				if inst.wallslide_trig then												--Remove trigger frag
					inst.wallslide_trig = false
				end
				return false
			else
				if inst.last_wall == inst.xinput then									--Have latched to wall this direction (simple solution to disable same wall)
					if inst.wallslide_trig then											--Remove trigger frag
						inst.wallslide_trig = false
					end
					return false
				else
					local side = nil
					if h_dir>0 then
						side = inst.hitbox_r+1
					elseif h_dir<0 then
						side = inst.hitbox_l
					end
					local x = inst.MY_POS.x
					local T = tile_id(inst, inst.MY_POS.x+side, inst.MY_POS.y+inst.hitbox_t)
					if T==solid1 then													--If tile is solid block
						if h_dir>0 then													--Save this direction for same wall latch disabling
							inst.last_wall = 1
						elseif h_dir<0 then
							inst.last_wall = -1
						end
						inst.wallslide_trig = true										--Trigger flag
						return true
					else
						if inst.wallslide_trig then										--Remove trigger frag
							inst.wallslide_trig = false
						end
						return false
					end
				end
			end
		else																			--Already latched to the wall
			if inst.wallslide_trig then													--Remove trigger frag
				inst.wallslide_trig = false
			end
			local side = nil
			if inst.last_wall>0 then
				side = inst.hitbox_r+1
			elseif inst.last_wall<0 then
				side = inst.hitbox_l
			end
			local x = inst.MY_POS.x
			local T = tile_id(inst, inst.MY_POS.x+side, inst.MY_POS.y+inst.hitbox_t)	--Check tile ID
			if T==solid1 then															--Tile is solid block
				return true
			else																		--Tile is not solid block
				if inst.wallslide_trig then												--Remove trigger frag
					inst.wallslide_trig = false
				end
				return false
			end
		end
	else
		if inst.wallslide_trig then														--Remove trigger frag
			inst.wallslide_trig = false
		end
		return false
	end
end

function platform_collision(inst)
	local vsp = inst.spd.y
	if vsp<=0 and inst.grounded==false then
		if not (band(inst.buttons, down)==down and band(inst.buttons, jump)==jump) then
			local x = inst.MY_POS.x
			local y = inst.MY_POS.y
			local bottom = inst.hitbox_b
			local L = tile_id(inst, x+inst.hitbox_l+1, y+bottom +1)
			local C = tile_id(inst, x+inst.hitbox_hc, y+bottom +1)
			local R = tile_id(inst, x+inst.hitbox_r, y+bottom +1)
			if L==0 and C==0 and R==0 then												--Above platform or in free tile
				L = tile_id(inst, x+inst.hitbox_l+1, y+bottom +vsp)
				C = tile_id(inst, x+inst.hitbox_hc, y+bottom +vsp)
				R = tile_id(inst, x+inst.hitbox_r, y+bottom +vsp)
				if L==plat or C==plat or R==plat then
					y = math.ceil((y+bottom+vsp)/TILE_SIZE) * TILE_SIZE -bottom
					inst.landed = true
					inst.grounded = true
					inst.MY_POS.y = y
					inst.spd.y = 0
				end
			end
		end
	end
end

function h_move(inst)
	if inst.wallsliding then														--Wallslide
		--
	elseif inst.on_ledge then
		--
	else
		local hin = inst.xinput														--xinput set in get_xinput()
		local hsp = inst.spd.x
		if hin ~= 0 then															--Move
			hsp = hsp + hin * inst.ACC
			hsp = clamp(hsp, -inst.MAX, inst.MAX)
		else																		--deaccelerate
			hsp = approach(hsp, 0, inst.DCC)										--(value, goal, ammount)
		end
		inst.spd.x = hsp
	end
end

function h_move_dt(inst, dt)
	
	if inst.wallsliding then														--Wallslide
		--
	elseif inst.on_ledge then
		--
	else
		local hin = inst.xinput														--xinput set in get_xinput()
		local hsp = inst.spd.x /dt
		if hin ~= 0 then															--Move
			hsp = hsp + hin * (inst.ACC * dt)
			hsp = clamp(hsp, -inst.MAX, inst.MAX)
		else																		--deaccelerate
			hsp = approach(hsp, 0, inst.DCC *dt)										--(value, goal, ammount)
		end
		inst.spd.x = hsp *dt
	end
end

function h_move_slopes_dt(inst, dt)
	
	if inst.wallsliding then														--Wallslide
		--
	elseif inst.on_ledge then
		--
	else
		local move_mult = 1															--Reduce speed if on slopes
		local M = tile_id(inst, inst.MY_POS.x+inst.hitbox_hc, inst.MY_POS.y+inst.hitbox_b)
		if M==solid2 or M==solid3 then
			move_mult = SLOPE_SPD1.x
		elseif M==solid4 or M==solid5 or M==solid6 or M==solid7 then
			move_mult = SLOPE_SPD2.x
		end
		local hin = inst.xinput														--xinput set in get_xinput()
		local hsp = inst.spd.x /dt
		if hin ~= 0 then															--Move
			hsp = hsp + hin * (inst.ACC * dt *move_mult)
			hsp = clamp(hsp, -inst.MAX *move_mult, inst.MAX *move_mult)
		else																		--deaccelerate
			hsp = approach(hsp, 0, inst.DCC *dt *move_mult)										--(value, goal, ammount)
		end
		inst.spd.x = hsp *dt
	end
end

function h_collide(inst)
	local hsp  = inst.spd.x
	if inst.wall_trig then inst.wall_trig = false end
	if hsp ~= 0 then																--Decouple code if not needed
		local x = inst.MY_POS.x
		local y = inst.MY_POS.y
		local side = nil
		if hsp > 0 then
			side = inst.hitbox_r
		else
			side = inst.hitbox_l
		end
		local T = tile_id(inst, x+side+hsp,		y+inst.hitbox_t)					--check top corner
		local M = tile_id(inst, x+side+hsp,		y+inst.hitbox_vc)					--check midle of the side
		local B = tile_id(inst, x+side+hsp,		y+inst.hitbox_b+1)					--check bottom corner

		if B==solid1 or M==solid1 or T==solid1 then
			if hsp > 0 then															--Moving to the right
				x = math.ceil((x+side+hsp)/TILE_SIZE) * TILE_SIZE -TILE_SIZE -side	--Snap to the tiles left side
			else																	-- Moving to the left or idle
				x = math.ceil((x+side+hsp)/TILE_SIZE) * TILE_SIZE -side				--Snap to the tiles right side
			end
			hsp  = 0 																--reset speed after collision
			inst.wall_trig = true													--Trigger wall collision flag
		end

		inst.MY_POS.x = x + hsp 													--Update coordinates variable
		inst.spd.x = hsp															--Update speed variable
	end
end

function h_collide_slope(inst)
	local hsp  = inst.spd.x
	if inst.wall_trig then inst.wall_trig = false end
	if hsp ~= 0 then																--Decouple code if not needed
		local x = inst.MY_POS.x
		local y = inst.MY_POS.y
		local side = nil
		if hsp > 0 then
			side = inst.hitbox_r
		else
			side = inst.hitbox_l
		end
		local T = tile_id(inst, x+side+hsp,		y+inst.hitbox_t)					--check top corner
		local M = 0																	--check midle of the side
		local B = 0																	--check bottom corner
		local S = tile_id(inst, x+inst.hitbox_hc,y+inst.hitbox_b)					--check below center
		if S==0 or S==nil then														--If not on ground enable checks
			B = tile_id(inst, x+side+hsp,		y+inst.hitbox_b+1)
			M = tile_id(inst, x+side+hsp,		y+inst.hitbox_vc)
		end
		if B==solid1 or M==solid1 or T==solid1 then
			if hsp > 0 then															--Moving to the right
				x = math.ceil((x+side+hsp)/TILE_SIZE) * TILE_SIZE -TILE_SIZE -side	--Snap to the tiles left side
			else																	-- Moving to the left or idle
				x = math.ceil((x+side+hsp)/TILE_SIZE) * TILE_SIZE -side				--Snap to the tiles right side
			end
			hsp  = 0 																--reset speed after collision
			inst.wall_trig = true													--Trigger wall collision flag
		end

		inst.MY_POS.x = x + hsp 													--Update coordinates variable
		inst.spd.x = hsp															--Update speed variable
	end
end

function v_move_platformer(inst)
	local vsp = inst.spd.y
	if inst.grounded then												--On ground
		inst.doublejump = false											--If use doublejump it's disabled on ground
		inst.last_wall = 0												--Reset Last wall (for allowing walljump from same wall once in a row)
		inst.jmp_buf_tmr = 0											--Reset jump buffer
		if inst.jumping and bit.band(inst.buttons, jump)==0 then		--Release jump button
			inst.jumping = false
		end
		if inst.wallsliding then										--disable wallsliding
			inst.wallsliding = false
		end

		if bit.band(inst.buttons, jump)==jump and not inst.jumping and (bit.band(inst.buttons, down)==0) then --New jump executed
			vsp = inst.START_JUMP
			inst.grounded = false
			inst.jumping = true
		end
	else 																--Not on the ground
		if not inst.on_ledge then
			vsp = vsp + inst.GRAVITY									--Apply gravity
		end
		if vsp>0 then													--Going up
			if inst.jmp_buf_tmr~=JUMP_BUFFER then						--Disable jump buffer
				inst.jmp_buf_tmr = JUMP_BUFFER
			end
		else															--Going down
			if can_wallslide(inst, inst.xinput) then					--Check wallsliding
				inst.wallsliding = true
			elseif inst.wallsliding then
				inst.wallsliding = false
			end
			if inst.wallsliding then
				if bit.band(inst.buttons, jump)==jump and not inst.jumping then --New jump executed
					vsp = inst.START_JUMP
					inst.jumping = true
					inst.wallsliding = false
					if inst.xinput == -inst.last_wall then						--Presing away from wall
						inst.spd.x = inst.xinput * inst.MAX
					end
				end
				if vsp < inst.WALLSPEED then vsp = inst.WALLSPEED end	--Limit wallslide speed
			else
				if vsp < inst.MAX_DOWN then vsp = inst.MAX_DOWN end		--Limit fall speed
			end
			if inst.jmp_buf_tmr < JUMP_BUFFER then						--Count jump buffer timer
				inst.jmp_buf_tmr = inst.jmp_buf_tmr +1
			end
		end
		
		if bit.band(inst.buttons, jump)~=jump then						--Released jump button
			if vsp > inst.RELEASE_JUMP then								--Cut down jump speed
				vsp = inst.RELEASE_JUMP
			end
			inst.jumping = false
		else															--Holding jump button
			if not inst.jumping and inst.jmp_buf_tmr < JUMP_BUFFER then
				vsp = inst.START_JUMP
				inst.jumping = true
			elseif not inst.jumping and inst.doublejump then			--If released jump and allowed doublejump
				vsp = inst.JUMP_START
				inst.jumping = true
				inst.doublejump = false
			end
		end
	end
	inst.spd.y = vsp										--Save vertical speed
end

function v_move_platformer_dt(inst, dt)
	local vsp = inst.spd.y /dt
	if inst.grounded then												--On ground
		inst.doublejump = false											--If use doublejump it's disabled on ground
		inst.last_wall = 0												--Reset Last wall (for allowing walljump from same wall once in a row)
		inst.jmp_buf_tmr = 0											--Reset jump buffer
		if inst.jumping and bit.band(inst.buttons, jump)==0 then		--Release jump button
			inst.jumping = false
		end
		if inst.wallsliding then										--disable wallsliding
			inst.wallsliding = false
		end

		if band(inst.buttons, jump)==jump and not inst.jumping and band(inst.buttons, down)~=down then --New jump executed
			vsp = inst.START_JUMP
			inst.grounded = false
			inst.jumping = true
		end
		if inst.fast_fall then inst.fast_fall = false end				--Not fast falling
	else 																--Not on the ground
		if not inst.on_ledge then
			vsp = vsp + inst.GRAVITY *dt								--Apply gravity
		end
		if vsp>0 then													--Going up
			if inst.jmp_buf_tmr~=JUMP_BUFFER then						--Disable jump buffer
				inst.jmp_buf_tmr = JUMP_BUFFER
			end
		else															--Going down
			if can_wallslide(inst, inst.xinput) then					--Check wallsliding
				inst.wallsliding = true
			elseif inst.wallsliding then
				inst.wallsliding = false
			end
			if inst.wallsliding then
				if bit.band(inst.buttons, jump)==jump and not inst.jumping then --New jump executed
					vsp = inst.START_JUMP
					inst.jumping = true
					inst.wallsliding = false
					if inst.xinput == -inst.last_wall then						--Presing away from wall
						inst.spd.x = inst.xinput * inst.MAX *dt					--Jump afay from wall with full speed
					end
				end
				if vsp < inst.WALLSPEED then vsp = inst.WALLSPEED end	--Limit wallslide speed
			else
				if vsp < inst.MAX_DOWN then								--Limit fall speed
					vsp = inst.MAX_DOWN
					inst.fast_fall = true								--Fast falling
				else
					if inst.fast_fall then inst.fast_fall = false end	--Not fast falling
				end		
			end
			if inst.jmp_buf_tmr < JUMP_BUFFER then						--Count jump buffer timer
				inst.jmp_buf_tmr = inst.jmp_buf_tmr +1*dt
			end
		end
		
		if band(inst.buttons, jump)~=jump then							--Released jump button
			if vsp > inst.RELEASE_JUMP then								--Cut down jump speed
				vsp = inst.RELEASE_JUMP
			end
			inst.jumping = false
		else															--Holding jump button
			if not inst.jumping and inst.jmp_buf_tmr < JUMP_BUFFER and band(inst.buttons, down)~=down then
				vsp = inst.START_JUMP
				inst.jumping = true
			elseif not inst.jumping and inst.doublejump then			--If released jump and allowed doublejump
				vsp = inst.JUMP_START
				inst.jumping = true
				inst.doublejump = false
			end
		end
	end
	inst.spd.y = vsp*dt										--Save vertical speed
end

function v_move_topdown(inst)														--Vertical top down movement
	--Get direction
	local vin = 0
	if (bit.band(inst.buttons, up) > 0) then										--bitmasking for up button
		vin = vin + 1
	end
	if (bit.band(inst.buttons, down) > 0) then										--bitmasking for down button
		vin = vin - 1
	end

	local vsp = inst.spd.y
	if vin ~= 0 then						--move
		vsp = vsp + vin * inst.ACC
		vsp = clamp(vsp, -inst.MAX, inst.MAX)
	else																			--deaccelerate
		vsp = approach(vsp, 0, inst.DCC)											--(value, goal, ammount)
	end
	inst.spd.y = vsp
end

function v_collide_blocks(inst)														--Simple block tile collision
	local vsp  = inst.spd.y
	if vsp ~= 0 then																--Decouple code if not needed
		local x = inst.MY_POS.x
		local y = inst.MY_POS.y
		local side = nil
		if vsp > 0 then
			side = inst.hitbox_t
		else
			side = inst.hitbox_b
		end
		local R = tile_id(inst, x+inst.hitbox_r,		y+side+vsp)					--check top corner
		local M = tile_id(inst, x+inst.hitbox_hc,		y+side+vsp)					--check midle of the side
		local L = tile_id(inst, x+inst.hitbox_l+1,		y+side+vsp)					--check bottom corner

		if R==solid1 or M==solid1 or L==solid1 then
			if vsp > 0 then															--Moving to the right
				y = math.ceil((y+side+vsp)/TILE_SIZE) * TILE_SIZE -TILE_SIZE -side	--Snap to the tiles left side
			else																	-- Moving to the left or idle
				y = math.ceil((y+side+vsp)/TILE_SIZE) * TILE_SIZE -side				--Snap to the tiles right side
			end
			vsp  = 0 --reset speed after collision
		end

		inst.MY_POS.y = y + vsp --Update coordinates variable
		inst.spd.y = vsp	--Update speed variable
	end
end

function v_collide_slopes(inst)														--Simple block tile collision
	local x = inst.MY_POS.x
	local y = inst.MY_POS.y
	local vsp  = inst.spd.y

	vsp  = vsp-- - frac																	--Leave remainder in integer value
	if vsp ~= 0 then																	--Decouple code if not moving
		if vsp > 0 then																	--Going up
			local side = inst.hitbox_t
			local R = tile_id(inst, x+inst.hitbox_r,		y+side+vsp)					--check right corner
			local M = tile_id(inst, x+inst.hitbox_hc,		y+side+vsp)					--check midle of the side
			local L = tile_id(inst, x+inst.hitbox_l+1,		y+side+vsp)					--check left corner

			if R==solid1 or M==solid1 or L==solid1 then
				y = math.ceil((y+side+vsp)/TILE_SIZE) * TILE_SIZE -TILE_SIZE -side		--Snap to the tiles bottom side
				vsp  = 0 																--reset speed after collision
			end
		else																			--Going down
			local side = inst.hitbox_b+1
			local C = tile_id(inst, x+inst.hitbox_hc, y+side+vsp)
			if C~=plat then
				if C==0 or C==nil then
					local R = tile_id(inst, x+inst.hitbox_r,		y+side+vsp)				--check top corner
					local M = tile_id(inst, x+inst.hitbox_hc,		y+side+vsp)				--check midle of the side
					local L = tile_id(inst, x+inst.hitbox_l+1,		y+side+vsp)				--check bottom corner

					if R==solid1 or M==solid1 or L==solid1 then
						y = math.ceil((y+side+vsp)/TILE_SIZE) * TILE_SIZE -side	+1			--Snap to the tiles top side
						vsp  = 0															--reset speed after collision
					end
				elseif C==solid1 then
					y = ceil((y+side+vsp)/TILE_SIZE) * TILE_SIZE -side	+1					--Snap to the tiles top side
					vsp  = 0																--reset speed after collision
				elseif C~=solid1 then
					local h = tile_height(inst, C, x+inst.hitbox_hc, y+inst.hitbox_b+1+vsp)
					if (y+inst.hitbox_b+1+vsp)<=h then
						y = h-(inst.hitbox_b+1)
						vsp  = 0
					end
				end
				if vsp == 0 then inst.landed=true end										--Trigger landing flag
			end
		end
	end
	
	if inst.grounded then
		local yy = 1
		local M = tile_id(inst, x+inst.hitbox_hc, y+inst.hitbox_b+yy)
		if M==0 or M==nil then
			yy = 0
			M = tile_id(inst, x+inst.hitbox_hc, y+inst.hitbox_b+yy)
		end
		if M==0 or M==nil then
			yy = TILE_SIZE
			M = tile_id(inst, x+inst.hitbox_hc, y+inst.hitbox_b+yy)
		end
		if M~=0 and M~=nil and M~=plat then
			local h = tile_height(inst, M, x+inst.hitbox_hc, y+inst.hitbox_b+yy)
			y = h -(inst.hitbox_b+1)
			vsp = 0
		end
	end
	inst.MY_POS.y = y + vsp --Update position variable
	inst.spd.y = vsp	--Update speed variable
end

function physics_update_topdown(inst)
	get_dir(inst)
	h_move(inst)
	h_collide(inst)
	v_move_topdown(inst)
	v_collide_blocks(inst)
	go.set_position(inst.MY_POS, inst.MY_URL)

	--Reset buttons
	inst.buttons = 0
end

function physics_update_platformer(inst)
	get_xinput(inst)
	h_move(inst)
	h_collide(inst)
	ground_check_slopes(inst)
	v_move_platformer(inst)
	ledge_collision(inst)
	v_collide_slopes(inst)
	go.set_position(inst.MY_POS, inst.MY_URL)
	
	--Reset buttons
	inst.buttons = 0
end

function physics_update_platformer_dt(inst, dt)
	dt = dt*TIME_MULT*60															--I like to have speed variables to be px/frame (60fps) so dt*60
	get_xinput(inst)
	h_move_slopes_dt(inst, dt)
	h_collide_slope(inst)
	ground_check_slopes(inst)
	v_move_platformer_dt(inst, dt)
	platform_collision(inst)
	ledge_collision_dt(inst, dt)
	v_collide_slopes(inst)
	go.set_position(inst.MY_POS, inst.MY_URL)
	
	--Reset buttons
	inst.buttons = 0
end