-- author:@keer

local hearts = {}

local function rectangle(x, y, w, h, col)
    render.filled_rect(vector2d(x, y), vector2d(w, h), col)
end

local function draw_heart(x, y, col)
    rectangle(x + 2, y + 14, 2, 2, color(0, 0, 0, col.a))
    rectangle(x, y + 12, 2, 2, color(0, 0, 0, col.a))
    rectangle(x - 2, y + 10, 2, 2, color(0, 0, 0, col.a))
    rectangle(x - 4, y + 4, 2, 6, color(0, 0, 0, col.a))
    rectangle(x - 2, y + 2, 2, 2, color(0, 0, 0, col.a))
    rectangle(x, y, 2, 2, color(0, 0, 0, col.a))
    rectangle(x + 2, y, 2, 2, color(0, 0, 0, col.a))
    rectangle(x + 4, y + 2, 2, 2, color(0, 0, 0, col.a))
    rectangle(x + 6, y, 2, 2, color(0, 0, 0, col.a))
    rectangle(x + 8, y, 2, 2, color(0, 0, 0, col.a))
    rectangle(x + 10, y + 2, 2, 2, color(0, 0, 0, col.a))
    rectangle(x + 12, y + 4, 2, 6, color(0, 0, 0, col.a))
    rectangle(x + 10, y + 10, 2, 2, color(0, 0, 0, col.a))
    rectangle(x + 8, y + 12, 2, 2, color(0, 0, 0, col.a))
    rectangle(x + 6, y + 14, 2, 2, color(0, 0, 0, col.a))
    rectangle(x + 4, y + 16, 2, 2, color(0, 0, 0, col.a))
    
    rectangle(x - 2, y + 4, 2, 6, col)
    rectangle(x, y + 2, 4, 2, col)
    rectangle(x, y + 6, 4, 6, col)
    rectangle(x + 2, y + 4, 2, 2, col)
    rectangle(x + 2, y + 12, 2, 2, col)
    rectangle(x + 4, y + 4, 2, 12, col)
    rectangle(x + 6, y + 2, 4, 10, col)
    rectangle(x + 6, y + 12, 2, 2, col)
    rectangle(x + 10, y + 4, 2, 6, col)
    
    rectangle(x, y + 4, 2, 2, color(254, 199, 199, col.a))
end

local function on_render()
    local realtime = globals.get_real_time()
    
    for i = #hearts, 1, -1 do
        local heart = hearts[i]
        
        local screen_pos = heart.position:to_screen()
        
        if screen_pos then
            local alpha = math.floor(255 - 255 * (realtime - heart.start_time))
            
            if realtime - heart.start_time >= 1 then
                alpha = 0
            end
            
            local col
            if heart.damage <= 15 then
                col = color(60, 255, 0, alpha)
            elseif heart.damage <= 30 then
                col = color(255, 251, 0, alpha)
            elseif heart.damage <= 60 then
                col = color(255, 140, 0, alpha)
            else
                col = color(254, 19, 19, alpha)
            end
            
            draw_heart(screen_pos.x - 5, screen_pos.y - 5, col)
        end
        
        heart.position.z = heart.position.z + (realtime - heart.frame_time) * 50
        heart.frame_time = realtime
        
        if realtime - heart.start_time >= 1 then
            table.remove(hearts, i)
        end
    end
end

local function on_player_hurt(event)
    local attacker = event.attacker
    local victim = event.userid
    local damage = event.dmg_health
    local hitgroup = event.hitgroup
    
    if not attacker or not victim then return end
    
    if attacker == entities.get_local_player() then
        local time = globals.get_real_time()
        
        local hit_pos = nil
        
        if hitgroup == 1 then
            hit_pos = victim:get_hitbox_pos(e_hitbox.HEAD)
        elseif hitgroup == 8 then
            hit_pos = victim:get_hitbox_pos(e_hitbox.NECK)
        elseif hitgroup == 2 then
            hit_pos = victim:get_hitbox_pos(e_hitbox.CHEST) or 
                     victim:get_hitbox_pos(e_hitbox.UPPER_CHEST) or
                     victim:get_hitbox_pos(e_hitbox.THORAX)
        elseif hitgroup == 3 then
            hit_pos = victim:get_hitbox_pos(e_hitbox.STOMACH) or
                     victim:get_hitbox_pos(e_hitbox.PELVIS)
        elseif hitgroup == 4 then
            hit_pos = victim:get_hitbox_pos(e_hitbox.LEFT_HAND) or
                     victim:get_hitbox_pos(e_hitbox.LEFT_FOREARM) or
                     victim:get_hitbox_pos(e_hitbox.LEFT_UPPER_ARM)
        elseif hitgroup == 5 then
            hit_pos = victim:get_hitbox_pos(e_hitbox.RIGHT_HAND) or
                     victim:get_hitbox_pos(e_hitbox.RIGHT_FOREARM) or
                     victim:get_hitbox_pos(e_hitbox.RIGHT_UPPER_ARM)
        elseif hitgroup == 6 then
            hit_pos = victim:get_hitbox_pos(e_hitbox.LEFT_FOOT) or
                     victim:get_hitbox_pos(e_hitbox.LEFT_CALF) or
                     victim:get_hitbox_pos(e_hitbox.LEFT_THIGH)
        elseif hitgroup == 7 then
            hit_pos = victim:get_hitbox_pos(e_hitbox.RIGHT_FOOT) or
                     victim:get_hitbox_pos(e_hitbox.RIGHT_CALF) or
                     victim:get_hitbox_pos(e_hitbox.RIGHT_THIGH)
        end
        
        if not hit_pos then
            local origin = victim:get_abs_origin()
            hit_pos = vector(origin.x, origin.y, origin.z + 50)
        end
        
        table.insert(hearts, {
            position = hit_pos,
            damage = damage,
            start_time = time,
            frame_time = time
        })
    end
end

callbacks.add("render", on_render)
events.add("player_hurt", on_player_hurt)