-- 搞笑短剧《基地会议》（四幕，约 3 分钟）
-- 冬天将至、食物告急，威尔逊召集沃尔夫冈、薇洛、温蒂、WX-78 开会，结果一路被队友坑。
-- 时间线按台词顺序自动排：say() 按字数算出台词时长并往后推进时钟，wait() 留白。
-- 坐标为舞台坐标：x 向屏幕右，z 向屏幕下（朝镜头）。

local HOUND_DISTANT = "dontstarve/creatures/hound/distant"
local HOUND_BARK = "dontstarve/creatures/hound/bark"

-- 站位：威尔逊站在科学机器旁，其余四人围着火坑
local P = {
    wilson = { 0, -1.6 },
    wolfgang = { -3.8, 0.4 },
    willow = { -2.4, 2.6 },
    wendy = { 2.4, 2.6 },
    wx78 = { 3.8, 0.4 },
}
local CREW = { "wolfgang", "willow", "wendy", "wx78" }
-- 下场/登场的画外位置
local OFF = {
    wolfgang = { -19, 1 },
    willow = { -18, 6 },
    wendy = { 18, 6 },
    wx78 = { 19, 0 },
}
local FIRE = { 0, 0.6 }
local TOUCHSTONE = { -9.5, 0.5 }
local BASE = { "lab", "chest1", "chest2", "tent" }

local cues, T = {}, 0

local function at(fn)
    table.insert(cues, { t = T, fn = fn })
end

local function wait(s)
    T = T + s
end

local function charcount(text)
    local _, n = string.gsub(text, "[^\128-\191]", "")
    return n
end

-- 台词时长：每字 0.2 秒 + 1 秒，至少 1.8 秒
local function say(who, text, extra)
    local d = math.max(1.8, charcount(text) * 0.2 + 1)
    at(function(D)
        D:Say(who, text, d)
        if extra ~= nil then
            extra(D)
        end
    end)
    wait(d + 0.35)
end

local function say_all(text)
    local d = math.max(1.8, charcount(text) * 0.2 + 1)
    at(function(D)
        for _, who in ipairs(CREW) do
            D:Say(who, text, d)
        end
    end)
    wait(d + 0.35)
end

local function cam(x, z, dist, dur)
    at(function(D) D:Camera(x, z, dist, 0, dur or 0.8) end)
end

-- 两人对话镜头：取两人站位中点
local function cam2(a, b, dist)
    cam((P[a][1] + P[b][1]) / 2, (P[a][2] + P[b][2]) / 2, dist or 12)
end

local function anim(who, a)
    at(function(D) D:Anim(who, a) end)
end

-- 幕间字卡：淡出 → 黑场标题（同时在黑场里换景）→ 淡入
local function card(title, subtitle, setup)
    at(function(D) D:Fade(false, 0.6) end)
    wait(0.7)
    at(function(D)
        D:Title(title, subtitle, 2.2)
        if setup ~= nil then
            setup(D)
        end
    end)
    wait(2.4)
    at(function(D) D:Fade(true, 0.8) end)
    wait(0.9)
end

local function face_all(x, z)
    at(function(D)
        D:Face("wilson", x, z)
        for _, who in ipairs(CREW) do
            if D:Actor(who) ~= nil then
                D:Face(who, x, z)
            end
        end
    end)
end

--------------------------------------------------------------------------
-- 布景（黑场中）

at(function(D)
    D:TurfLine("FOREST", -30, -16, 30, -16, 12)
    D:Turf("DIRT", 0, -0.5, 7)
    D:Scatter("evergreen", -13, -18, 7, 12, 7)
    D:Scatter("evergreen", 9, -18, 7, 12, 9)
    D:Scatter("evergreen_sparse", 15, -7, 3, 2, 5)
    D:Scatter("berrybush", 10, 5, 2.5, 3, 41)
    D:Scatter("grass", -15, 5, 3, 4, 13)
    D:Scatter("flower", -6, 8, 4, 4, 21)
    D:Prop("rock1", 14, 0)
    D:Prop("rock2", -16, -6)

    D:Prop("firepit", FIRE[1], FIRE[2])
    D:Prop("researchlab", -1.9, -3.4, "lab")
    D:Prop("icebox", 2.2, -3.6)
    D:Prop("treasurechest", -4.8, -3.0, "chest1")
    D:Prop("treasurechest", -6.0, -2.0, "chest2")
    D:Prop("tent", 6.6, -3.0, "tent")
    D:Prop("resurrectionstone", TOUCHSTONE[1], TOUCHSTONE[2])

    D:Spawn("wilson", "wilson", P.wilson[1], P.wilson[2])
    for _, who in ipairs(CREW) do
        D:Spawn(who, who, P[who][1], P[who][2])
        D:Face(who, FIRE[1], FIRE[2])
    end
    D:Face("wilson", 0, 5)
    D:Camera(0, -0.5, 15, 0)
end)

--------------------------------------------------------------------------
-- 第一幕：紧急会议

wait(0.5)
at(function(D) D:Title("第一幕", "紧急会议", 2.4) end)
wait(2.7)
at(function(D) D:Fade(true, 1.2) end)
wait(1.4)

cam(0, -1, 11, 1.5)
say("wilson", "各位，情况非常严峻！我们的食物只够吃三天了！")
cam2("wilson", "wolfgang")
say("wolfgang", "什么？！三天？！我一顿就能吃掉三天的食物！")
anim("wolfgang", "emoteXL_angry")
wait(0.6)
cam2("wilson", "willow")
say("willow", "要不我们把森林烧了吧？这样就不用担心冬天了。")
anim("willow", "emoteXL_happycheer")
wait(0.4)
cam(0, 2.6, 12)
at(function(D) D:Face("wendy", P.willow[1], P.willow[2]) end)
say("wendy", "我觉得可以先把你烧了。")
cam2("wilson", "wx78")
say("wx78", "可笑。低等生物为什么需要进食？食物是低效率的能源。")
at(function(D) D:Face("wilson", P.wx78[1], P.wx78[2]) end)
say("wilson", "那你把齿轮交出来，我们就有食物了。")
wait(0.6)
say("wx78", "……会议结束。")
at(function(D) D:Face("wx78", 10, -2) end)
wait(1.2)

--------------------------------------------------------------------------
-- 第二幕：分配任务

card("第二幕", "分配任务", function(D)
    D:Face("wilson", 0, 5)
    D:Face("wx78", FIRE[1], FIRE[2])
    D:Camera(0, 0, 14, 0)
end)

say("wilson", "好，现在分配任务。")
say("wilson", "沃尔夫冈负责打猎。")
anim("wolfgang", "emote_strikepose")
say("wilson", "薇洛负责采集木材。")
anim("willow", "emoteXL_happycheer")
say("wilson", "温蒂负责采集浆果。")
anim("wendy", "emoteXL_sad")
say("wilson", "WX-78负责科技研发。")
anim("wx78", "emoteXL_annoyed")
say("wilson", "我负责统筹全局。")
anim("wilson", "emote_strikepose")
wait(0.8)

-- 四人一哄而散，然后马上一个个回来交差
at(function(D)
    for _, who in ipairs(CREW) do
        D:Walk(who, OFF[who][1], OFF[who][2], 8)
    end
end)
wait(2.4)
at(function(D) D:Walk("wolfgang", P.wolfgang[1], P.wolfgang[2], 8) end)
wait(2)
at(function(D) D:Face("wolfgang", "wilson") end)
cam2("wilson", "wolfgang")
say("wolfgang", "我完成了！")
at(function(D) D:Face("wilson", P.wolfgang[1], P.wolfgang[2]) end)
say("wilson", "这么快？猎物呢？")
say("wolfgang", "已经吃掉了。")
anim("wolfgang", { "eat_pre", "eat" })
wait(1.2)

at(function(D) D:Walk("willow", P.willow[1], P.willow[2], 8) end)
wait(2)
cam2("wilson", "willow")
at(function(D)
    D:Face("willow", "wilson")
    D:Face("wilson", P.willow[1], P.willow[2])
end)
say("willow", "木头也准备好了！")
say("wilson", "放在哪里？")
say("willow", "烧掉了，暖和！")
anim("willow", "emoteXL_happycheer")
wait(1)

at(function(D) D:Walk("wendy", P.wendy[1], P.wendy[2], 8) end)
wait(2)
cam2("wilson", "wendy")
at(function(D)
    D:Face("wendy", "wilson")
    D:Face("wilson", P.wendy[1], P.wendy[2])
end)
say("wendy", "浆果采好了。")
say("wilson", "太好了！放冰箱了吗？")
say("wendy", "阿比盖尔吃了。", function(D)
    local abigail = D:Puppet("abigail", "ghost", "ghost_abigail_build", "idle", 3.8, 3.6)
    abigail.idle_anims = { "idle" }
    abigail.AnimState:SetBloomEffectHandle("shaders/anim_bloom_ghost.ksh")
    abigail.AnimState:SetMultColour(1, 1, 1, 0.7)
    D:Anim("abigail", "appear")
end)
wait(0.4)
at(function(D)
    local abigail = D:Actor("abigail")
    abigail.AnimState:PlayAnimation("dissipate")
    abigail:ListenForEvent("animover", function() D:Exit("abigail") end)
end)
wait(1.5)
at(function(D) D:Exit("abigail") end)

-- 镜头转向 WX-78
at(function(D) D:Walk("wx78", P.wx78[1], P.wx78[2], 8) end)
wait(2)
at(function(D)
    D:Face("wx78", "wilson")
    D:Face("wilson", P.wx78[1], P.wx78[2])
end)
cam(P.wx78[1] - 0.5, P.wx78[2], 10, 1)
say("wilson", "那你呢？科技研发有什么成果？")
say("wx78", "我升级了自己。")
anim("wx78", "emote_strikepose")
wait(1.2)
say("wilson", "你研究出什么新科技了？")
say("wx78", "我现在可以更高效地嘲讽你们了。")
anim("wx78", "emoteXL_happycheer")
anim("wilson", "emoteXL_facepalm")
wait(1.6)

--------------------------------------------------------------------------
-- 第三幕：冬天来了

card("第三幕", "冬天来了", function(D)
    D:Season("winter")
    D:Temperature(-20)
    D:Precipitation(true)
    D:SnowLevel(0.5)
    D:Phase("dusk")
    for _, who in ipairs({ "wilson", "wolfgang", "willow", "wendy", "wx78" }) do
        D:Face(who, FIRE[1], FIRE[2])
        D:Idle(who, { "idle_shiver_pre", "idle_shiver_loop" })
    end
    D:Camera(0, 0, 13, 0)
end)

at(function(D) D:SnowLevel(0.7) end)
say("wilson", "快！谁有暖石？！")
cam2("wilson", "wolfgang")
say("wolfgang", "我没有，我把暖石吃了。")
at(function(D) D:Face("wilson", P.wolfgang[1], P.wolfgang[2]) end)
say("wilson", "暖石不能吃啊！！！")
anim("wilson", "emoteXL_angry")
wait(0.8)
cam2("wilson", "willow")
say("willow", "别担心，我有火！")

-- 薇洛点燃整个基地
anim("willow", "atk")
cam(0, -1.5, 17, 2)
for i, name in ipairs(BASE) do
    at(function(D) D:Ignite(name, 22) end)
    wait(0.35)
end
at(function(D) D:SnowLevel(0.9) end)
wait(1.2)
at(function(D) D:Face("wilson", -1.9, -3.4) end)
say("wilson", "我的家！！！")
anim("wilson", "emoteXL_sad")
wait(0.8)
say("wx78", "检测到基地温度上升。任务完成。")
say("wendy", "至少我们不会冻死了。")

-- 远处传来猎犬叫声
at(function(D)
    D:Sound(HOUND_DISTANT)
    D:Phase("night")
end)
wait(1.2)
at(function(D) D:Sound(HOUND_BARK) end)
face_all(14, 0)
wait(0.8)
cam(0, -1.2, 11, 0.6)
say("wilson", "所有人准备战斗！")

-- 镜头一转，人都跑光了
at(function(D) D:Fade(false, 0.25) end)
wait(0.3)
at(function(D)
    for _, who in ipairs(CREW) do
        D:Exit(who)
    end
    D:Camera(P.wilson[1], P.wilson[2], 9, 0)
end)
wait(0.1)
at(function(D) D:Fade(true, 0.25) end)
wait(1.8)
at(function(D) D:Face("wilson", 0, 5) end)
wait(0.6)
say("wilson", "……我就知道。")
anim("wilson", "emoteXL_facepalm")
wait(1.8)

--------------------------------------------------------------------------
-- 第四幕：最终反转（第二天早上，基地只剩焦黑残骸）

card("第四幕", "最终反转", function(D)
    D:Phase("day")
    D:Precipitation(false)
    D:Temperature(-5)
    D:Idle("wilson", { "idle_loop" })
    D:Face("wilson", 0, 5)
    for _, who in ipairs(CREW) do
        D:Spawn(who, who, OFF[who][1], OFF[who][2])
    end
    D:Camera(0, -0.5, 14, 0)
end)

at(function(D)
    for _, who in ipairs(CREW) do
        D:Walk(who, P[who][1], P[who][2], 7)
    end
end)
wait(2.6)
face_all(P.wilson[1], P.wilson[2])
at(function(D) D:Face("wilson", 0, 5) end)
wait(0.3)
say("wilson", "昨天晚上你们都去哪了？")
say("wolfgang", "我去寻找食物了！")
say("willow", "我去寻找木材了！")
say("wendy", "我去寻找阿比盖尔了。")
say("wx78", "我去寻找更高级的队友了。")
say("wilson", "那你们为什么又回来了？")
say_all("因为你的复活石还在！")
cam(TOUCHSTONE[1], TOUCHSTONE[2], 9, 1.2)
wait(2.4)

-- 威尔逊沉默三秒
cam(P.wilson[1], P.wilson[2], 8, 1.2)
wait(1.2)
wait(3)
say("wilson", "我宣布，今天开始，基地禁止开会。")
wait(0.6)
at(function(D) D:Fade(false, 1.5) end)
wait(1.7)
at(function(D) D:Title("饥荒联机版", "真正的生存不是对抗自然，而是对抗队友。", 4.2) end)
wait(4.6)

return {
    name = "meeting",
    set_radius = 30,
    ground = "GRASS",
    length = T,
    env = { season = "autumn", phase = "day", moon = "full", temperature = 15, precipitation = false, snowlevel = 0 },
    cues = cues,
}
