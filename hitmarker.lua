local UI_PATH = "Scripting, Script elements"

local hm_enable = ui.add_checkbox(UI_PATH, "(+) Hitmarker")
local hm_color  = ui.add_color_picker(UI_PATH, "Hitmarker color")
hm_color:set(color(88, 255, 209, 255))

local hm_duration = ui.add_slider(UI_PATH, "Hitmarker duration", 1.0, 5.0, 1.0, 0.1)

local FADE_TIME = 0.5

local marks = {}

local function hitgroup_to_hitbox(hitgroup)
    if hitgroup == e_hitgroup.HEAD then return e_hitbox.HEAD end
    if hitgroup == e_hitgroup.NECK then return e_hitbox.NECK end
    if hitgroup == e_hitgroup.CHEST then return e_hitbox.CHEST end
    if hitgroup == e_hitgroup.STOMACH then return e_hitbox.STOMACH end
    if hitgroup == e_hitgroup.LEFTARM then return e_hitbox.LEFT_FOREARM end
    if hitgroup == e_hitgroup.RIGHTARM then return e_hitbox.RIGHT_FOREARM end
    if hitgroup == e_hitgroup.LEFTLEG then return e_hitbox.LEFT_CALF end
    if hitgroup == e_hitgroup.RIGHTLEG then return e_hitbox.RIGHT_CALF end
    return e_hitbox.CHEST
end

local function push_mark_world(world_pos)
    marks[#marks + 1] = { pos = world_pos, wait = hm_duration:get(), fade = 1.0, is_screen = false }
end

local function push_mark_screen(screen_pos)
    marks[#marks + 1] = { pos = screen_pos, wait = hm_duration:get(), fade = 1.0, is_screen = true }
end

local function get_victim_world_pos(victim, hb)
    local p = victim:get_hitbox_pos(hb)
    if p ~= nil then return p end
    p = victim:get_hitbox_pos(e_hitbox.HEAD)
    if p ~= nil then return p end
    p = victim:get_hitbox_pos(e_hitbox.CHEST)
    if p ~= nil then return p end
    p = victim:get_eye_pos()
    if p ~= nil then return p end
    p = victim:get_abs_origin()
    if p ~= nil then return p end
    p = victim:get_origin()
    return p
end

local function get_victim_screen_center(victim)
    local tl, sz = victim:get_screen_bounds()
    if tl == nil or sz == nil then return nil end
    return vector2d(tl.x + (sz.x * 0.5), tl.y + (sz.y * 0.5))
end

local impacts = {}
local IMPACT_KEEP_TIME = 0.40
local IMPACT_MATCH_WINDOW = 0.30
local IMPACT_MAX_DIST = 45.0
local IMPACT_MAX_DIST_SQ = IMPACT_MAX_DIST * IMPACT_MAX_DIST

events.add("bullet_impact", function(e)
    local lp = entities.get_local_player()
    if lp == nil then return end

    if e.userid ~= lp then return end

    impacts[#impacts + 1] = {
        t = globals.get_cur_time(),
        pos = vector(e.x, e.y, e.z)
    }
end)

local function prune_impacts(now)
    for i = #impacts, 1, -1 do
        if (now - impacts[i].t) > IMPACT_KEEP_TIME then
            table.remove(impacts, i)
        end
    end
end

local function find_best_impact_by_distance(now, target_pos)
    local best_pos = nil
    local best_dist_sq = 1e18

    for i = #impacts, 1, -1 do
        local imp = impacts[i]
        local dt = now - imp.t

        if dt >= 0 and dt <= IMPACT_MATCH_WINDOW then
            local dx = imp.pos.x - target_pos.x
            local dy = imp.pos.y - target_pos.y
            local dz = imp.pos.z - target_pos.z
            local dist_sq = (dx * dx) + (dy * dy) + (dz * dz)

            if dist_sq < best_dist_sq then
                best_dist_sq = dist_sq
                best_pos = imp.pos
            end
        end
    end

    if best_pos ~= nil and best_dist_sq <= IMPACT_MAX_DIST_SQ then
        return best_pos
    end

    return nil
end

local function find_best_impact_by_time(now)
    local best_pos = nil
    local best_dt = 1e18

    for i = #impacts, 1, -1 do
        local imp = impacts[i]
        local dt = now - imp.t
        if dt >= 0 and dt <= IMPACT_MATCH_WINDOW and dt < best_dt then
            best_dt = dt
            best_pos = imp.pos
        end
    end

    return best_pos
end

events.add("player_hurt", function(event)
    if event.attacker ~= entities.get_local_player() then return end

    local victim = event.userid
    if victim == nil then return end

    local now = globals.get_cur_time()
    prune_impacts(now)

    local hb = hitgroup_to_hitbox(event.hitgroup)
    local victim_pos = get_victim_world_pos(victim, hb)

    if victim_pos ~= nil then
        local impact_pos = find_best_impact_by_distance(now, victim_pos)
        if impact_pos ~= nil then
            push_mark_world(impact_pos)
        else
            push_mark_world(victim_pos)
        end
        return
    end

    local impact_fallback = find_best_impact_by_time(now)
    if impact_fallback ~= nil then
        push_mark_world(impact_fallback)
        return
    end

    local sc = get_victim_screen_center(victim)
    if sc ~= nil then
        push_mark_screen(sc)
    end
end)

local function clear_all()
    marks = {}
    impacts = {}
end

events.add("round_start", clear_all)
events.add("player_spawn", clear_all)

callbacks.add("render", function()
    if not hm_enable:get() then return end

    local ft = globals.get_frame_time()
    local base = hm_color:get()
    local arm_long, arm_thick = 5, 1

    for i = #marks, 1, -1 do
        local m = marks[i]

        m.wait = m.wait - ft
        if m.wait <= 0 then
            m.fade = m.fade - ((1.0 / FADE_TIME) * ft)
        end

        if m.fade <= 0 then
            table.remove(marks, i)
        else
            local x, y

            if m.is_screen then
                x, y = m.pos.x, m.pos.y
            else
                local screen = m.pos:to_screen()
                if screen == nil then
                    goto continue
                end
                x, y = screen.x, screen.y
            end

            local col = base:scaled_alpha(m.fade)
            render.filled_rect(vector2d(x - arm_long,  y - arm_thick), vector2d(arm_long * 2,  arm_thick * 2), col)
            render.filled_rect(vector2d(x - arm_thick, y - arm_long),  vector2d(arm_thick * 2, arm_long * 2),  col)
        end

        ::continue::
    end
end)
