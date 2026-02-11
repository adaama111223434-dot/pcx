local ffi_ok, ffi = pcall(require, 'ffi')
if ffi_ok then
    ffi.cdef[[
        typedef struct { float x, y, z; } vec3_t;
    ]]
end
local player_positions = {}
local death_particles = {}
local kill_trails = {}
local self_particles = {}
local self_particles_active = false
local fireflies = {}
local firefly_spawn_timer = 0
local glow_texture_id = nil
local glow_texture_size = 64
local line_texture_id = nil
local line_texture_size = 64
local function random_float(min, max)
    return math.random() * (max - min) + min
end
local function random_int(min, max)
    return math.random(min, max)
end
local function generate_glow_texture()
    local size = glow_texture_size
    local center = size / 2
    local max_radius = center
    local pixels = {}
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local dx = x - center + 0.5
            local dy = y - center + 0.5
            local dist = math.sqrt(dx * dx + dy * dy) / max_radius
            local alpha = 0
            if dist < 1 then
                local core = math.max(0, 1 - dist * 4) * 255
                local inner = math.max(0, 1 - dist * 2) * 200
                local outer = math.max(0, 1 - dist) * 100
                alpha = math.min(255, core + inner * 0.5 + outer * 0.3)
            end
            pixels[#pixels + 1] = string.char(255, 255, 255, math.floor(alpha))
        end
    end
    local pixel_string = table.concat(pixels)
    local success, texture = pcall(function()
        return render.create_png_from_memory(pixel_string)
    end)
    if success and texture then
        glow_texture_id = texture
        return true
    end
    return false
end
local function generate_line_texture()
    local size = line_texture_size
    local center_y = size / 2
    local half_width = size / 2
    local pixels = {}
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local dy = math.abs(y - center_y + 0.5)
            local dx = math.abs(x - half_width + 0.5) / half_width
            local perp_falloff = math.max(0, 1 - dy / (size * 0.15))
            local length_falloff = math.max(0, 1 - dx * dx)
            local alpha = perp_falloff * length_falloff * 255
            local core_perp = math.max(0, 1 - dy / (size * 0.05))
            alpha = alpha + core_perp * length_falloff * 150
            pixels[#pixels + 1] = string.char(255, 255, 255, math.floor(math.min(255, alpha)))
        end
    end
    local pixel_string = table.concat(pixels)
    local success, texture = pcall(function()
        return render.create_png_from_memory(pixel_string)
    end)
    if success and texture then
        line_texture_id = texture
        return true
    end
    return false
end
local textures_loaded = generate_glow_texture() and generate_line_texture()
local particle_pool = {}
local pool_size = 0
local function pool_get()
    if pool_size > 0 then
        local p = particle_pool[pool_size]
        particle_pool[pool_size] = nil
        pool_size = pool_size - 1
        return p
    end
    return {}
end
local function pool_return(p)
    pool_size = pool_size + 1
    particle_pool[pool_size] = p
end
local HITBOX_COUNT = 19
local TWO_PI = 6.28318530718
local INV_1_5 = 0.666666666667
local INV_500 = 0.002
local math_sin = math.sin
local math_cos = math.cos
local math_floor = math.floor
local math_sqrt = math.sqrt
local math_abs = math.abs
local math_max = math.max
local math_min = math.min
local table_remove = table.remove
local container = ui.find_container("Scripting, Script elements")
local ui_enabled = container:add_checkbox("Particles")
local ui_color = ui_enabled:add_color_picker()
ui_color:set(color(230, 240, 255, 255))
local ui_label_particles = container:add_label("─── Particle Settings ───")
local ui_particle_count = container:add_slider("Particle count", 5, 30, 1)
ui_particle_count:set(15)
local ui_particle_size = container:add_slider("Size", 1, 20, 1, "px")
ui_particle_size:set(1)
local ui_size_variation = container:add_slider("Size variation", 0, 100, 1, "%")
ui_size_variation:set(40)
local ui_lifetime = container:add_slider("Duration", 10, 50, 1)
ui_lifetime:set(30)
local ui_dissolve_style = container:add_dropdown("Style", {"Thanos Snap", "Float Up", "Scatter", "Implode"})
local ui_particle_shape = container:add_dropdown("Shape", {"Circles", "Lines", "Mixed"})
local ui_label_color = container:add_label("─── Color Settings ───")
local ui_color_mode = container:add_dropdown("Color mode", {"Static", "Rainbow", "Gradient"})
local ui_rainbow_speed = container:add_slider("Rainbow speed", 1, 100, 1, "%")
ui_rainbow_speed:set(50)
local ui_secondary_color = container:add_color_picker("Secondary color")
ui_secondary_color:set(color(255, 100, 200, 255))
local ui_color_variation = container:add_slider("Hue variation", 0, 100, 1, "%")
ui_color_variation:set(0)
local ui_glow_intensity = container:add_slider("Glow", 0, 100, 1, "%")
ui_glow_intensity:set(50)
local ui_label_physics = container:add_label("─── Physics ───")
local ui_drift_speed = container:add_slider("Drift speed", 1, 100, 1, "%")
ui_drift_speed:set(20)
local ui_gravity = container:add_slider("Gravity", -100, 100, 1, "%")
ui_gravity:set(0)
local ui_turbulence = container:add_slider("Turbulence", 0, 100, 1, "%")
ui_turbulence:set(0)
local ui_spin_speed = container:add_slider("Spin speed", 0, 100, 1, "%")
ui_spin_speed:set(0)
local ui_velocity_inherit = container:add_slider("Velocity inherit", 0, 100, 1, "%")
ui_velocity_inherit:set(0)
local ui_delay_spread = container:add_slider("Delay spread", 0, 100, 1, "%")
ui_delay_spread:set(50)
local ui_label_extras = container:add_label("─── Extra Effects ───")
local ui_particle_connections = container:add_checkbox("Particle connections")
local ui_connection_distance = container:add_slider("Connection range", 10, 100, 1, "px")
ui_connection_distance:set(40)
local ui_secondary_particles = container:add_checkbox("Fizzy particles")
local ui_label_trail = container:add_label("─── Kill Trail ───")
local ui_kill_trail = container:add_checkbox("Enable kill trail")
local ui_kill_trail_color = ui_kill_trail:add_color_picker()
ui_kill_trail_color:set(color(100, 255, 180, 255))
local ui_kill_trail_style = container:add_dropdown("Trail style", {"Soul Stream", "Energy Beam", "Spiral", "Lightning"})
local ui_kill_trail_speed = container:add_slider("Trail speed", 1, 100, 1, "%")
ui_kill_trail_speed:set(50)
local ui_kill_trail_density = container:add_slider("Trail density", 5, 50, 1)
ui_kill_trail_density:set(20)
local ui_kill_trail_curve = container:add_slider("Trail curve", 0, 100, 1, "%")
ui_kill_trail_curve:set(40)
local ui_label_self = container:add_label("─── Self Effects ───")
local ui_self_particles = container:add_checkbox("Self particles")
local ui_self_particles_color = ui_self_particles:add_color_picker()
ui_self_particles_color:set(color(100, 180, 255, 255))
local ui_label_fireflies = container:add_label("─── Fireflies ───")
local ui_fireflies = container:add_checkbox("Enable fireflies")
local ui_fireflies_color = ui_fireflies:add_color_picker()
ui_fireflies_color:set(color(255, 255, 150, 255))
local ui_fireflies_amount = container:add_slider("Amount", 5, 50, 1)
ui_fireflies_amount:set(20)
local ui_fireflies_size = container:add_slider("Firefly size", 1, 10, 1, "px")
ui_fireflies_size:set(1)
local ui_fireflies_range = container:add_slider("Range", 100, 800, 1)
ui_fireflies_range:set(300)
local ui_label_options = container:add_label("─── Options ───")
local ui_enemies_only = container:add_checkbox("Enemies only")
local ui_show_notification = container:add_checkbox("Show notification")
local function update_ui_visibility()
    local enabled = ui_enabled:get()
    local color_mode = ui_color_mode:get()
    local shape = ui_particle_shape:get()
    ui_label_particles:set_visibility(enabled)
    ui_particle_count:set_visibility(enabled)
    ui_particle_size:set_visibility(enabled)
    ui_size_variation:set_visibility(enabled)
    ui_lifetime:set_visibility(enabled)
    ui_dissolve_style:set_visibility(enabled)
    ui_particle_shape:set_visibility(enabled)
    ui_label_color:set_visibility(enabled)
    ui_color_mode:set_visibility(enabled)
    ui_rainbow_speed:set_visibility(enabled and color_mode == "Rainbow")
    ui_secondary_color:set_visibility(enabled and color_mode == "Gradient")
    ui_color_variation:set_visibility(enabled)
    ui_glow_intensity:set_visibility(enabled)
    ui_label_physics:set_visibility(enabled)
    ui_drift_speed:set_visibility(enabled)
    ui_gravity:set_visibility(enabled)
    ui_turbulence:set_visibility(enabled)
    ui_spin_speed:set_visibility(enabled and (shape == "Lines" or shape == "Mixed"))
    ui_velocity_inherit:set_visibility(enabled)
    ui_delay_spread:set_visibility(enabled)
    ui_label_extras:set_visibility(enabled)
    ui_particle_connections:set_visibility(enabled)
    ui_connection_distance:set_visibility(enabled and ui_particle_connections:get())
    ui_secondary_particles:set_visibility(enabled)
    ui_label_trail:set_visibility(enabled)
    ui_kill_trail:set_visibility(enabled)
    local kill_trail_enabled = enabled and ui_kill_trail:get()
    ui_kill_trail_style:set_visibility(kill_trail_enabled)
    ui_kill_trail_speed:set_visibility(kill_trail_enabled)
    ui_kill_trail_density:set_visibility(kill_trail_enabled)
    ui_kill_trail_curve:set_visibility(kill_trail_enabled)
    ui_label_self:set_visibility(enabled)
    ui_self_particles:set_visibility(enabled)
    ui_label_fireflies:set_visibility(enabled)
    ui_fireflies:set_visibility(enabled)
    local fireflies_enabled = enabled and ui_fireflies:get()
    ui_fireflies_amount:set_visibility(fireflies_enabled)
    ui_fireflies_size:set_visibility(fireflies_enabled)
    ui_fireflies_range:set_visibility(fireflies_enabled)
    ui_label_options:set_visibility(enabled)
    ui_enemies_only:set_visibility(enabled)
    ui_show_notification:set_visibility(enabled)
end
ui_enabled:add_callback(update_ui_visibility)
ui_color_mode:add_callback(update_ui_visibility)
ui_particle_shape:add_callback(update_ui_visibility)
ui_particle_connections:add_callback(update_ui_visibility)
ui_kill_trail:add_callback(update_ui_visibility)
ui_fireflies:add_callback(update_ui_visibility)
update_ui_visibility()
local function hsv_to_rgb(h, s, v)
    local c = v * s
    local x = c * (1 - math_abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b = 0, 0, 0
    if h < 60 then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    return math_floor((r + m) * 255), math_floor((g + m) * 255), math_floor((b + m) * 255)
end
local function lerp_color(r1, g1, b1, r2, g2, b2, t)
    return math_floor(r1 + (r2 - r1) * t),
           math_floor(g1 + (g2 - g1) * t),
           math_floor(b1 + (b2 - b1) * t)
end
local function shift_hue(r, g, b, hue_shift)
    local max_c = math_max(r, g, b)
    local min_c = math_min(r, g, b)
    local delta = max_c - min_c
    if delta == 0 then return r, g, b end
    local h, s, v
    v = max_c / 255
    s = delta / max_c
    if r == max_c then
        h = 60 * (((g - b) / delta) % 6)
    elseif g == max_c then
        h = 60 * (((b - r) / delta) + 2)
    else
        h = 60 * (((r - g) / delta) + 4)
    end
    h = (h + hue_shift) % 360
    if h < 0 then h = h + 360 end
    return hsv_to_rgb(h, s, v)
end
local function create_death_particles(x, y, z, player, inherit_vel_x, inherit_vel_y, inherit_vel_z)
    local spawn_time = globals.get_real_time()
    local vel_inherit_mult = ui_velocity_inherit:get() * 0.01
    inherit_vel_x = (inherit_vel_x or 0) * vel_inherit_mult
    inherit_vel_y = (inherit_vel_y or 0) * vel_inherit_mult
    inherit_vel_z = (inherit_vel_z or 0) * vel_inherit_mult
    local particles_per_hitbox = ui_particle_count:get()
    local base_size = ui_particle_size:get()
    local drift_mult = ui_drift_speed:get() * 0.01
    local dissolve_style = ui_dissolve_style:get()
    local particle_shape = ui_particle_shape:get()
    local is_lines = particle_shape == "Lines"
    local is_mixed = particle_shape == "Mixed"
    local delay_spread = ui_delay_spread:get() * 0.01 * 2.0
    local size_variation = ui_size_variation:get() * 0.01
    local size_min = base_size * (1 - size_variation * 0.5)
    local size_max = base_size * (1 + size_variation * 0.5)
    if size_min < 0.5 then size_min = 0.5 end
    local hitbox_positions = {}
    if player then
        for i = 0, HITBOX_COUNT - 1 do
            local hpos = player:get_hitbox_pos(i)
            if hpos then
                hitbox_positions[#hitbox_positions + 1] = {x = hpos.x, y = hpos.y, z = hpos.z}
            end
        end
    end
    local num_hitboxes = #hitbox_positions
    local estimated_count = num_hitboxes > 0 and (num_hitboxes * particles_per_hitbox) or (particles_per_hitbox * 8)
    local p_x, p_y, p_z, p_vel_x, p_vel_y, p_vel_z
    local p_size, p_intensity, p_dissolve_delay, p_dissolve_speed
    local p_active, p_faded, p_is_line, p_line_angle, p_line_length
    local p_spin_offset, p_turb_offset, p_color_offset
    local use_ffi = ffi_ok
    if use_ffi then
        p_x = ffi.new("float[?]", estimated_count + 1)
        p_y = ffi.new("float[?]", estimated_count + 1)
        p_z = ffi.new("float[?]", estimated_count + 1)
        p_vel_x = ffi.new("float[?]", estimated_count + 1)
        p_vel_y = ffi.new("float[?]", estimated_count + 1)
        p_vel_z = ffi.new("float[?]", estimated_count + 1)
        p_size = ffi.new("float[?]", estimated_count + 1)
        p_intensity = ffi.new("float[?]", estimated_count + 1)
        p_dissolve_delay = ffi.new("float[?]", estimated_count + 1)
        p_dissolve_speed = ffi.new("float[?]", estimated_count + 1)
        p_active = ffi.new("bool[?]", estimated_count + 1)
        p_faded = ffi.new("bool[?]", estimated_count + 1)
        p_is_line = ffi.new("bool[?]", estimated_count + 1)
        p_line_angle = ffi.new("float[?]", estimated_count + 1)
        p_line_length = ffi.new("float[?]", estimated_count + 1)
        p_spin_offset = ffi.new("float[?]", estimated_count + 1)
        p_turb_offset = ffi.new("float[?]", estimated_count + 1)
        p_color_offset = ffi.new("float[?]", estimated_count + 1)
    else
        p_x, p_y, p_z = {}, {}, {}
        p_vel_x, p_vel_y, p_vel_z = {}, {}, {}
        p_size, p_intensity = {}, {}
        p_dissolve_delay, p_dissolve_speed = {}, {}
        p_active, p_faded = {}, {}
        p_is_line, p_line_angle, p_line_length = {}, {}, {}
        p_spin_offset, p_turb_offset, p_color_offset = {}, {}, {}
    end
    local style_thanos = dissolve_style == "Thanos Snap"
    local style_float = dissolve_style == "Float Up"
    local style_scatter = dissolve_style == "Scatter"
    local style_implode = dissolve_style == "Implode"
    local origin_z_40 = z + 40
    local n = 0
    local function add_particle(px, py, pz)
        n = n + 1
        local idx = use_ffi and (n - 1) or n
        local vel_x, vel_y, vel_z
        if style_thanos then
            local drift_angle = random_float(0.7, 1.7)
            local drift_speed = random_float(8, 30) * drift_mult
            vel_x = math_cos(drift_angle) * drift_speed
            vel_y = math_sin(drift_angle) * drift_speed
            vel_z = random_float(3, 15) * drift_mult
        elseif style_float then
            vel_x = random_float(-5, 5) * drift_mult
            vel_y = random_float(-5, 5) * drift_mult
            vel_z = random_float(20, 40) * drift_mult
        elseif style_scatter then
            local angle = random_float(0, TWO_PI)
            local speed = random_float(15, 50) * drift_mult
            vel_x = math_cos(angle) * speed
            vel_y = math_sin(angle) * speed
            vel_z = random_float(-20, 30) * drift_mult
        elseif style_implode then
            local dx = x - px
            local dy = y - py
            local dz = origin_z_40 - pz
            local inv_dist = 1 / (math_sqrt(dx*dx + dy*dy + dz*dz) + 0.1)
            local speed = random_float(20, 40) * drift_mult
            vel_x = -dx * inv_dist * speed
            vel_y = -dy * inv_dist * speed
            vel_z = -dz * inv_dist * speed
        end
        vel_x = vel_x + inherit_vel_x
        vel_y = vel_y + inherit_vel_y
        vel_z = vel_z + inherit_vel_z
        p_x[idx], p_y[idx], p_z[idx] = px, py, pz
        p_vel_x[idx], p_vel_y[idx], p_vel_z[idx] = vel_x, vel_y, vel_z
        p_size[idx] = random_float(size_min, size_max)
        p_intensity[idx] = random_float(0.7, 1.0)
        p_dissolve_delay[idx] = random_float(0, delay_spread)
        p_dissolve_speed[idx] = random_float(0.8, 1.4)
        p_active[idx] = false
        p_faded[idx] = false
        p_spin_offset[idx] = random_float(0, TWO_PI)
        p_turb_offset[idx] = random_float(0, 100)
        p_color_offset[idx] = random_float(0, 1)
        local is_line = is_lines or (is_mixed and random_int(0, 1) == 1)
        p_is_line[idx] = is_line
        p_line_angle[idx] = is_line and random_float(0, TWO_PI) or 0
        p_line_length[idx] = is_line and random_float(8, 20) or 0
    end
    if num_hitboxes > 0 then
        for h = 1, num_hitboxes do
            local hitbox = hitbox_positions[h]
            local hx, hy, hz = hitbox.x, hitbox.y, hitbox.z
            for i = 1, particles_per_hitbox do
                add_particle(
                    hx + random_float(-5, 5),
                    hy + random_float(-5, 5),
                    hz + random_float(-5, 5)
                )
            end
        end
    else
        local count_mult = particles_per_hitbox * 0.0667
        local parts = {
            {x, y, z + 68, math_floor(12 * count_mult), 5},
            {x, y, z + 50, math_floor(25 * count_mult), 10},
            {x, y, z + 38, math_floor(25 * count_mult), 10},
            {x - 18, y, z + 50, math_floor(15 * count_mult), 4},
            {x + 18, y, z + 50, math_floor(15 * count_mult), 4},
            {x - 5, y, z + 18, math_floor(18 * count_mult), 5},
            {x + 5, y, z + 18, math_floor(18 * count_mult), 5},
        }
        for p = 1, 7 do
            local part = parts[p]
            local bx, by, bz, count, spread = part[1], part[2], part[3], part[4], part[5]
            for i = 1, count do
                add_particle(
                    bx + random_float(-spread, spread),
                    by + random_float(-spread, spread),
                    bz + random_float(-spread, spread)
                )
            end
        end
    end
    death_particles[#death_particles + 1] = {
        x = p_x, y = p_y, z = p_z,
        vel_x = p_vel_x, vel_y = p_vel_y, vel_z = p_vel_z,
        size = p_size, intensity = p_intensity,
        dissolve_delay = p_dissolve_delay, dissolve_speed = p_dissolve_speed,
        active = p_active, faded = p_faded,
        is_line = p_is_line, line_angle = p_line_angle, line_length = p_line_length,
        spin_offset = p_spin_offset, turb_offset = p_turb_offset, color_offset = p_color_offset,
        count = n,
        spawn_time = spawn_time,
        is_implode = style_implode,
        use_ffi = use_ffi,
        secondary_particles = {},
        secondary_spawn_timer = 0
    }
end
local function create_secondary_particle(x, y, z, parent_vel_x, parent_vel_y, parent_vel_z)
    return {
        x = x, y = y, z = z,
        vel_x = parent_vel_x * 0.3 + random_float(-10, 10),
        vel_y = parent_vel_y * 0.3 + random_float(-10, 10),
        vel_z = parent_vel_z * 0.3 + random_float(-5, 15),
        size = random_float(0.5, 2),
        life = random_float(0.2, 0.5),
        spawn_time = globals.get_real_time(),
        hue_offset = random_float(-20, 20)
    }
end
local function draw_ethereal_glow_circle(sx, sy, alpha, size, intensity, r, g, b, glow_mult)
    if not glow_texture_id then
        local core_alpha = math_floor(alpha * intensity * 0.85)
        if core_alpha > 0 then
            render.filled_circle(vector2d(sx, sy), size, color(r, g, b, core_alpha))
        end
        return
    end
    local tex_size = size * (2 + glow_mult * 1.5)
    local half_size = tex_size / 2
    local final_alpha = math_floor(alpha * intensity * (0.7 + glow_mult * 0.3))
    if final_alpha < 2 then return end
    if final_alpha > 255 then final_alpha = 255 end
    render.image(glow_texture_id, vector2d(sx - half_size, sy - half_size), vector2d(tex_size, tex_size), color(r, g, b, final_alpha))
end
local function draw_ethereal_glow_line(sx, sy, alpha, size, intensity, r, g, b, glow_mult, angle, length)
    local half_len = length * size * 0.4
    local cos_a = math_cos(angle)
    local sin_a = math_sin(angle)
    local x1 = sx - cos_a * half_len
    local y1 = sy - sin_a * half_len
    local x2 = sx + cos_a * half_len
    local y2 = sy + sin_a * half_len
    local base_alpha = alpha * intensity
    if base_alpha < 2 then return end
    if glow_mult > 0.1 then
        local glow_alpha = math_floor(base_alpha * 0.15 * glow_mult)
        if glow_alpha > 1 then
            local perp_x = -sin_a * size * 0.8
            local perp_y = cos_a * size * 0.8
            render.line(vector2d(x1 + perp_x, y1 + perp_y), vector2d(x2 + perp_x, y2 + perp_y), color(r, g, b, glow_alpha))
            render.line(vector2d(x1 - perp_x, y1 - perp_y), vector2d(x2 - perp_x, y2 - perp_y), color(r, g, b, glow_alpha))
        end
        local mid_alpha = math_floor(base_alpha * 0.25 * glow_mult)
        if mid_alpha > 1 then
            local perp_x2 = -sin_a * size * 0.4
            local perp_y2 = cos_a * size * 0.4
            render.line(vector2d(x1 + perp_x2, y1 + perp_y2), vector2d(x2 + perp_x2, y2 + perp_y2), color(r, g, b, mid_alpha))
            render.line(vector2d(x1 - perp_x2, y1 - perp_y2), vector2d(x2 - perp_x2, y2 - perp_y2), color(r, g, b, mid_alpha))
        end
    end
    local core_alpha = math_floor(base_alpha * 0.9)
    if core_alpha > 255 then core_alpha = 255 end
    if core_alpha > 0 then
        render.line(vector2d(x1, y1), vector2d(x2, y2), color(r, g, b, core_alpha))
    end
    if glow_texture_id and glow_mult > 0.2 then
        local center_alpha = math_floor(base_alpha * 0.5 * glow_mult)
        if center_alpha > 255 then center_alpha = 255 end
        if center_alpha > 2 then
            local tex_size = size * 1.5
            local half_size = tex_size / 2
            render.image(glow_texture_id, vector2d(sx - half_size, sy - half_size), vector2d(tex_size, tex_size), color(r, g, b, center_alpha))
        end
    end
end
local function create_kill_trail(start_x, start_y, start_z)
    local spawn_time = globals.get_real_time()
    local local_player = entities.get_local_player()
    if not local_player then return end
    local trail_density = ui_kill_trail_density:get()
    local trail_curve = ui_kill_trail_curve:get() * 0.01
    local trail_style = ui_kill_trail_style:get()
    local player_origin = local_player:get_origin()
    if not player_origin then return end
    local player_x, player_y, player_z = player_origin.x, player_origin.y, player_origin.z
    player_z = player_z + 40
    local dx = player_x - start_x
    local dy = player_y - start_y
    local dz = player_z - start_z
    local dist = math_sqrt(dx*dx + dy*dy + dz*dz)
    local mid_x = (start_x + player_x) * 0.5
    local mid_y = (start_y + player_y) * 0.5
    local mid_z = (start_z + player_z) * 0.5 + 80 + trail_curve * dist * 0.3
    local curve_strength = trail_curve * dist * 0.2
    local perp_x = -dy / (dist + 1)
    local perp_y = dx / (dist + 1)
    local curve_dir = random_float(-1, 1)
    mid_x = mid_x + perp_x * curve_strength * curve_dir
    mid_y = mid_y + perp_y * curve_strength * curve_dir
    local particles = {}
    for i = 1, trail_density do
        local t = (i - 1) / (trail_density - 1)
        local size_mult = 0.6 + 0.8 * math_sin(t * 3.14159)
        particles[i] = {
            t = t,
            offset_x = random_float(-12, 12),
            offset_y = random_float(-12, 12),
            offset_z = random_float(-8, 8),
            size = random_float(2, 5) * size_mult,
            intensity = random_float(0.7, 1.0),
            phase = random_float(0, TWO_PI),
            wave_phase = random_float(0, TWO_PI),
            hue_offset = random_float(-20, 20),
            active = false,
            fade_alpha = 0,
            drift_speed = random_float(0.8, 1.2),
            orbit_radius = random_float(5, 15)
        }
    end
    local is_spiral = trail_style == "Spiral"
    local is_lightning = trail_style == "Lightning"
    local is_beam = trail_style == "Energy Beam"
    kill_trails[#kill_trails + 1] = {
        start_x = start_x,
        start_y = start_y,
        start_z = start_z,
        mid_x = mid_x,
        mid_y = mid_y,
        mid_z = mid_z,
        end_x = player_x,
        end_y = player_y,
        end_z = player_z,
        particles = particles,
        spawn_time = spawn_time,
        progress = 0,
        style = trail_style,
        is_spiral = is_spiral,
        is_lightning = is_lightning,
        is_beam = is_beam,
        completed = false,
        fade_out = false,
        fade_start = 0,
        lightning_segments = {},
        lightning_update_time = 0,
        emitters = {},
        last_emit_time = spawn_time,
        impact_triggered = false
    }
end
local function bezier_point(t, x0, y0, z0, x1, y1, z1, x2, y2, z2)
    local inv_t = 1 - t
    local inv_t2 = inv_t * inv_t
    local t2 = t * t
    local two_inv_t_t = 2 * inv_t * t
    return inv_t2 * x0 + two_inv_t_t * x1 + t2 * x2,
           inv_t2 * y0 + two_inv_t_t * y1 + t2 * y2,
           inv_t2 * z0 + two_inv_t_t * z1 + t2 * z2
end
local function generate_lightning_segments(start_x, start_y, start_z, end_x, end_y, end_z, segments)
    local result = {}
    local num_segments = 8
    for i = 0, num_segments do
        local t = i / num_segments
        local x = start_x + (end_x - start_x) * t
        local y = start_y + (end_y - start_y) * t
        local z = start_z + (end_z - start_z) * t
        if i > 0 and i < num_segments then
            local offset_scale = 30 * math_sin(t * 3.14159)
            x = x + random_float(-offset_scale, offset_scale)
            y = y + random_float(-offset_scale, offset_scale)
            z = z + random_float(-offset_scale * 0.5, offset_scale * 0.5)
        end
        result[i + 1] = {x = x, y = y, z = z}
    end
    return result
end
local function update_kill_trails(dt, current_time)
    if not ui_kill_trail:get() then return end
    local local_player = entities.get_local_player()
    if not local_player or not local_player:is_alive() then return end
    local player_origin = local_player:get_origin()
    if not player_origin then return end
    local player_x, player_y, player_z = player_origin.x, player_origin.y, player_origin.z
    player_z = player_z + 40
    local trail_speed = ui_kill_trail_speed:get() * 0.025
    for i = #kill_trails, 1, -1 do
        local trail = kill_trails[i]
        if trail.fade_out then
            local fade_age = current_time - trail.fade_start
            if fade_age > 1.2 then
                table_remove(kill_trails, i)
                goto next_trail
            end
        end
        if not trail.completed then
            local speed_mult = 0.5 + trail.progress * 1.5
            trail.progress = trail.progress + dt * trail_speed * speed_mult
            if trail.progress >= 1 then
                trail.progress = 1
                trail.completed = true
                trail.fade_out = true
                trail.fade_start = current_time
                trail.impact_triggered = true
            end
        end
        local lerp_speed = 8 * dt
        trail.end_x = trail.end_x + (player_x - trail.end_x) * lerp_speed
        trail.end_y = trail.end_y + (player_y - trail.end_y) * lerp_speed
        trail.end_z = trail.end_z + (player_z - trail.end_z) * lerp_speed
        if not trail.fade_out and current_time - trail.last_emit_time > 0.03 then
            trail.last_emit_time = current_time
            local head_x, head_y, head_z = bezier_point(
                trail.progress,
                trail.start_x, trail.start_y, trail.start_z,
                trail.mid_x, trail.mid_y, trail.mid_z,
                trail.end_x, trail.end_y, trail.end_z
            )
            if #trail.emitters < 50 then
                trail.emitters[#trail.emitters + 1] = {
                    x = head_x + random_float(-5, 5),
                    y = head_y + random_float(-5, 5),
                    z = head_z + random_float(-5, 5),
                    vel_x = random_float(-20, 20),
                    vel_y = random_float(-20, 20),
                    vel_z = random_float(-10, 30),
                    size = random_float(1, 2.5),
                    life = random_float(0.3, 0.7),
                    spawn_time = current_time,
                    hue_offset = random_float(-30, 30)
                }
            end
        end
        for k = #trail.emitters, 1, -1 do
            local e = trail.emitters[k]
            local age = current_time - e.spawn_time
            if age > e.life then
                table_remove(trail.emitters, k)
            else
                e.x = e.x + e.vel_x * dt
                e.y = e.y + e.vel_y * dt
                e.z = e.z + e.vel_z * dt
                e.vel_z = e.vel_z - 80 * dt
                e.vel_x = e.vel_x * 0.98
                e.vel_y = e.vel_y * 0.98
            end
        end
        if trail.is_lightning and current_time - trail.lightning_update_time > 0.04 then
            local head_t = trail.progress
            local head_x, head_y, head_z = bezier_point(
                head_t,
                trail.start_x, trail.start_y, trail.start_z,
                trail.mid_x, trail.mid_y, trail.mid_z,
                trail.end_x, trail.end_y, trail.end_z
            )
            trail.lightning_segments = generate_lightning_segments(
                trail.start_x, trail.start_y, trail.start_z,
                head_x, head_y, head_z, 8
            )
            trail.lightning_update_time = current_time
        end
        local particles = trail.particles
        for j = 1, #particles do
            local p = particles[j]
            if not p.active and p.t <= trail.progress then
                p.active = true
                p.activate_time = current_time
            end
            if p.active then
                if trail.fade_out then
                    local fade_age = current_time - trail.fade_start
                    local stagger = (1 - p.t) * 0.3
                    p.fade_alpha = math_max(0, 1 - (fade_age - stagger) / 0.8)
                else
                    local dist_from_head = trail.progress - p.t
                    local head_fade = math_max(0, 1 - dist_from_head * 2.5)
                    local activate_age = current_time - (p.activate_time or current_time)
                    local fade_in = math_min(1, activate_age * 8)
                    p.fade_alpha = fade_in * (0.4 + head_fade * 0.6)
                end
            end
        end
        ::next_trail::
    end
end
local function render_kill_trails()
    if not ui_kill_trail:get() then return end
    if #kill_trails == 0 then return end
    local current_time = globals.get_real_time()
    local cam_pos = camera.get_pos()
    local cam_angles = camera.get_angles()
    local cam_x, cam_y, cam_z = cam_pos.x, cam_pos.y, cam_pos.z
    local cam_pitch, cam_yaw = cam_angles.x, cam_angles.y
    local cam_pitch_rad = cam_pitch * 0.0174533
    local cam_yaw_rad = cam_yaw * 0.0174533
    local cos_pitch = math_cos(cam_pitch_rad)
    local fwd_x = cos_pitch * math_cos(cam_yaw_rad)
    local fwd_y = cos_pitch * math_sin(cam_yaw_rad)
    local fwd_z = -math_sin(cam_pitch_rad)
    local trail_col = ui_kill_trail_color:get()
    local r, g, b = trail_col.r, trail_col.g, trail_col.b
    local glow_mult = ui_glow_intensity:get() * 0.01
    for i = 1, #kill_trails do
        local trail = kill_trails[i]
        local particles = trail.particles
        local trail_fade = 1
        if trail.fade_out then
            trail_fade = math_max(0, 1 - (current_time - trail.fade_start) / 1.0)
        end
        if trail.is_lightning and #trail.lightning_segments > 1 then
            local segments = trail.lightning_segments
            for j = 1, #segments - 1 do
                local s1 = segments[j]
                local s2 = segments[j + 1]
                local screen1 = vector(s1.x, s1.y, s1.z):to_screen()
                local screen2 = vector(s2.x, s2.y, s2.z):to_screen()
                if screen1 and screen2 then
                    local sx1, sy1 = screen1.x, screen1.y
                    local sx2, sy2 = screen2.x, screen2.y
                    local glow_alpha = math_floor(60 * trail_fade * glow_mult)
                    if glow_alpha > 1 then
                        render.line(vector2d(sx1 - 1, sy1), vector2d(sx2 - 1, sy2), color(r, g, b, glow_alpha))
                        render.line(vector2d(sx1 + 1, sy1), vector2d(sx2 + 1, sy2), color(r, g, b, glow_alpha))
                        render.line(vector2d(sx1, sy1 - 1), vector2d(sx2, sy2 - 1), color(r, g, b, glow_alpha))
                        render.line(vector2d(sx1, sy1 + 1), vector2d(sx2, sy2 + 1), color(r, g, b, glow_alpha))
                    end
                    local mid_alpha = math_floor(120 * trail_fade)
                    if mid_alpha > 1 then
                        render.line(vector2d(sx1, sy1), vector2d(sx2, sy2), color(r, g, b, mid_alpha))
                    end
                    local core_alpha = math_floor(220 * trail_fade)
                    if core_alpha > 1 then
                        render.line(vector2d(sx1, sy1), vector2d(sx2, sy2), color(255, 255, 255, core_alpha))
                    end
                    if glow_texture_id and j > 1 and j < #segments - 1 then
                        local node_size = (6 + random_float(0, 4)) * trail_fade
                        local flicker = 0.7 + 0.3 * math_sin(current_time * 30 + j * 2)
                        render.image(glow_texture_id, vector2d(sx1 - node_size/2, sy1 - node_size/2), vector2d(node_size, node_size), color(r, g, b, math_floor(150 * trail_fade * flicker)))
                    end
                end
            end
        end
        for k = 1, #trail.emitters do
            local e = trail.emitters[k]
            local age = current_time - e.spawn_time
            local life_ratio = age / e.life
            local e_fade = 1 - life_ratio
            if e_fade > 0 then
                local screen = vector(e.x, e.y, e.z):to_screen()
                if screen then
                    local esx, esy = screen.x, screen.y
                    local edx = e.x - cam_x
                    local edy = e.y - cam_y
                    local edz = e.z - cam_z
                    local edist = math_sqrt(edx*edx + edy*edy + edz*edz)
                    local e_size = e.size * (500 / (edist > 1 and edist or 1)) * e_fade
                    local er, eg, eb = r, g, b
                    if e.hue_offset ~= 0 then
                        er, eg, eb = shift_hue(r, g, b, e.hue_offset)
                    end
                    local e_alpha = math_floor(200 * e_fade * trail_fade)
                    if glow_texture_id and e_alpha > 2 then
                        render.image(glow_texture_id, vector2d(esx - e_size, esy - e_size), vector2d(e_size * 2, e_size * 2), color(er, eg, eb, e_alpha))
                    end
                end
            end
        end
        local visible = {}
        for j = 1, #particles do
            local p = particles[j]
            if p.active and p.fade_alpha > 0.01 then
                local base_x, base_y, base_z = bezier_point(
                    p.t,
                    trail.start_x, trail.start_y, trail.start_z,
                    trail.mid_x, trail.mid_y, trail.mid_z,
                    trail.end_x, trail.end_y, trail.end_z
                )
                local offset_x, offset_y, offset_z = p.offset_x, p.offset_y, p.offset_z
                local time_offset = current_time * p.drift_speed
                if trail.is_spiral then
                    local spiral_angle = p.phase + time_offset * 6 + p.t * 12
                    local spiral_radius = p.orbit_radius * (0.8 + 0.4 * math_sin(p.t * TWO_PI * 3))
                    offset_x = math_cos(spiral_angle) * spiral_radius
                    offset_y = math_sin(spiral_angle) * spiral_radius
                    offset_z = math_sin(spiral_angle * 0.5 + p.wave_phase) * 8
                elseif trail.is_beam then
                    local pulse = 0.3 + 0.7 * math_max(0, math_sin(time_offset * 12 - p.t * 8))
                    local beam_radius = 3 + pulse * 5
                    offset_x = math_cos(p.phase) * beam_radius
                    offset_y = math_sin(p.phase) * beam_radius
                    offset_z = math_sin(p.wave_phase + time_offset * 4) * beam_radius * 0.5
                else
                    local flow = math_sin(time_offset * 3 + p.phase + p.t * 5)
                    local wave = math_cos(time_offset * 2 + p.wave_phase + p.t * 3)
                    offset_x = offset_x * 0.7 + flow * 8
                    offset_y = offset_y * 0.7 + wave * 8
                    offset_z = offset_z * 0.5 + math_sin(time_offset * 4 + p.t * 6) * 5
                end
                local px = base_x + offset_x
                local py = base_y + offset_y
                local pz = base_z + offset_z
                local dx, dy, dz = px - cam_x, py - cam_y, pz - cam_z
                local dot = dx * fwd_x + dy * fwd_y + dz * fwd_z
                if dot > -50 then
                    local screen = vector(px, py, pz):to_screen()
                    if screen then
                        local sx, sy = screen.x, screen.y
                        local dist = math_sqrt(dx*dx + dy*dy + dz*dz)
                        local clamped_dist = dist > 1 and dist or 1
                        local pr, pg, pb = r, g, b
                        if p.hue_offset ~= 0 then
                            pr, pg, pb = shift_hue(r, g, b, p.hue_offset)
                        end
                        local head_dist = math_abs(trail.progress - p.t)
                        local head_glow = math_max(0, 1 - head_dist * 3)
                        local alpha = math_floor(255 * p.fade_alpha * p.intensity * trail_fade)
                        if alpha > 255 then alpha = 255 end
                        local size = p.size * (500 / clamped_dist) * (0.6 + head_glow * 0.8)
                        visible[#visible + 1] = {
                            sx = sx, sy = sy,
                            dist = dist,
                            alpha = alpha,
                            size = size,
                            intensity = p.intensity * (0.6 + head_glow * 0.4),
                            r = pr, g = pg, b = pb,
                            head_glow = head_glow
                        }
                    end
                end
            end
        end
        if trail.progress > 0 and trail.progress <= 1 and not trail.fade_out then
            local head_x, head_y, head_z = bezier_point(
                trail.progress,
                trail.start_x, trail.start_y, trail.start_z,
                trail.mid_x, trail.mid_y, trail.mid_z,
                trail.end_x, trail.end_y, trail.end_z
            )
            local head_screen = vector(head_x, head_y, head_z):to_screen()
            if head_screen then
                local hsx, hsy = head_screen.x, head_screen.y
                local hdx = head_x - cam_x
                local hdy = head_y - cam_y
                local hdz = head_z - cam_z
                local hdist = math_sqrt(hdx*hdx + hdy*hdy + hdz*hdz)
                local base_size = 500 / (hdist > 1 and hdist or 1)
                local pulse = 0.7 + 0.3 * math_sin(current_time * 20)
                if glow_texture_id then
                    local outer_size = base_size * 18 * pulse
                    render.image(glow_texture_id, vector2d(hsx - outer_size/2, hsy - outer_size/2), vector2d(outer_size, outer_size), color(r, g, b, math_floor(80 * pulse)))
                    local mid_size = base_size * 10 * pulse
                    render.image(glow_texture_id, vector2d(hsx - mid_size/2, hsy - mid_size/2), vector2d(mid_size, mid_size), color(r, g, b, math_floor(180 * pulse)))
                    local inner_size = base_size * 5 * pulse
                    render.image(glow_texture_id, vector2d(hsx - inner_size/2, hsy - inner_size/2), vector2d(inner_size, inner_size), color(255, 255, 255, math_floor(255 * pulse)))
                end
            end
        end
        if trail.impact_triggered and trail.fade_out then
            local impact_age = current_time - trail.fade_start
            if impact_age < 0.3 then
                local impact_progress = impact_age / 0.3
                local impact_fade = 1 - impact_progress
                local ring_size = 20 + impact_progress * 80
                local impact_screen = vector(trail.end_x, trail.end_y, trail.end_z):to_screen()
                if impact_screen and glow_texture_id then
                    local isx, isy = impact_screen.x, impact_screen.y
                    local ring_alpha = math_floor(200 * impact_fade)
                    render.image(glow_texture_id, vector2d(isx - ring_size/2, isy - ring_size/2), vector2d(ring_size, ring_size), color(r, g, b, ring_alpha))
                    local flash_size = ring_size * 0.4 * impact_fade
                    render.image(glow_texture_id, vector2d(isx - flash_size/2, isy - flash_size/2), vector2d(flash_size, flash_size), color(255, 255, 255, math_floor(255 * impact_fade)))
                end
            end
        end
        if #visible > 1 then
            table.sort(visible, function(a, b) return a.dist > b.dist end)
        end
        for j = 1, #visible do
            local p = visible[j]
            draw_ethereal_glow_circle(p.sx, p.sy, p.alpha, p.size, p.intensity, p.r, p.g, p.b, glow_mult)
        end
    end
end
local function create_self_particles()
    local spawn_time = globals.get_real_time()
    local particles = {}
    local num_particles = 20
    for i = 1, num_particles do
        local angle = (i - 1) / num_particles * TWO_PI
        particles[i] = {
            angle = angle,
            radius = random_float(18, 30),
            z_offset = random_float(-15, 25),
            size = random_float(2, 5),
            speed = random_float(0.6, 1.4),
            phase = random_float(0, TWO_PI),
            hue_offset = random_float(-30, 30),
            vertical_speed = random_float(0.3, 0.8)
        }
    end
    self_particles[1] = {
        particles = particles,
        spawn_time = spawn_time
    }
end
local function update_self_particles(dt, current_time)
    local should_be_active = ui_self_particles:get()
    local local_player = entities.get_local_player()
    local is_alive = local_player and local_player:is_alive()
    local is_thirdperson = false
    if is_alive then
        is_thirdperson = not camera.is_in_first_person()
    end
    if should_be_active and is_alive and is_thirdperson then
        if not self_particles_active then
            create_self_particles()
            self_particles_active = true
        end
    else
        if self_particles_active then
            self_particles = {}
            self_particles_active = false
        end
    end
end
local function render_self_particles()
    if #self_particles == 0 then return end
    local local_player = entities.get_local_player()
    if not local_player or not local_player:is_alive() then return end
    local origin = local_player:get_origin()
    if not origin then return end
    local px, py, pz = origin.x, origin.y, origin.z
    pz = pz + 45
    local current_time = globals.get_real_time()
    local cam_pos = camera.get_pos()
    local cam_x, cam_y, cam_z = cam_pos.x, cam_pos.y, cam_pos.z
    local self_col = ui_self_particles_color:get()
    local r, g, b = self_col.r, self_col.g, self_col.b
    local glow_mult = ui_glow_intensity:get() * 0.01
    for i = 1, #self_particles do
        local effect = self_particles[i]
        local particles = effect.particles
        local age = current_time - effect.spawn_time
        local fade = math_min(1, age * 2)
        for j = 1, #particles do
            local p = particles[j]
            local orbit_angle = p.angle + age * 3 * p.speed
            local bob = math_sin(age * 4 + p.phase) * 8
            local vertical_wave = math_sin(age * p.vertical_speed * 2 + p.phase) * 12
            local radius = p.radius + math_sin(age * 2 + p.phase) * 6
            local wave_offset = math_sin(age * 5 + p.phase * 2) * 3
            radius = radius + wave_offset
            local part_x = px + math_cos(orbit_angle) * radius
            local part_y = py + math_sin(orbit_angle) * radius
            local part_z = pz + p.z_offset + bob + vertical_wave
            local screen = vector(part_x, part_y, part_z):to_screen()
            if screen then
                local sx, sy = screen.x, screen.y
                local dx = part_x - cam_x
                local dy = part_y - cam_y
                local dz = part_z - cam_z
                local dist = math_sqrt(dx*dx + dy*dy + dz*dz)
                local size = p.size * (500 / (dist > 1 and dist or 1)) * fade
                local pulse = 0.7 + 0.3 * math_sin(age * 3 + p.phase)
                local alpha = math_floor(180 * fade * pulse)
                local pr, pg, pb = r, g, b
                if p.hue_offset ~= 0 then
                    pr, pg, pb = shift_hue(r, g, b, p.hue_offset)
                end
                draw_ethereal_glow_circle(sx, sy, alpha, size, 0.9, pr, pg, pb, glow_mult)
            end
        end
    end
end
local function spawn_firefly(cam_x, cam_y, cam_z, range)
    local current_time = globals.get_real_time()
    local angle = random_float(0, TWO_PI)
    local dist = random_float(50, range)
    local height_offset = random_float(-50, 100)
    local x = cam_x + math_cos(angle) * dist
    local y = cam_y + math_sin(angle) * dist
    local z = cam_z + height_offset
    fireflies[#fireflies + 1] = {
        x = x, y = y, z = z,
        vel_x = random_float(-15, 15),
        vel_y = random_float(-15, 15),
        vel_z = random_float(-5, 10),
        spawn_time = current_time,
        life = random_float(2, 5),
        phase = random_float(0, TWO_PI),
        flicker_speed = random_float(3, 8),
        drift_phase = random_float(0, TWO_PI),
        hue_offset = random_float(-20, 20)
    }
end
local function update_fireflies(dt, current_time)
    if not ui_fireflies:get() then
        fireflies = {}
        return
    end
    local cam_pos = camera.get_pos()
    if not cam_pos then return end
    local cam_x, cam_y, cam_z = cam_pos.x, cam_pos.y, cam_pos.z
    local max_fireflies = ui_fireflies_amount:get()
    local range = ui_fireflies_range:get()
    firefly_spawn_timer = firefly_spawn_timer + dt
    local spawn_interval = 0.15
    while firefly_spawn_timer >= spawn_interval and #fireflies < max_fireflies do
        spawn_firefly(cam_x, cam_y, cam_z, range)
        firefly_spawn_timer = firefly_spawn_timer - spawn_interval
    end
    for i = #fireflies, 1, -1 do
        local f = fireflies[i]
        local age = current_time - f.spawn_time
        if age > f.life then
            table_remove(fireflies, i)
        else
            local drift_x = math_sin(current_time * 0.8 + f.drift_phase) * 20
            local drift_y = math_cos(current_time * 0.6 + f.drift_phase * 1.3) * 20
            local drift_z = math_sin(current_time * 0.4 + f.drift_phase * 0.7) * 10
            f.x = f.x + (f.vel_x + drift_x) * dt
            f.y = f.y + (f.vel_y + drift_y) * dt
            f.z = f.z + (f.vel_z + drift_z) * dt
            f.vel_x = f.vel_x + random_float(-30, 30) * dt
            f.vel_y = f.vel_y + random_float(-30, 30) * dt
            f.vel_z = f.vel_z + random_float(-15, 15) * dt
            local max_vel = 25
            if f.vel_x > max_vel then f.vel_x = max_vel end
            if f.vel_x < -max_vel then f.vel_x = -max_vel end
            if f.vel_y > max_vel then f.vel_y = max_vel end
            if f.vel_y < -max_vel then f.vel_y = -max_vel end
            if f.vel_z > max_vel * 0.5 then f.vel_z = max_vel * 0.5 end
            if f.vel_z < -max_vel * 0.5 then f.vel_z = -max_vel * 0.5 end
            local dx = f.x - cam_x
            local dy = f.y - cam_y
            local dz = f.z - cam_z
            local dist_sq = dx*dx + dy*dy + dz*dz
            if dist_sq > range * range * 1.5 then
                table_remove(fireflies, i)
            end
        end
    end
end
local function render_fireflies()
    if #fireflies == 0 then return end
    local current_time = globals.get_real_time()
    local cam_pos = camera.get_pos()
    local cam_x, cam_y, cam_z = cam_pos.x, cam_pos.y, cam_pos.z
    local firefly_col = ui_fireflies_color:get()
    local r, g, b = firefly_col.r, firefly_col.g, firefly_col.b
    local base_size = ui_fireflies_size:get()
    for i = 1, #fireflies do
        local f = fireflies[i]
        local age = current_time - f.spawn_time
        local life_ratio = age / f.life
        local fade = 1
        if life_ratio < 0.1 then
            fade = life_ratio / 0.1
        elseif life_ratio > 0.8 then
            fade = (1 - life_ratio) / 0.2
        end
        local flicker = 0.3 + 0.7 * math_max(0, math_sin(current_time * f.flicker_speed + f.phase))
        flicker = flicker * (0.8 + 0.2 * math_sin(current_time * f.flicker_speed * 3 + f.phase * 2))
        local screen = vector(f.x, f.y, f.z):to_screen()
        if screen then
            local sx, sy = screen.x, screen.y
            local alpha = math_floor(255 * fade * flicker)
            if alpha > 5 then
                local fr, fg, fb = r, g, b
                if f.hue_offset ~= 0 then
                    fr, fg, fb = shift_hue(r, g, b, f.hue_offset)
                end
                if base_size <= 2 then
                    render.filled_rect(vector2d(sx, sy), vector2d(base_size, base_size), color(fr, fg, fb, alpha))
                else
                    if glow_texture_id then
                        local tex_size = base_size * 2
                        render.image(glow_texture_id, vector2d(sx - tex_size/2, sy - tex_size/2), vector2d(tex_size, tex_size), color(fr, fg, fb, alpha))
                    else
                        render.filled_rect(vector2d(sx - base_size/2, sy - base_size/2), vector2d(base_size, base_size), color(fr, fg, fb, alpha))
                    end
                end
                if alpha > 150 and glow_texture_id and base_size <= 4 then
                    local glow_size = base_size * 4
                    local glow_alpha = math_floor(alpha * 0.3)
                    render.image(glow_texture_id, vector2d(sx - glow_size/2, sy - glow_size/2), vector2d(glow_size, glow_size), color(fr, fg, fb, glow_alpha))
                end
            end
        end
    end
end
local function update_particles(dt, current_time, lifetime)
    local gravity = ui_gravity:get() * 0.5
    local spin_speed = ui_spin_speed:get() * 0.05
    local turbulence = ui_turbulence:get() * 0.3
    local spawn_secondary = ui_secondary_particles:get()
    local num_systems = #death_particles
    for i = num_systems, 1, -1 do
        local system = death_particles[i]
        local age = current_time - system.spawn_time
        if age > lifetime then
            table_remove(death_particles, i)
        else
            local s_x, s_y, s_z = system.x, system.y, system.z
            local s_vel_x, s_vel_y, s_vel_z = system.vel_x, system.vel_y, system.vel_z
            local s_dissolve_delay = system.dissolve_delay
            local s_dissolve_speed = system.dissolve_speed
            local s_active, s_faded = system.active, system.faded
            local s_line_angle = system.line_angle
            local s_spin_offset = system.spin_offset
            local s_turb_offset = system.turb_offset
            local is_implode = system.is_implode
            local num_particles = system.count
            local idx_offset = system.use_ffi and -1 or 0
            for j = 1, num_particles do
                local idx = j + idx_offset
                if s_faded[idx] then goto next_particle end
                local delay = s_dissolve_delay[idx]
                if not s_active[idx] then
                    if age >= delay then
                        s_active[idx] = true
                    else
                        goto next_particle
                    end
                end
                local dissolve_progress = (age - delay) * s_dissolve_speed[idx]
                if dissolve_progress > 1.5 then
                    s_faded[idx] = true
                    goto next_particle
                end
                local vel_mult
                if is_implode then
                    vel_mult = dt * (dissolve_progress < 0.7 and 1 or -2)
                else
                    vel_mult = dt * (1 + dissolve_progress * 0.5)
                end
                local new_x = s_x[idx] + s_vel_x[idx] * vel_mult
                local new_y = s_y[idx] + s_vel_y[idx] * vel_mult
                local new_z = s_z[idx] + s_vel_z[idx] * vel_mult
                s_vel_z[idx] = s_vel_z[idx] - gravity * dt
                if turbulence > 0 then
                    local turb_time = current_time * 3 + s_turb_offset[idx]
                    local turb_x = math_sin(turb_time * 1.3) * turbulence * dt
                    local turb_y = math_sin(turb_time * 1.7 + 2.1) * turbulence * dt
                    local turb_z = math_sin(turb_time * 1.1 + 4.3) * turbulence * dt
                    new_x = new_x + turb_x
                    new_y = new_y + turb_y
                    new_z = new_z + turb_z
                end
                if spin_speed > 0 then
                    s_line_angle[idx] = s_line_angle[idx] + spin_speed * dt + s_spin_offset[idx] * 0.01
                end
                s_x[idx] = new_x
                s_y[idx] = new_y
                s_z[idx] = new_z
                if spawn_secondary and dissolve_progress > 0.3 and dissolve_progress < 1.2 then
                    if random_float(0, 1) < 0.02 then
                        local sec = create_secondary_particle(
                            new_x, new_y, new_z,
                            s_vel_x[idx], s_vel_y[idx], s_vel_z[idx]
                        )
                        system.secondary_particles[#system.secondary_particles + 1] = sec
                    end
                end
                ::next_particle::
            end
            local sec_particles = system.secondary_particles
            for k = #sec_particles, 1, -1 do
                local sec = sec_particles[k]
                local sec_age = current_time - sec.spawn_time
                if sec_age > sec.life then
                    table_remove(sec_particles, k)
                else
                    sec.x = sec.x + sec.vel_x * dt
                    sec.y = sec.y + sec.vel_y * dt
                    sec.z = sec.z + sec.vel_z * dt
                    sec.vel_z = sec.vel_z - gravity * dt * 2
                end
            end
        end
    end
end
local function render_particles()
    if not ui_enabled:get() then return end
    local current_time = globals.get_real_time()
    local dt = globals.get_frame_time()
    local lifetime = ui_lifetime:get() * 0.1
    update_particles(dt, current_time, lifetime)
    local num_systems = #death_particles
    if num_systems == 0 then return end
    local cam_pos = camera.get_pos()
    local cam_angles = camera.get_angles()
    local cam_x, cam_y, cam_z = cam_pos.x, cam_pos.y, cam_pos.z
    local cam_pitch, cam_yaw = cam_angles.x, cam_angles.y
    local main_col = ui_color:get()
    local r, g, b = main_col.r, main_col.g, main_col.b
    local glow_mult = ui_glow_intensity:get() * 0.01
    local color_mode = ui_color_mode:get()
    local is_rainbow = color_mode == "Rainbow"
    local is_gradient = color_mode == "Gradient"
    local rainbow_speed = ui_rainbow_speed:get() * 3
    local sec_col = ui_secondary_color:get()
    local r2, g2, b2 = sec_col.r, sec_col.g, sec_col.b
    local use_connections = ui_particle_connections:get()
    local connection_dist = ui_connection_distance:get()
    local color_variation = ui_color_variation:get() * 0.5
    local cam_pitch_rad = cam_pitch * 0.0174533
    local cam_yaw_rad = cam_yaw * 0.0174533
    local cos_pitch = math_cos(cam_pitch_rad)
    local fwd_x = cos_pitch * math_cos(cam_yaw_rad)
    local fwd_y = cos_pitch * math_sin(cam_yaw_rad)
    local fwd_z = -math_sin(cam_pitch_rad)
    local fov_cos = 0.5
    local visible_particles = {}
    for i = 1, num_systems do
        local system = death_particles[i]
        local age = current_time - system.spawn_time
        local num_particles = system.count
        local idx_offset = system.use_ffi and -1 or 0
        local s_x, s_y, s_z = system.x, system.y, system.z
        local s_vel_x, s_vel_y, s_vel_z = system.vel_x, system.vel_y, system.vel_z
        local s_size, s_intensity = system.size, system.intensity
        local s_dissolve_delay, s_dissolve_speed = system.dissolve_delay, system.dissolve_speed
        local s_active, s_faded = system.active, system.faded
        local s_is_line, s_line_angle, s_line_length = system.is_line, system.line_angle, system.line_length
        local s_color_offset = system.color_offset
        local sys_center_x, sys_center_y, sys_center_z = 0, 0, 0
        local sample_count = 0
        local sample_step = math_floor(num_particles / 8) + 1
        for j = 1, num_particles, sample_step do
            local idx = j + idx_offset
            if not s_faded[idx] then
                sys_center_x = sys_center_x + s_x[idx]
                sys_center_y = sys_center_y + s_y[idx]
                sys_center_z = sys_center_z + s_z[idx]
                sample_count = sample_count + 1
            end
        end
        if sample_count == 0 then goto next_system end
        sys_center_x = sys_center_x / sample_count
        sys_center_y = sys_center_y / sample_count
        sys_center_z = sys_center_z / sample_count
        local sys_dx = sys_center_x - cam_x
        local sys_dy = sys_center_y - cam_y
        local sys_dz = sys_center_z - cam_z
        local sys_dist = math_sqrt(sys_dx * sys_dx + sys_dy * sys_dy + sys_dz * sys_dz)
        local sys_radius = 150
        if sys_dist > 1 then
            local inv_sys_dist = 1 / sys_dist
            local sys_dir_x = sys_dx * inv_sys_dist
            local sys_dir_y = sys_dy * inv_sys_dist
            local sys_dir_z = sys_dz * inv_sys_dist
            local sys_dot = sys_dir_x * fwd_x + sys_dir_y * fwd_y + sys_dir_z * fwd_z
            if sys_dot < -0.3 and sys_dist > sys_radius then
                goto next_system
            end
            local horiz_dot = sys_dir_x * fwd_x + sys_dir_y * fwd_y
            local horiz_dist = math_sqrt(sys_dir_x * sys_dir_x + sys_dir_y * sys_dir_y)
            if horiz_dist > 0.01 then
                local horiz_angle = horiz_dot / horiz_dist
                local sphere_angle_margin = sys_radius / (sys_dist + 1)
                if horiz_angle < fov_cos - sphere_angle_margin and sys_dist > sys_radius then
                    goto next_system
                end
            end
        end
        for j = 1, num_particles do
            local idx = j + idx_offset
            if s_faded[idx] then goto continue end
            local px, py, pz = s_x[idx], s_y[idx], s_z[idx]
            local dx, dy, dz = px - cam_x, py - cam_y, pz - cam_z
            local dist_sq = dx*dx + dy*dy + dz*dz
            if dist_sq > 4000000 then goto continue end
            local dot = dx * fwd_x + dy * fwd_y + dz * fwd_z
            if dot < -50 then goto continue end
            local screen = vector(px, py, pz):to_screen()
            if screen then
                local sx, sy = screen.x, screen.y
                local dist = math_sqrt(dist_sq)
                local clamped_dist = dist > 1 and dist or 1
                local inv_dist = 1 / clamped_dist
                local distance_scale = 500 * inv_dist
                local intensity_boost = clamped_dist * INV_500
                if intensity_boost < 1 then intensity_boost = 1 end
                if intensity_boost > 3 then intensity_boost = 3 end
                local alpha, size
                local p_size = s_size[idx]
                local dissolve_progress = 0
                if s_active[idx] then
                    dissolve_progress = (age - s_dissolve_delay[idx]) * s_dissolve_speed[idx]
                    local fade = 1 - dissolve_progress * INV_1_5
                    if fade < 0 then fade = 0 end
                    alpha = math_floor(255 * fade * intensity_boost)
                    if alpha > 255 then alpha = 255 end
                    if alpha < 5 then
                        s_faded[idx] = true
                        goto continue
                    end
                    size = p_size * (0.5 + fade * 0.5) * distance_scale
                else
                    alpha = math_floor(245 * intensity_boost)
                    if alpha > 255 then alpha = 255 end
                    size = p_size * distance_scale
                end
                local boosted_intensity = s_intensity[idx] * intensity_boost
                if boosted_intensity > 1 then boosted_intensity = 1 end
                local pr, pg, pb = r, g, b
                if is_rainbow then
                    local hue = (current_time * rainbow_speed + s_color_offset[idx] * 360) % 360
                    pr, pg, pb = hsv_to_rgb(hue, 1, 1)
                elseif is_gradient then
                    local t = dissolve_progress * INV_1_5
                    if t > 1 then t = 1 end
                    t = t + s_color_offset[idx] * 0.3
                    if t > 1 then t = t - 1 end
                    pr, pg, pb = lerp_color(r, g, b, r2, g2, b2, t)
                end
                if color_variation > 0 then
                    local hue_shift = (s_color_offset[idx] - 0.5) * 2 * color_variation
                    pr, pg, pb = shift_hue(pr, pg, pb, hue_shift)
                end
                visible_particles[#visible_particles + 1] = {
                    sx = sx, sy = sy,
                    dist = dist,
                    alpha = alpha,
                    size = size,
                    intensity = boosted_intensity,
                    r = pr, g = pg, b = pb,
                    is_line = s_is_line[idx],
                    line_angle = s_line_angle[idx],
                    line_length = s_line_length[idx],
                    vel_x = s_vel_x[idx],
                    vel_y = s_vel_y[idx],
                    vel_z = s_vel_z[idx]
                }
            end
            ::continue::
        end
        local sec_particles = system.secondary_particles
        for k = 1, #sec_particles do
            local sec = sec_particles[k]
            local sec_dx = sec.x - cam_x
            local sec_dy = sec.y - cam_y
            local sec_dz = sec.z - cam_z
            local sec_dot = sec_dx * fwd_x + sec_dy * fwd_y + sec_dz * fwd_z
            if sec_dot < -20 then goto next_secondary end
            local sec_screen = vector(sec.x, sec.y, sec.z):to_screen()
            if sec_screen then
                local sec_sx, sec_sy = sec_screen.x, sec_screen.y
                local sec_age = current_time - sec.spawn_time
                local sec_fade = 1 - (sec_age / sec.life)
                if sec_fade > 0 then
                    local sec_alpha = math_floor(200 * sec_fade)
                    local sec_dist = math_sqrt(sec_dx*sec_dx + sec_dy*sec_dy + sec_dz*sec_dz)
                    local sec_size = sec.size * 500 / (sec_dist > 1 and sec_dist or 1)
                    local sec_r, sec_g, sec_b = r, g, b
                    if sec.hue_offset ~= 0 then
                        sec_r, sec_g, sec_b = shift_hue(r, g, b, sec.hue_offset)
                    end
                    visible_particles[#visible_particles + 1] = {
                        sx = sec_sx, sy = sec_sy,
                        dist = sec_dist,
                        alpha = sec_alpha,
                        size = sec_size,
                        intensity = 0.8,
                        r = sec_r, g = sec_g, b = sec_b,
                        is_line = false,
                        is_secondary = true
                    }
                end
            end
            ::next_secondary::
        end
        ::next_system::
    end
    if #visible_particles > 1 then
        table.sort(visible_particles, function(a, b) return a.dist > b.dist end)
    end
    if use_connections and #visible_particles > 1 then
        local conn_dist_sq = connection_dist * connection_dist
        local num_visible = #visible_particles
        local max_particles_to_connect = 20
        local step = num_visible > max_particles_to_connect and math_floor(num_visible / max_particles_to_connect) or 1
        local sampled_indices = {}
        local sampled_count = 0
        for i = 1, num_visible, step do
            if sampled_count >= max_particles_to_connect then break end
            sampled_count = sampled_count + 1
            sampled_indices[sampled_count] = i
        end
        local cell_size = connection_dist
        local grid = {}
        for si = 1, sampled_count do
            local i = sampled_indices[si]
            local p = visible_particles[i]
            local cx = math_floor(p.sx / cell_size)
            local cy = math_floor(p.sy / cell_size)
            local key = cx * 10000 + cy
            if not grid[key] then grid[key] = {} end
            grid[key][#grid[key] + 1] = {idx = i, sample_idx = si}
        end
        for si = 1, sampled_count do
            local i = sampled_indices[si]
            local p1 = visible_particles[i]
            local cx = math_floor(p1.sx / cell_size)
            local cy = math_floor(p1.sy / cell_size)
            for ox = -1, 1 do
                for oy = -1, 1 do
                    local key = (cx + ox) * 10000 + (cy + oy)
                    local cell = grid[key]
                    if cell then
                        for k = 1, #cell do
                            local entry = cell[k]
                            if entry.sample_idx > si then
                                local p2 = visible_particles[entry.idx]
                                local dx = p2.sx - p1.sx
                                local dy = p2.sy - p1.sy
                                local dist_sq = dx * dx + dy * dy
                                if dist_sq < conn_dist_sq and dist_sq > 0 then
                                    local dist = math_sqrt(dist_sq)
                                    local dist_ratio = dist / connection_dist
                                    local fade = 1 - dist_ratio * dist_ratio * dist_ratio
                                    local alpha_factor = (p1.alpha + p2.alpha) / 510
                                    local conn_alpha = math_floor(fade * alpha_factor * 60)
                                    if conn_alpha > 2 then
                                        local avg_r = math_floor((p1.r + p2.r) * 0.5)
                                        local avg_g = math_floor((p1.g + p2.g) * 0.5)
                                        local avg_b = math_floor((p1.b + p2.b) * 0.5)
                                        local glow_alpha = math_floor(conn_alpha * 0.3)
                                        if glow_alpha > 1 then
                                            render.line(vector2d(p1.sx, p1.sy), vector2d(p2.sx, p2.sy), color(avg_r, avg_g, avg_b, glow_alpha))
                                        end
                                        local core_alpha = math_floor(conn_alpha * 0.8)
                                        if core_alpha > 1 then
                                            render.line(vector2d(p1.sx, p1.sy), vector2d(p2.sx, p2.sy), color(avg_r, avg_g, avg_b, core_alpha))
                                        end
                                        if glow_texture_id and fade > 0.5 then
                                            local node_alpha = math_floor(conn_alpha * 0.4)
                                            if node_alpha > 2 then
                                                local node_size = 4 + fade * 4
                                                local mid_x = (p1.sx + p2.sx) * 0.5
                                                local mid_y = (p1.sy + p2.sy) * 0.5
                                                render.image(glow_texture_id, vector2d(mid_x - node_size/2, mid_y - node_size/2), vector2d(node_size, node_size), color(avg_r, avg_g, avg_b, node_alpha))
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    for i = 1, #visible_particles do
        local p = visible_particles[i]
        if p.is_line then
            draw_ethereal_glow_line(p.sx, p.sy, p.alpha, p.size, p.intensity, p.r, p.g, p.b, glow_mult, p.line_angle, p.line_length)
        else
            draw_ethereal_glow_circle(p.sx, p.sy, p.alpha, p.size, p.intensity, p.r, p.g, p.b, glow_mult)
        end
    end
end
local function track_players()
    local players = entities.get_players()
    local dt = globals.get_frame_time()
    local inv_dt = dt > 0.001 and (1 / dt) or 0
    for i = 1, #players do
        local player = players[i]
        if player:is_alive() then
            local origin = player:get_origin()
            if origin then
                local x, y, z = origin.x, origin.y, origin.z
                local player_index = player:get_index()
                local prev = player_positions[player_index]
                if prev and prev.x then
                    local vel_x = (x - prev.x) * inv_dt
                    local vel_y = (y - prev.y) * inv_dt
                    local vel_z = (z - prev.z) * inv_dt
                    player_positions[player_index] = {x = x, y = y, z = z, vel_x = vel_x, vel_y = vel_y, vel_z = vel_z}
                else
                    player_positions[player_index] = {x = x, y = y, z = z, vel_x = 0, vel_y = 0, vel_z = 0}
                end
            end
        end
    end
end
local function on_player_death(event)
    if not ui_enabled:get() then return end
    local victim = event.userid
    local attacker = event.attacker
    local local_player = entities.get_local_player()
    if not victim then return end
    if not local_player then return end
    if ui_enemies_only:get() then
        if not victim:is_enemy() and victim ~= local_player then
            return
        end
    end
    local victim_index = victim:get_index()
    local last_pos = player_positions[victim_index]
    if last_pos then
        create_death_particles(
            last_pos.x, last_pos.y, last_pos.z, victim,
            last_pos.vel_x or 0, last_pos.vel_y or 0, last_pos.vel_z or 0
        )
        if ui_kill_trail:get() and attacker then
            if attacker == local_player and victim ~= local_player then
                create_kill_trail(last_pos.x, last_pos.y, last_pos.z + 40)
            end
        end
        if ui_show_notification:get() then
            local player_name = victim:get_name()
            local main_col = ui_color:get()
            utils.console_print(color(main_col.r, main_col.g, main_col.b, 255), "[Particles] ", player_name, " dissolved!")
        end
    end
    player_positions[victim_index] = nil
end
local function on_render()
    track_players()
    local current_time = globals.get_real_time()
    local dt = globals.get_frame_time()
    update_kill_trails(dt, current_time)
    render_kill_trails()
    update_self_particles(dt, current_time)
    render_self_particles()
    update_fireflies(dt, current_time)
    render_fireflies()
    render_particles()
end
events.add("player_death", on_player_death)
callbacks.add("render", on_render)
local status_parts = {}
if ffi_ok then
    status_parts[#status_parts + 1] = "FFI"
end
if textures_loaded then
    status_parts[#status_parts + 1] = "Textures"
end
if #status_parts > 0 then
    utils.console_print(color(100, 255, 100, 255), "[Particles] Successfully loaded! (" .. table.concat(status_parts, " + ") .. " enabled)")
else
    utils.console_print(color(200, 220, 255, 255), "[Particles] Successfully loaded!")
end
