# true-tile-collision
Collision system that doesn't use collision shapes.
Check out ["example project"](https://github.com/nezvers/DefoldPublicExamples).
It's still in development but it contain everything you need for platformer game and easy to put together top-down game

# Easy to use!
## Prepare player
```lua
require "true_tile_collision.true_tile_collision"                                   -- [1]

function init(self)
    msg.post(".", "acquire_input_focus")				--Enable inputs for player

    init_physics(self, msg.url(), "/background#tilemap", "collision", 16, 2, 5, 0.2)    -- [2]
    set_hitbox(self, 5, -5, 15, -1)                                                 -- [3]
end

function final(self)
    msg.post(".", "release_input_focus")	--Disable input upon deletion of the object
end

function update(self, dt)
    --PHYSICS
    physics_update_platformer_block(self, dt)                                       -- [4]
    
    --SPRITE - simple flip
    if not self.on_ledge and not self.wallsliding then
        if self.xinput==1 then
            sprite.set_hflip("#sprite", false)
        elseif self.xinput==-1 then
            sprite.set_hflip("#sprite", true)
        end
    end
end

function on_input(self, action_id, action)
    -- save all buttons in one variable using bitwise
    if action_id == hash("up") then
        button_up(self)
    elseif action_id == hash("down")   then
        button_down(self)
    elseif action_id == hash("left")   then
        button_left(self)
    elseif action_id == hash("right")  then
        button_right(self)
    elseif action_id == hash("jump")   then
        button_jump(self)
    elseif action_id == hash("action") then --**
        button_action(self)
    elseif action_id == hash("start")  then --**
        button_start(self)
    end
    --** not used for True Tile collision but are there if you want to expand
end
```
1. Reference the TrueTileCollision LUA module
2. Creates all necessary variables inside object. Need to pass (self, URL, collisionTilemap, collisionLayer, tileSize, maxHorizontalSpeed, jumpSpeed, gravity) By default use values pixels per frame (60fps)
3. Hitbox size (self, right, left, top, bottom) Distance from origin point to sides.
4. Update physics. Built-in:  
physics_update_platformer_block;  
physics_update_platformer_slopes;  
physics_update_topdown;  
physics_update_walker.

Please look into init_physics() function because there you'll find needed flags and triggers for your objects (Abilities, States, triggers) to trigger sprite animations/ sounds or create your own AI behaviour.

## Prepare tiles
Tiles doesn't need collision shapes. Collision happens using tile IDs from tilesource.  
Suggested method would be to have tilemap with at least 2 layers where one of them is invisible and used for placing solid tiles, or use separate tilemap with dedicated tilesource (if you have more than one tilesources).  
If you don't have dedicated tilesource or IDs doesn't match the default values, all you need to do is call set_tiles function.
```lua
function set_tiles(tile1, tile2, tile3, tile4, tile5, tile6, tile7, tile8)
	solid1	= tile1		--solid block
	solid2	= tile2		--slope 45 righ
	solid3	= tile3		--slope 45 left
	solid4	= tile4		--slope 22.5 right 1/2
	solid5	= tile5		--slope 22.5 right 2/2
	solid6	= tile6		--slope 22.5 left 1/2
	solid7	= tile7		--slope 22.5 left 2/2
	plat	= tile8		--Jumpthrough platform
end
```
Values are IDs in tilesource used for collision. IDs in tilesource are counted from left to right and top to down, starting from 1.

## Create your own _physics_update_
Since dependancy LUA modules are read only, you can create module that refer to TTC (require "true_tile_collision.true_tile_collision") and create your own physics updates (for players and enemies) by using modular system from TTC.  
For reference you can use TTC built-in physics updates and many physics functions that's coded inside TTC.

# HAPPY GAMEDEV
## Cheers, _NeZvers_
