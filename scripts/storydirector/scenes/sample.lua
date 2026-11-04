-- 样片《第一夜》：威尔逊迷路，薇洛赶到并生起篝火。
-- 坐标为舞台坐标：x 向屏幕右，z 向屏幕下（朝镜头）；t 为秒。

return {
    name = "sample_first_night",
    set_radius = 24,
    ground = "GRASS",
    length = 24,
    cues = {
        { t = 0, fn = function(D)
            if TheWorld.state.isday then
                TheWorld:PushEvent("ms_setphase", "dusk")
            end
            D:Spawn("wilson", "wilson", -1.6, 0)
            D:Face("wilson", -5, 1)
            D:Camera(-1.6, 0, 15, 0)
        end },
        { t = 0.5, fn = function(D)
            -- 标题卡放在黑场上，淡入画面前收起，避免压在角色身上
            D:Title("第一夜", "饥荒剧场 · 样片", 2.3)
        end },
        { t = 3, fn = function(D)
            D:Fade(true, 1.5)
        end },
        { t = 4.5, fn = function(D)
            D:Say("wilson", "天快黑了……这到底是什么鬼地方？", 3)
            D:Camera(-0.8, 0, 13, 0, 3)
        end },
        { t = 6, fn = function(D)
            D:Face("wilson", 5, 1)
        end },
        { t = 7.5, fn = function(D)
            D:Spawn("willow", "willow", 11, 0.3)
            D:Walk("willow", 1.6, 0)
            D:Camera(0, 0, 13, 0, 1.6)
        end },
        { t = 8.2, fn = function(D)
            D:Face("wilson", "willow")
        end },
        { t = 9.6, fn = function(D)
            D:Face("willow", "wilson")
            D:Say("willow", "又来一个倒霉蛋。想活过今晚，就得有火。", 3.5)
        end },
        { t = 13.3, fn = function(D)
            D:Say("wilson", "可我们什么都没有……", 2.5)
            D:Camera(0, 0.3, 11, 0, 2)
        end },
        { t = 16, fn = function(D)
            D:Say("willow", "我有。", 1.5)
        end },
        { t = 16.8, fn = function(D)
            D:Prop("campfire", 0, 1.1)
            D:Anim("willow", "emoteXL_happycheer")
            D:Face("wilson", 0, 1.1)
            D:Camera(0, 0.6, 9.5, 0, 1.5)
        end },
        { t = 18.5, fn = function(D)
            D:Face("willow", 0, 1.1)
            D:Camera(0, 0.6, 10.5, 30, 4)
        end },
        { t = 21.5, fn = function(D)
            D:Fade(false, 2)
        end },
    },
}
