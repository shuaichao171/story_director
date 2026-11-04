-- 剧情导演：把场景时间线翻译成演员动画、运镜、台词和画面效果。
-- 只在主机（ismastersim 且有 ThePlayer）上运行，所有演员都是本地非网络实体。

local Widget = require "widgets/widget"
local Image = require "widgets/image"
local Text = require "widgets/text"
local player_ex = require "prefabs/player_common_extensions"

local SIGNAL_FILE = "story_director_signal"
local LOG_TAG = "[STORY_DIRECTOR]"

-- 清场时不碰的实体
local CLEAR_CANT_TAGS = { "player", "INLIMBO", "CLASSIFIED" }
-- 清场时删不得的实体（传送门、唯一物品、特效、地图图标等）：拍摄期间藏起来，收工再显示
local CLEAR_HIDE_TAGS = { "multiplayer_portal", "irreplaceable", "NOCLICK", "FX" }

local Director = Class(function(self, scene)
    self.scene = scene
    self.actors = {}
    self.props = {}
    self.named = {}
    self.tile_undo = {}
    self.hidden = {}
    self.tasks = {}
    self.root = CreateEntity()
    self.root.entity:AddTransform()
    self.root.persists = false
end)

--------------------------------------------------------------------------
-- 信号：录制脚本轮询 client_save 下的这个文件来开始/停止录像

function Director:Signal(state)
    print(LOG_TAG, state, self.scene.name)
    TheSim:SetPersistentString(SIGNAL_FILE, state.." "..tostring(self.scene.name).." "..tostring(os.time()), false)
end

--------------------------------------------------------------------------
-- 舞台坐标：dx 沿屏幕向右，dz 沿屏幕向下（朝镜头），以舞台中心为原点

function Director:Pos(dx, dz)
    return Vector3(
        self.center.x + self.right.x * dx + self.down.x * dz,
        0,
        self.center.z + self.right.z * dx + self.down.z * dz)
end

-- 圆内全是陆地：按三圈、每圈 16 个方向抽查
local function IsAreaLand(map, x, z, radius)
    if not map:IsPassableAtPoint(x, 0, z) then
        return false
    end
    for _, k in ipairs({ 1, 0.66, 0.33 }) do
        for a = 0, 337.5, 22.5 do
            local r = a * DEGREES
            if not map:IsPassableAtPoint(x + math.cos(r) * radius * k, 0, z + math.sin(r) * radius * k) then
                return false
            end
        end
    end
    return true
end

-- 在玩家附近找一块半径 radius 全是陆地、且不含出生传送门的空地当布景区
function Director:FindStage(radius)
    local px, _, pz = ThePlayer.Transform:GetWorldPosition()
    local map = TheWorld.Map
    local portals = TheSim:FindEntities(px, 0, pz, 400, { "multiplayer_portal" })
    local function FarFromPortals(x, z)
        for _, portal in ipairs(portals) do
            if portal:GetDistanceSqToPoint(x, 0, z) < radius * radius then
                return false
            end
        end
        return true
    end
    local fallback = nil
    for dist = 8, 160, 6 do
        for a = 0, 340, 20 do
            local r = a * DEGREES
            local x, z = px + math.cos(r) * dist, pz + math.sin(r) * dist
            if IsAreaLand(map, x, z, radius) then
                if FarFromPortals(x, z) then
                    return Vector3(x, 0, z)
                end
                fallback = fallback or Vector3(x, 0, z)
            end
        end
    end
    print(LOG_TAG, "找不到足够大的空地，布景区边缘可能露出原地图")
    return fallback or Vector3(px, 0, pz)
end

-- 清掉圆内除演员外的所有实体：普通物件删除，删不得的藏起来（收工时 ShowHidden 还原）
function Director:ClearArea(c, radius)
    for _, ent in ipairs(TheSim:FindEntities(c.x, 0, c.z, radius, nil, CLEAR_CANT_TAGS)) do
        if ent:IsValid() and ent ~= TheWorld and ent ~= TheWorld.net and ent ~= self.root
            and ent.entity:GetParent() == nil and not self:IsCast(ent) then
            if ent:HasOneOfTags(CLEAR_HIDE_TAGS) then
                if ent.entity:IsVisible() then
                    ent:Hide()
                    table.insert(self.hidden, ent)
                end
            else
                ent:Remove()
            end
        end
    end
end

function Director:ShowHidden()
    for _, ent in ipairs(self.hidden) do
        if ent:IsValid() then
            ent:Show()
        end
    end
    self.hidden = {}
end

--------------------------------------------------------------------------
-- 演员：用角色本体 build 做的木偶，不受 SG、AI 和输入影响

function Director:Spawn(name, build, dx, dz)
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddDynamicShadow()
    inst.persists = false
    inst:AddTag("NOCLICK")

    inst.Transform:SetFourFaced()
    inst.AnimState:SetBank("wilson")
    inst.AnimState:SetBuild(build)
    player_ex.SetupBaseSymbolVisibility(inst)
    player_ex.SetupOverrideSymbols(inst)
    player_ex.SetupOverrideBuilds(inst)
    inst.AnimState:PlayAnimation("idle_loop", true)
    inst.DynamicShadow:SetSize(1.3, .6)

    inst:AddComponent("talker")
    inst.components.talker.fontsize = 35
    inst.components.talker.font = TALKINGFONT
    inst.components.talker.offset = Vector3(0, -400, 0)

    inst.actor_build = build
    inst.Transform:SetPosition(self:Pos(dx, dz):Get())
    self.actors[name] = inst
    return inst
end

function Director:Actor(name)
    return self.actors[name]
end

-- 演员平时的待机动画：默认 idle_loop；Idle(名字, { "idle_shiver_pre", "idle_shiver_loop" }) 改成冻得发抖
local function PlayIdle(inst)
    local idle = inst.idle_anims or { "idle_loop" }
    inst.AnimState:PlayAnimation(idle[1], #idle == 1)
    for i = 2, #idle do
        inst.AnimState:PushAnimation(idle[i], i == #idle)
    end
end

function Director:Idle(name, anims)
    local inst = self.actors[name]
    inst.idle_anims = anims
    if not inst.walking then
        PlayIdle(inst)
    end
end

-- 只有动画的木偶（如阿比盖尔：bank "ghost"，build "ghost_abigail_build"，动画 "idle"）
function Director:Puppet(name, bank, build, anim, dx, dz)
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.persists = false
    inst:AddTag("NOCLICK")
    inst.AnimState:SetBank(bank)
    inst.AnimState:SetBuild(build)
    inst.AnimState:PlayAnimation(anim, true)
    inst.Transform:SetPosition(self:Pos(dx, dz):Get())
    self.actors[name] = inst
    return inst
end

-- 演员下场（直接从画面上消失）
function Director:Exit(name)
    local inst = self.actors[name]
    if inst ~= nil then
        inst:Remove()
        self.actors[name] = nil
    end
end

function Director:Face(name, target, dz)
    local inst = self.actors[name]
    local pt = type(target) == "string" and self.actors[target]:GetPosition() or self:Pos(target, dz)
    inst:FacePoint(pt.x, 0, pt.z)
end

-- anim 可以是一串动画，如 { "eat_pre", "eat" }；不循环时播完回到待机动画
function Director:Anim(name, anim, loop)
    local inst = self.actors[name]
    local anims = type(anim) == "table" and anim or { anim }
    inst.AnimState:PlayAnimation(anims[1], loop and #anims == 1)
    for i = 2, #anims do
        inst.AnimState:PushAnimation(anims[i], loop and i == #anims)
    end
    if not loop then
        local idle = inst.idle_anims or { "idle_loop" }
        for i, a in ipairs(idle) do
            inst.AnimState:PushAnimation(a, i == #idle)
        end
    end
end

function Director:Say(name, text, duration)
    local inst = self.actors[name]
    inst.components.talker:Say(text, duration, true, true, true)
    inst.AnimState:PlayAnimation("dial_loop", true)
    inst.SoundEmitter:KillSound("talk")
    inst.SoundEmitter:PlaySound("dontstarve/characters/"..inst.actor_build.."/talk_LP", "talk")
    self:After(duration, function()
        if not inst:IsValid() then
            return
        end
        inst.SoundEmitter:KillSound("talk")
        if not inst.walking then
            PlayIdle(inst)
        end
    end)
end

function Director:Walk(name, dx, dz, speed)
    local inst = self.actors[name]
    local dest = self:Pos(dx, dz)
    speed = speed or TUNING.WILSON_RUN_SPEED
    inst:FacePoint(dest.x, 0, dest.z)
    inst.walking = true
    inst.AnimState:PlayAnimation("run_pre")
    inst.AnimState:PushAnimation("run_loop", true)
    if inst.walktask ~= nil then
        inst.walktask:Cancel()
    end
    inst.walktask = inst:DoPeriodicTask(0, function()
        local pos = inst:GetPosition()
        local delta = dest - pos
        local step = speed * FRAMES
        if delta:Length() <= step then
            inst.Transform:SetPosition(dest:Get())
            inst.walktask:Cancel()
            inst.walktask = nil
            inst.walking = false
            inst.AnimState:PlayAnimation("run_pst")
            local idle = inst.idle_anims or { "idle_loop" }
            for i, a in ipairs(idle) do
                inst.AnimState:PushAnimation(a, i == #idle)
            end
            inst.SoundEmitter:PlaySound("dontstarve/movement/run_grass")
        else
            inst.Transform:SetPosition((pos + delta:GetNormalized() * step):Get())
        end
    end)
end

--------------------------------------------------------------------------
-- 生物演员：用游戏里的真实生物（带原版动画和音效），关掉 AI、索敌、睡眠和伤害，由剧本指挥

function Director:Creature(name, prefab, dx, dz)
    local inst = SpawnPrefab(prefab)
    inst.Transform:SetPosition(self:Pos(dx, dz):Get())
    inst.persists = false
    inst:StopBrain("story_director")
    if inst.components.combat ~= nil then
        inst.components.combat:SetRetargetFunction(nil)
        inst.components.combat:SetTarget(nil)
    end
    if inst.components.health ~= nil then
        inst.components.health:SetInvincible(true)
    end
    if inst.components.sleeper ~= nil then
        inst.components.sleeper:SetSleepTest(function() return false end)
        inst.components.sleeper:SetWakeTest(function() return true end)
    end
    if inst.components.lootdropper ~= nil then
        inst.components.lootdropper:SetLoot(nil)
        inst.components.lootdropper:SetChanceLootTable(nil)
    end
    self.actors[name] = inst
    return inst
end

-- 生物走位：run=false 时用走路速度
function Director:Move(name, dx, dz, run)
    self.actors[name].components.locomotor:GoToPoint(self:Pos(dx, dz), nil, run ~= false)
end

-- 让生物进入状态机状态，如猎犬的 "taunt"、"howl"（data = { count = -1 }）、"attack"、"startle"、"hit"
function Director:State(name, state, data)
    self.actors[name].sg:GoToState(state, data)
end

-- 在镜头位置播放音效（不跟随演员），如远处猎犬嚎叫 "dontstarve/creatures/hound/distant"
function Director:Sound(path)
    self.dolly.SoundEmitter:PlaySound(path)
end

-- 在舞台点放一丛草并点燃，烧 duration 秒后消失（不向周围蔓延，不留灰烬）
function Director:Burn(dx, dz, duration)
    local inst = self:Prop("grass", dx, dz)
    local burnable = inst.components.burnable
    if inst.components.propagator ~= nil then
        inst.components.propagator.propagaterange = 0
    end
    burnable:SetBurnTime(duration or 10)
    burnable:SetOnBurntFn(function(i) i:Remove() end)
    burnable:Ignite(true)
    return inst
end

-- name 可省略；起了名字的道具可以用 Ignite(名字) 点燃
function Director:Prop(prefab, dx, dz, name)
    local inst = SpawnPrefab(prefab)
    if inst ~= nil then
        inst.Transform:SetPosition(self:Pos(dx, dz):Get())
        table.insert(self.props, inst)
        if name ~= nil then
            self.named[name] = inst
        end
    end
    return inst
end

-- 点燃起了名字的道具，烧 duration 秒后变成烧毁的样子（建筑留下焦黑残骸），火不蔓延；不可燃的道具忽略
function Director:Ignite(name, duration)
    local inst = self.named[name]
    local burnable = inst ~= nil and inst:IsValid() and inst.components.burnable or nil
    if burnable == nil then
        return
    end
    if duration ~= nil then
        burnable:SetBurnTime(duration)
    end
    -- 只烧点名的道具，不引燃旁边的树和草
    if inst.components.propagator ~= nil then
        inst.components.propagator.propagaterange = 0
    end
    burnable:Ignite(true)
end

-- 在舞台点周围 radius 内随机散布 count 个物件（树、花、石头等布景），seed 固定则每次拍摄位置相同
function Director:Scatter(prefab, dx, dz, radius, count, seed)
    local rng_state = seed or 1
    local function rand()
        -- 线性同余，避免影响全局 math.random
        rng_state = (rng_state * 1103515245 + 12345) % 2147483648
        return rng_state / 2147483648
    end
    for _ = 1, count do
        local a = rand() * 2 * PI
        local r = math.sqrt(rand()) * radius
        self:Prop(prefab, dx + math.cos(a) * r, dz + math.sin(a) * r)
    end
end

--------------------------------------------------------------------------
-- 地形：按舞台坐标改地皮（tile 用 WORLD_TILES 的名字，如 "GRASS"、"FOREST"、"ROAD"、"OCEAN_COASTAL"）

local function TileId(name)
    local tile = WORLD_TILES[string.upper(name)]
    assert(tile ~= nil, "未知地皮："..tostring(name))
    return tile
end

-- 改地皮并记下原样，收工时 RestoreSet 还原
function Director:PaintTile(map, pt, tile)
    local tx, ty = map:GetTileCoordsAtPoint(pt.x, 0, pt.z)
    local old = map:GetTile(tx, ty)
    if old ~= tile then
        local key = tx..","..ty
        if self.tile_undo[key] == nil then
            self.tile_undo[key] = { tx, ty, old }
        end
        map:SetTile(tx, ty, tile)
    end
end

-- 以舞台点为圆心，半径 radius（单位：游戏距离，一格地皮 = 4）内铺地皮
function Director:Turf(tile, dx, dz, radius)
    local map = TheWorld.Map
    local id = TileId(tile)
    local c = self:Pos(dx, dz)
    for x = -radius, radius, TILE_SCALE do
        for z = -radius, radius, TILE_SCALE do
            if x * x + z * z <= radius * radius then
                self:PaintTile(map, Vector3(c.x + x, 0, c.z + z), id)
            end
        end
    end
end

-- 从舞台点 (x1,z1) 到 (x2,z2) 铺一条宽 width 的带子（道路、小河）
function Director:TurfLine(tile, x1, z1, x2, z2, width)
    local map = TheWorld.Map
    local id = TileId(tile)
    local a, b = self:Pos(x1, z1), self:Pos(x2, z2)
    local len = (b - a):Length()
    local steps = math.max(1, math.ceil(len / (TILE_SCALE / 2)))
    local half = (width or TILE_SCALE) / 2
    for i = 0, steps do
        local p = a + (b - a) * (i / steps)
        for x = -half, half, TILE_SCALE / 2 do
            for z = -half, half, TILE_SCALE / 2 do
                self:PaintTile(map, Vector3(p.x + x, 0, p.z + z), id)
            end
        end
    end
end

-- 清掉舞台点周围的物件（不动玩家和演员；传送门、特效等藏起来）
function Director:Clear(dx, dz, radius)
    self:ClearArea(self:Pos(dx, dz), radius)
end

function Director:IsCast(ent)
    for _, actor in pairs(self.actors) do
        if actor == ent then
            return true
        end
    end
    return ent == self.dolly
end

--------------------------------------------------------------------------
-- 时间、季节、天气：直接改世界状态，只在主机生效

-- phase: "day" / "dusk" / "night"
function Director:Phase(phase)
    TheWorld:PushEvent("ms_setphase", phase)
end

-- 一天的时段分配，三项加起来必须是 16，如 { day = 16, dusk = 0, night = 0 } 让白天不结束
-- 拍完不自动恢复：季节切换时游戏会按季节重新下发时段
function Director:ClockSegs(segs)
    TheWorld:PushEvent("ms_setclocksegs", segs)
end

-- moon: "new" / "quarter" / "half" / "threequarter" / "full"
function Director:Moon(moon)
    TheWorld:PushEvent("ms_setmoonphase", { moonphase = moon, iswaxing = true })
end

-- season: "autumn" / "winter" / "spring" / "summer"
function Director:Season(season)
    TheWorld:PushEvent("ms_setseason", season)
end

-- 下雨/下雪：冬天或气温低于 0 时自动变成雪；on=false 停止并禁止再下
function Director:Precipitation(on)
    TheWorld:PushEvent("ms_setprecipitationmode", on and "always" or "never")
    TheWorld:PushEvent("ms_forceprecipitation", on)
    self.changed_precipitation = true
end

-- 固定世界气温（摄氏度）；冬天刚开始时气温在临界值附近，要稳定下雪就设到 0 以下。传 nil 恢复
function Director:Temperature(degrees)
    local wt = TheWorld.net ~= nil and TheWorld.net.components.worldtemperature or nil
    if wt == nil then
        return
    end
    if degrees ~= nil then
        wt:SetTemperatureMod(0, degrees)
        self.changed_temperature = true
    else
        wt:SetTemperatureMod(1, 0)
    end
end

-- 地面积雪 0~1
function Director:SnowLevel(level)
    TheWorld:PushEvent("ms_setsnowlevel", level)
end

-- 在舞台点劈一道闪电
function Director:Lightning(dx, dz)
    TheWorld:PushEvent("ms_sendlightningstrike", self:Pos(dx, dz))
end

-- 时间流速：<1 慢动作，>1 快进；时间线的秒数也按游戏时间走
function Director:TimeScale(scale)
    TheSim:SetTimeScale(scale)
    self.changed_timescale = true
end

-- 一次性设定环境，场景的 env 字段在搭台（黑场）时调用
function Director:Env(env)
    if env.season ~= nil then self:Season(env.season) end
    if env.clocksegs ~= nil then self:ClockSegs(env.clocksegs) end
    if env.phase ~= nil then self:Phase(env.phase) end
    if env.moon ~= nil then self:Moon(env.moon) end
    if env.temperature ~= nil then self:Temperature(env.temperature) end
    if env.precipitation ~= nil then self:Precipitation(env.precipitation) end
    if env.snowlevel ~= nil then self:SnowLevel(env.snowlevel) end
end

-- 收工：删掉场景生成的道具、还原改过的地皮（场景 keep_set = true 时保留布景）
function Director:RestoreSet()
    if self.scene.keep_set then
        return
    end
    for _, inst in ipairs(self.props) do
        if inst:IsValid() then
            inst:Remove()
        end
    end
    self.props = {}
    local map = TheWorld.Map
    for _, undo in pairs(self.tile_undo) do
        map:SetTile(undo[1], undo[2], undo[3])
    end
    self.tile_undo = {}
end

function Director:RestoreEnv()
    if self.changed_timescale then
        TheSim:SetTimeScale(1)
    end
    if self.changed_precipitation then
        TheWorld:PushEvent("ms_setprecipitationmode", "dynamic")
    end
    if self.changed_temperature then
        self:Temperature(nil)
    end
end

--------------------------------------------------------------------------
-- 镜头：相机跟随一个隐形推车实体，推车位置、距离和朝向都按缓动插值

local function smoothstep(t)
    return t * t * (3 - 2 * t)
end

function Director:Camera(dx, dz, distance, heading_offset, duration)
    local from_pos = self.dolly:GetPosition()
    local to_pos = self:Pos(dx, dz)
    local from_dist = TheCamera:GetDistance()
    local to_dist = distance or from_dist
    local from_heading = TheCamera:GetHeadingTarget()
    local to_heading = self.base_heading + (heading_offset or 0)
    -- 走最短的角度差
    local dh = (to_heading - from_heading + 180) % 360 - 180

    if self.cameratask ~= nil then
        self.cameratask:Cancel()
        self.cameratask = nil
    end
    if duration == nil or duration <= 0 then
        self.dolly.Transform:SetPosition(to_pos:Get())
        TheCamera:SetDistance(to_dist)
        TheCamera:SetHeadingTarget(from_heading + dh)
        TheCamera:Snap()
        return
    end

    local t0 = GetTime()
    self.cameratask = self.root:DoPeriodicTask(0, function()
        local t = math.min((GetTime() - t0) / duration, 1)
        local k = smoothstep(t)
        self.dolly.Transform:SetPosition((from_pos + (to_pos - from_pos) * k):Get())
        TheCamera:SetDistance(from_dist + (to_dist - from_dist) * k)
        TheCamera:SetHeadingTarget(from_heading + dh * k)
        if t >= 1 then
            self.cameratask:Cancel()
            self.cameratask = nil
        end
    end)
end

--------------------------------------------------------------------------
-- 画面：黑边、标题、淡入淡出

function Director:BuildUI()
    local ui = ThePlayer.HUD:AddChild(Widget("story_director_ui"))
    ui:SetHAnchor(ANCHOR_MIDDLE)
    ui:SetVAnchor(ANCHOR_MIDDLE)
    ui:SetScaleMode(SCALEMODE_PROPORTIONAL)
    ui:MoveToBack()

    -- 导演自己的黑幕：在黑边和标题之下，所以黑场上也能显示标题
    self.blackout = ui:AddChild(Image("images/global.xml", "square.tex"))
    self.blackout:SetSize(RESOLUTION_X * 3, RESOLUTION_Y * 3)
    self.blackout:SetTint(0, 0, 0, 1)
    self.blackout_alpha = 1

    local bar_h = 90
    for _, sign in ipairs({ 1, -1 }) do
        local bar = ui:AddChild(Image("images/global.xml", "square.tex"))
        bar:SetTint(0, 0, 0, 1)
        bar:SetSize(RESOLUTION_X * 3, bar_h * 2)
        bar:SetPosition(0, sign * RESOLUTION_Y / 2)
    end

    self.title = ui:AddChild(Text(TITLEFONT, 90, ""))
    self.title:SetPosition(0, 40)
    self.subtitle = ui:AddChild(Text(UIFONT, 36, ""))
    self.subtitle:SetPosition(0, -30)
    self.subtitle:SetColour(0.85, 0.8, 0.7, 1)
    self.ui = ui
end

function Director:Title(title, subtitle, duration)
    self.title:SetString(title or "")
    self.subtitle:SetString(subtitle or "")
    self.title:Show()
    self.subtitle:Show()
    self:After(duration, function()
        self.title:Hide()
        self.subtitle:Hide()
    end)
end

function Director:Fade(fadein, duration)
    local from = self.blackout_alpha
    local to = fadein and 0 or 1
    if self.fadetask ~= nil then
        self.fadetask:Cancel()
    end
    local t0 = GetTime()
    self.fadetask = self.root:DoPeriodicTask(0, function()
        local t = math.min((GetTime() - t0) / duration, 1)
        self.blackout_alpha = from + (to - from) * t
        self.blackout:SetTint(0, 0, 0, self.blackout_alpha)
        if t >= 1 then
            self.fadetask:Cancel()
            self.fadetask = nil
        end
    end)
end

--------------------------------------------------------------------------
-- 生命周期

function Director:After(t, fn)
    local task = self.root:DoTaskInTime(t, function()
        if self.running then
            fn(self)
        end
    end)
    table.insert(self.tasks, task)
    return task
end

function Director:Setup()
    local scene = self.scene
    self.base_heading = TheCamera:GetHeadingTarget()
    self.right = TheCamera:GetRightVec()
    self.down = TheCamera:GetDownVec()
    -- 布景区：镜头能拍到的整片地方。区内原有物件清空，铺上底层地皮，画面里只剩剧本布置的东西
    self.set_radius = scene.set_radius or scene.stage_radius or 5
    self.center = self:FindStage(self.set_radius)
    if scene.clear_stage ~= false then
        self:ClearArea(self.center, self.set_radius)
    end
    if scene.ground ~= nil then
        self:Turf(scene.ground, 0, 0, self.set_radius)
    end

    -- 收起玩家：隐身、无敌、不接受输入
    local player = ThePlayer
    self.saved_player = { pos = player:GetPosition() }
    player:Hide()
    player.DynamicShadow:Enable(false)
    if player.components.health ~= nil then
        player.components.health:SetInvincible(true)
    end
    if player.components.playercontroller ~= nil then
        player.components.playercontroller:Enable(false)
    end
    -- 夜戏和冬戏时别让查理攻击、冻僵的音效混进录音
    if player.components.grue ~= nil then
        player.components.grue:AddImmunity("story_director")
    end
    if player.components.temperature ~= nil then
        player.components.temperature:SetTemp(TUNING.STARTING_TEMP)
    end
    player.HUD.controls:Hide()
    -- 把隐身的玩家挪进布景区后方：附近实体才不会休眠，天气特效（挂在玩家身上）也跟着到场
    local spot = self:Pos(0, -self.set_radius * 0.6)
    if player.Physics ~= nil then
        player.Physics:Teleport(spot:Get())
    else
        player.Transform:SetPosition(spot:Get())
    end

    self.dolly = CreateEntity()
    self.dolly.entity:AddTransform()
    self.dolly.entity:AddSoundEmitter()
    self.dolly.persists = false
    self.dolly.Transform:SetPosition(self.center:Get())
    TheCamera:SetControllable(false)
    TheCamera:SetMinDistance(scene.camera_min_distance or 6)
    TheCamera:SetGains(4, 20, 8)
    TheCamera:SetTarget(self.dolly)

    self:BuildUI()

    if scene.env ~= nil then
        self:Env(scene.env)
    end
end

function Director:Restore()
    local player = ThePlayer
    if player ~= nil and player:IsValid() then
        if self.saved_player ~= nil then
            local pos = self.saved_player.pos
            if player.Physics ~= nil then
                player.Physics:Teleport(pos:Get())
            else
                player.Transform:SetPosition(pos:Get())
            end
        end
        player:Show()
        player.DynamicShadow:Enable(true)
        if player.components.health ~= nil then
            player.components.health:SetInvincible(false)
        end
        if player.components.playercontroller ~= nil then
            player.components.playercontroller:Enable(true)
        end
        if player.components.grue ~= nil then
            player.components.grue:RemoveImmunity("story_director")
        end
        if player.components.temperature ~= nil then
            player.components.temperature:SetTemp(nil)
        end
        if player.HUD ~= nil then
            player.HUD.controls:Show()
        end
        TheCamera:SetDefault()
        TheCamera:SetControllable(true)
        TheCamera:SetTarget(player)
        TheCamera:Snap()
    end
    if self.ui ~= nil then
        self.ui:Kill()
        self.ui = nil
    end
    for _, inst in pairs(self.actors) do
        if inst:IsValid() then
            inst:Remove()
        end
    end
    self.actors = {}
    if self.dolly ~= nil then
        self.dolly:Remove()
        self.dolly = nil
    end
end

function Director:Play(onfinished)
    self.running = true
    -- 先用游戏黑幕盖住画面搭台，搭好后换成导演黑幕，录像从黑场开始
    TheFrontEnd:Fade(FADE_OUT, 0.3)
    self.root:DoTaskInTime(0.4, function()
        self:Setup()
        TheFrontEnd:Fade(FADE_IN, 0.01)
        self:Signal("START")
        local length = 0
        for _, cue in ipairs(self.scene.cues) do
            self:After(cue.t, cue.fn)
            length = math.max(length, cue.t)
        end
        self:After(self.scene.length or (length + 1), function()
            self:Signal("STOP")
            self:Stop()
            -- Fade(FADE_IN) 会先把游戏黑幕置满，和导演黑幕的移除在同一帧，不会闪
            TheFrontEnd:Fade(FADE_IN, 1)
            if onfinished ~= nil then
                onfinished()
            end
        end)
    end)
end

function Director:Stop()
    for _, task in ipairs(self.tasks) do
        task:Cancel()
    end
    self.tasks = {}
    if self.cameratask ~= nil then
        self.cameratask:Cancel()
        self.cameratask = nil
    end
    if self.fadetask ~= nil then
        self.fadetask:Cancel()
        self.fadetask = nil
    end
    self.running = false
    self:RestoreEnv()
    self:RestoreSet()
    self:ShowHidden()
    self:Restore()
    self.root:Remove()
end

return Director
