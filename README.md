# 剧情导演 Story Director

用《饥荒联机版》引擎按时间线演出剧情，并自动录成带声音的视频。

## 目录

| 文件 | 作用 |
| --- | --- |
| `modworldgenmain.lua` | 片场世界预设「剧情片场」(`STORY_STUDIO`)：小地图，草地 + 树林 + 草原，无道路、布景、节日活动、Boss、袭击、鸟、蝴蝶、兔子 |
| `modmain.lua` | 入口：`c_story(名字)` 开拍、文件指令开拍、自动建世界后自动开拍 |
| `scripts/storydirector/director.lua` | 导演引擎（演员、镜头、台词、画面、地形、时间天气） |
| `scripts/storydirector/autohost.lua` | 自动新建片场世界并选人 |
| `scripts/storydirector/scenes/*.lua` | 场景剧本，文件名就是场景名；`firstnight` 是 1 分钟正式短片《第一夜》 |
| `tools/record.py` | 等开拍信号录制游戏窗口 + 系统声音，自动对齐合成 |

## 写场景

```lua
return {
    name = "my_scene",
    set_radius = 26,           -- 布景区半径：要盖住所有镜头能拍到的范围
    ground = "GRASS",          -- 布景区底层地皮，先铺满整片，再由剧本铺别的地皮
    length = 20,               -- 总时长（秒），到点淡出收工
    keep_set = false,          -- true：拍完保留道具和地皮；默认收工复原
    env = { season = "autumn", phase = "dusk", moon = "full",
            temperature = nil, precipitation = false, snowlevel = 0 },
    cues = {
        { t = 0, fn = function(D) D:Spawn("wilson", "wilson", -2, 0) end },
        { t = 3, fn = function(D) D:Fade(true, 1.5) end },
    },
}
```

舞台坐标 `(dx, dz)`：`dx` 向屏幕右，`dz` 向屏幕下（朝镜头），原点为舞台中心；一格地皮 = 4。

## 导演接口 `D:`

| 类别 | 接口 |
| --- | --- |
| 演员 | `Spawn(名字, build, dx, dz)`、`Face(名字, 另一名字 或 dx, dz)`、`Walk(名字, dx, dz, 速度)`、`Say(名字, 台词, 秒)`、`Anim(名字, 动画, 循环)` |
| 道具 | `Prop(prefab, dx, dz)`、`Scatter(prefab, dx, dz, 半径, 数量, 种子)` |
| 地形 | `Turf(地皮, dx, dz, 半径)`、`TurfLine(地皮, x1, z1, x2, z2, 宽)`、`Clear(dx, dz, 半径)`；地皮名取 `WORLD_TILES`，如 GRASS、FOREST、SAVANNA、DIRT、ROCKY、MARSH、ROAD、WOODFLOOR、CARPET、OCEAN_COASTAL |
| 时间 | `Phase("day"/"dusk"/"night")`、`ClockSegs{day=,dusk=,night=}`（合计 16）、`Moon("new"…"full")`、`TimeScale(倍率)` |
| 季节天气 | `Season("autumn"/"winter"/"spring"/"summer")`、`Temperature(度数/nil)`、`Precipitation(true/false)`、`SnowLevel(0~1)`、`Lightning(dx, dz)` |
| 生物 | `Creature(名字, prefab, dx, dz)` 生成真实生物（关 AI、无敌、不睡、不掉落），`Move(名字, dx, dz)` 跑位，`State(名字, 状态, 参数)` 播状态机动作（猎犬：taunt、attack、startle、hit、howl）；`Face`、收工删除和人物演员共用 |
| 音效与火 | `Sound(音效路径)` 播全局音效（如 `dontstarve/creatures/hound/distant`），`Burn(dx, dz, 秒)` 放一丛草点燃，烧完消失、不蔓延 |
| 镜头 | `Camera(dx, dz, 距离, 朝向偏移角, 秒)`（秒省略则直接切） |
| 画面 | `Fade(淡入?, 秒)`、`Title(标题, 副标题, 秒)` |

说明：
- 下雨在气温低于约 5 度时变成雪；冬天刚开始时气温在临界值附近，要稳定下雪就加 `Temperature(-10)`。
- 收工时自动恢复：时间流速、降水模式、气温、场景道具、改过的地皮。季节、时段、月相不恢复。
- 布景区：搭台时在玩家附近找一块半径 `set_radius` 全是陆地、不含出生传送门的空地，区内原有物件全部删除（不恢复，所以要在片场世界里拍），删不得的（传送门、特效等）先藏起来、收工再显示，然后铺满 `ground` 地皮。画面里出现的东西因此全部来自剧本，背景也要在剧本里布置（树林、草丛、石头、地皮）。
- 拍摄期间隐身的玩家被挪到布景区后方，保证布景区内的生物不休眠、雨雪特效在场；收工后挪回原处。
- 旧场景只写了 `stage_radius` 时，布景区半径就取它，并且不铺底层地皮。
- 改完剧本或 `director.lua` 不用重启游戏，重拍时会重新加载；改 `modmain.lua`、`autohost.lua`、`modworldgenmain.lua` 需要重启。

## 拍摄

前提：在 `mods/modsettings.lua` 加 `ForceEnableMod("story_director")`（或在建服模组页启用）。

- **已在世界里**：
  `python tools/record.py --signal <client_save>/story_director_signal --out _ai_work/takes/x.mp4 --ffmpeg <ffmpeg.exe> --play my_scene`
- 片场预设改过以后（如关闭节日活动），只对之后新建的世界生效。
- **从主菜单全自动**：在 `<client_save>/story_director_autohost` 写入 `HOST my_scene`，先启动上面的录制脚本（不带 `--play`），再启动游戏。会新建一个离线、无洞穴、只开本模组的片场世界，自动选威尔逊并开拍。

`<client_save>` 是 `文档/Klei/DoNotStarveTogether/<账号ID>/client_save`。录音会录进电脑上此时所有的声音；`--no-audio` 只录画面，`--capture screen` 改为录屏幕区域。
