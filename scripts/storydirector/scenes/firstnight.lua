-- 正式短片《第一夜》（约 1 分钟，生存冒险）
-- 黄昏，威尔逊独自在荒野迷路；两只猎犬从右侧围上来，一只扑倒了他。
-- 薇洛赶到，点燃一排草丛筑起火墙，猎犬退走。入夜下雪，两人守着营火，远处又传来嚎叫。
-- 坐标为舞台坐标：x 向屏幕右，z 向屏幕下（朝镜头）；t 为秒。

local HOUND_DISTANT = "dontstarve/creatures/hound/distant"
local HOUND_GROWL = "dontstarve/creatures/hound/growl"
local WILSON_HURT = "dontstarve/characters/wilson/hurt"

local cues = {
    -- 布景（黑场中）。布景区内原有物件已清空、铺满草地，画面里的东西全在这里布置：
    -- 上方一条林带，右侧稀树草原（猎犬来的方向），左侧是营地泥地
    { t = 0, fn = function(D)
        D:TurfLine("FOREST", -30, -16, 22, -16, 12)
        D:Turf("SAVANNA", 15, 3, 8)
        D:Turf("DIRT", -8.5, 1.5, 5)
        D:Scatter("evergreen", -15, -16, 9, 12, 7)
        D:Scatter("evergreen", 5, -16, 9, 12, 9)
        D:Scatter("evergreen_sparse", 13, -8, 4, 3, 5)
        D:Scatter("sapling", -6, -8, 6, 4, 17)
        D:Scatter("grass", -17, -3, 3, 4, 13)
        D:Scatter("grass", 16, 5, 5, 6, 27)
        D:Scatter("flower", 4, 4, 4, 4, 21)
        D:Scatter("flower", -16, 8, 4, 3, 31)
        D:Prop("rock1", 10, -4)
        D:Prop("rock2", -20, 5)
        D:Spawn("wilson", "wilson", -3, 0)
        D:Face("wilson", 8, 0)
        D:Camera(-1, 0, 13, 0)
    end },
    { t = 0.5, fn = function(D) D:Title("第一夜", "饥荒 · 生存短片", 2.6) end },
    { t = 3.3, fn = function(D) D:Fade(true, 2) end },

    -- 一、迷路
    { t = 4.8, fn = function(D)
        D:Say("wilson", "这地方……连个人影都没有。", 2.8)
        D:Camera(-2, 0, 11, 0, 5)
    end },
    { t = 8, fn = function(D) D:Anim("wilson", "pickup") end },
    { t = 8.6, fn = function(D) D:Say("wilson", "天快黑了，得找点吃的。", 2.4) end },
    { t = 11.2, fn = function(D) D:Sound(HOUND_DISTANT) end },
    { t = 12, fn = function(D)
        D:Face("wilson", 12, 0)
        D:Say("wilson", "……什么声音？", 1.8)
    end },

    -- 二、猎犬
    { t = 13.2, fn = function(D)
        D:Creature("hound1", "hound", 18, -1.5)
        D:Creature("hound2", "hound", 19, 1.8)
        D:Move("hound1", 4.5, -1.2)
        D:Move("hound2", 6, 1.6)
        D:Camera(-0.5, 0, 16, 0, 2)
    end },
    { t = 14.8, fn = function(D) D:State("hound1", "taunt", true) end },
    { t = 15.2, fn = function(D)
        D:State("hound2", "taunt", true)
        D:Say("wilson", "猎……猎犬！", 1.6)
    end },
    { t = 16.8, fn = function(D)
        D:Walk("wilson", -5.5, 0.4, 3.5)
        D:Move("hound1", 1, -0.8)
        D:Move("hound2", 2.5, 1.4)
    end },
    { t = 17.8, fn = function(D)
        D:Face("wilson", "hound1")
        D:Sound(HOUND_GROWL)
    end },
    { t = 18.3, fn = function(D) D:Say("wilson", "别、别过来！", 1.6) end },
    { t = 20, fn = function(D) D:Move("hound1", -4, 0.2) end },
    { t = 20.6, fn = function(D) D:State("hound1", "attack") end },
    { t = 21.1, fn = function(D)
        D:Anim("wilson", "hit")
        D:Sound(WILSON_HURT)
    end },
    { t = 21.8, fn = function(D)
        D:Walk("wilson", -8.5, 0.8, 6)
        D:Move("hound2", -1, 1.8)
    end },

    -- 三、火墙
    { t = 22.2, fn = function(D)
        D:Spawn("willow", "willow", -17, 0.3)
        D:Walk("willow", -11.5, 0.3, 7)
    end },
    { t = 23, fn = function(D)
        D:Face("wilson", "hound1")
        D:Face("willow", "hound1")
        D:Say("willow", "退后！", 1.4)
        D:Camera(-5, 0, 16, 0, 2)
    end },
    { t = 23.6, fn = function(D) D:Anim("willow", "atk") end },
    { t = 25.2, fn = function(D)
        D:State("hound1", "startle")
        D:State("hound2", "startle")
    end },
    { t = 26.3, fn = function(D)
        D:Move("hound1", 0.5, -0.6)
        D:Move("hound2", 2, 1.8)
        D:Say("willow", "哈！它们最怕的就是火！", 2.4)
    end },
    { t = 27.6, fn = function(D)
        D:State("hound1", "taunt", true)
        D:Face("hound1", -8, 0)
    end },
    { t = 28.1, fn = function(D) D:State("hound2", "taunt", true) end },
    { t = 29, fn = function(D) D:Phase("night") end },
    { t = 29.6, fn = function(D)
        D:Move("hound1", 19, -2.5)
        D:Move("hound2", 20, 2)
    end },
    { t = 30.4, fn = function(D) D:Say("wilson", "它们……走了？", 1.8) end },

    -- 四、营火
    { t = 32.4, fn = function(D)
        D:Face("willow", "wilson")
        D:Face("wilson", "willow")
        D:Say("willow", "暂时而已。天一黑，它们还会回来。", 3)
        D:Camera(-10, 1.5, 12, 0, 3)
    end },
    { t = 36, fn = function(D) D:Say("wilson", "我……我连火都不会生。", 2.4) end },
    { t = 38.8, fn = function(D) D:Say("willow", "那就学。先把这堆火守住。", 2.6) end },
    { t = 39.6, fn = function(D) D:Walk("willow", -11.6, 2.4, 4) end },
    { t = 40.6, fn = function(D)
        D:Face("willow", -10, 2.6)
        D:Anim("willow", "build_pre")
        D:Walk("wilson", -8.4, 2.4, 3)
    end },
    { t = 41.4, fn = function(D)
        D:Prop("campfire", -10, 2.6)
        D:Face("wilson", -10, 2.6)
    end },
    { t = 42.4, fn = function(D)
        D:Season("winter")
        D:Temperature(-10)
        D:Precipitation(true)
        D:SnowLevel(0.15)
    end },
    { t = 44, fn = function(D)
        D:Say("wilson", "下雪了……", 1.8)
        D:Anim("wilson", "idle_shiver_pre")
    end },
    { t = 46.2, fn = function(D)
        D:Say("willow", "冬天要来了。想活下去，就别让火灭了。", 3.4)
        D:SnowLevel(0.35)
    end },
    { t = 50, fn = function(D) D:Sound(HOUND_DISTANT) end },
    { t = 50.6, fn = function(D)
        D:Face("wilson", 14, 0)
        D:Face("willow", 14, 0)
    end },
    { t = 51.4, fn = function(D)
        D:Say("wilson", "……今晚会很长。", 2.4)
        D:SnowLevel(0.6)
    end },
    { t = 53.4, fn = function(D) D:Camera(-10, 2, 19, 30, 5) end },
    { t = 56, fn = function(D) D:SnowLevel(0.85) end },
    { t = 57.5, fn = function(D) D:Fade(false, 2) end },
    { t = 60, fn = function(D) D:Title("未完待续", "", 2.6) end },
}

-- 薇洛扔出火种：一排草丛从上到下依次点燃，挡在两人和猎犬之间
for i = 0, 5 do
    table.insert(cues, { t = 24 + i * 0.14, fn = function(D)
        D:Burn(-6.5, -3 + i * 1.2, 19 - i * 0.14)
    end })
end

return {
    name = "firstnight",
    set_radius = 30,       -- 覆盖所有镜头（含最后拉远）能拍到的范围
    ground = "GRASS",
    length = 63,
    env = { season = "autumn", phase = "dusk", moon = "full", precipitation = false, snowlevel = 0 },
    cues = cues,
}
