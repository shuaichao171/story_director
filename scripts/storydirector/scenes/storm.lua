-- 演示《暴风雪之夜》：布景、地皮、下雨打雷、秋转冬、雨变雪、积雪、铺路、入夜。
-- 坐标为舞台坐标：x 向屏幕右，z 向屏幕下（朝镜头）；t 为秒。

local cues = {
    { t = 0, fn = function(D)
        -- 布景：营地泥地、背景树林、右侧草丛
        D:Turf("DIRT", 0, 0.5, 5)
        D:Scatter("evergreen", 0, -12, 7, 10, 3)
        D:Scatter("grass", 9, 1, 3, 5, 11)
        D:Spawn("wilson", "wilson", -2, 0)
        D:Spawn("willow", "willow", 2.2, 0.2)
        D:Face("wilson", "willow")
        D:Face("willow", "wilson")
        D:Camera(0, 0, 15, 0)
    end },
    { t = 0.5, fn = function(D)
        D:Title("暴风雪之夜", "片场世界 · 天气与地形演示", 2.3)
    end },
    { t = 3, fn = function(D)
        D:Fade(true, 1.5)
    end },
    { t = 4.5, fn = function(D)
        D:Say("wilson", "风变大了……", 2.2)
        D:Camera(0, 0, 13, 0, 3)
    end },
    { t = 5.5, fn = function(D)
        D:Precipitation(true)
    end },
    { t = 7, fn = function(D)
        D:Lightning(7, -6)
    end },
    { t = 7.6, fn = function(D)
        D:Say("willow", "要下大雨了，快生火！", 2.5)
    end },
    { t = 10, fn = function(D)
        D:Prop("campfire", 0, 1.3)
        D:Anim("willow", "emoteXL_happycheer")
        D:Face("wilson", 0, 1.3)
    end },
    { t = 11, fn = function(D)
        D:Season("winter")
        D:Temperature(-10)
        D:SnowLevel(0.2)
    end },
    { t = 12, fn = function(D)
        D:Say("wilson", "雨……变成雪了？", 2.3)
    end },
    { t = 13.5, fn = function(D) D:SnowLevel(0.5) end },
    { t = 14.5, fn = function(D)
        D:Face("willow", 10, 7)
        D:Say("willow", "看，那边有条路。", 2.3)
    end },
    { t = 15, fn = function(D) D:SnowLevel(0.8) end },
    { t = 19, fn = function(D) D:SnowLevel(1) end },
    { t = 19.5, fn = function(D)
        D:Phase("night")
        D:Lightning(-8, -7)
    end },
    { t = 20, fn = function(D)
        D:Camera(0, 1, 20, 25, 4)
    end },
    { t = 24.5, fn = function(D)
        D:Fade(false, 2)
    end },
}

-- 道路从左到右一段段铺出来
for i = 0, 7 do
    table.insert(cues, { t = 15.5 + i * 0.35, fn = function(D)
        D:TurfLine("ROAD", -16 + i * 4, 7, -12 + i * 4, 7, 4)
    end })
end

return {
    name = "storm",
    set_radius = 26,
    ground = "GRASS",
    length = 27,
    env = { season = "autumn", phase = "dusk", moon = "full", precipitation = false, snowlevel = 0 },
    cues = cues,
}
