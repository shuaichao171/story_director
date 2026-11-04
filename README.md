# 剧情导演 Story Director

用《饥荒联机版》游戏本身当摄影棚：写一份 Lua 剧本（角色、台词、走位、镜头、天气、怪物、地形），一条命令自动建世界、开拍，并录成带游戏声音的视频。

自带四个示例场景：

| 场景 | 内容 | 时长 |
| --- | --- | --- |
| `sample` | 威尔逊和薇洛在黄昏营火边聊天 | 24 秒 |
| `storm` | 天气与地形演示：下雨、打雷、秋转冬、积雪、铺路 | 27 秒 |
| `firstnight` | 短片《第一夜》：猎犬来袭，薇洛用火墙救人 | 1 分钟 |
| `meeting` | 四幕搞笑短剧《基地会议》 | 3 分 30 秒 |

## 快速上手

### 1. 准备

- Windows 10（1903 以上）或 Windows 11
- Steam 版《饥荒联机版》
- [Python 3.8 以上](https://www.python.org/downloads/)：安装时勾选 **Add python.exe to PATH**
- FFmpeg：在 PowerShell 里运行下面这条命令，装完**重新打开**命令行窗口

  ```powershell
  winget install Gyan.FFmpeg
  ```

### 2. 把项目放进游戏的 mods 文件夹

在 Steam 库里右键《饥荒联机版》→ 管理 → 浏览本地文件，打开 `mods` 文件夹，把本项目放进去，文件夹名用 `story_director`：

```powershell
cd "<游戏目录>\mods"
git clone https://github.com/shuaichao171/story_director.git
```

不用 git 的话，在 GitHub 页面点 Code → Download ZIP，解压到 `mods` 里，并把文件夹 `story_director-main` 改名为 `story_director`。

放好后的路径应该是：`...\Don't Starve Together\mods\story_director\modinfo.lua`

### 3. 安装录音用的 Python 库

```powershell
cd "<游戏目录>\mods\story_director"
python -m pip install -r requirements.txt
```

### 4. 检查环境

```powershell
python tools/shoot.py --check
```

每一项都是 `[ OK ]` 就可以开拍；`[缺少]` 的项目下面会写怎么补。如果提示找不到存档目录，先正常打开一次游戏、进到主菜单再退出。

### 5. 开拍

先**关闭游戏**，然后：

```powershell
python tools/shoot.py sample
```

脚本会自动完成：

1. 在 `mods/modsettings.lua` 临时启用本模组（拍完自动删掉这行，不影响你平时玩）
2. 启动游戏，新建一个离线、无洞穴的「剧情片场」世界（约 1～2 分钟），自动选人
3. 进入世界后开拍，同时录制游戏画面和声音
4. 拍完把视频存到 `takes/sample_<时间>.mp4`

游戏不会自动关闭。改完剧本后再运行同一条命令，就在这个世界里直接重拍（几秒钟就开始）。换别的场景：`python tools/shoot.py meeting`。

## 拍摄须知

- **录音会录进电脑上此时所有的声音**（音乐、聊天软件提示音等），录制前先关掉。只要画面加 `--no-audio`。
- 视频分辨率就是游戏窗口大小。建议用**窗口模式或无边框窗口**，独占全屏可能录不到画面。
- FFmpeg 8 以上会直接抓游戏窗口，窗口被挡住也不影响；旧版 FFmpeg 会改为录屏幕区域，录制时不要遮挡、不要最小化游戏窗口。
- 游戏刚启动时 Steam 可能在右上角弹出提示，被录进开头的话，在已开着的游戏里重拍一次即可（或在 Steam 设置里关闭游戏内通知）。
- 每次从关闭游戏的状态开拍都会新建一个名为 Story Director 的存档，不需要了可以在游戏的「主机游戏」存档列表里删除。
- 剧本会清空布景区里原有的东西，为了不误伤你的正常存档，**只会在「剧情片场」世界里开拍**。

### 常用参数

| 参数 | 作用 |
| --- | --- |
| `--out 路径.mp4` | 指定输出文件 |
| `--no-audio` | 只录画面 |
| `--capture screen` | 改为录屏幕区域 |
| `--save-dir <目录>` | 有多个游戏账号、自动找到的存档目录不对时，指定 `文档\Klei\DoNotStarveTogether\<账号>\client_save` |
| `--ffmpeg <ffmpeg.exe>` | ffmpeg 不在 PATH 里时指定 |
| `--max-length 秒` | 单条最长录多久（默认 600） |

### 不用脚本、手动开拍

自动建世界失败、或者用的是 WeGame 版时：

1. 在游戏里「创建世界」，模组页启用「剧情导演 Story Director」，世界设置的预设选「剧情片场」，删掉洞穴，进入世界
2. 运行 `python tools/shoot.py sample`（游戏开着时脚本会直接让游戏开拍并录制）

只想在游戏里看、不录像：按 `~` 打开控制台输入 `c_story("sample")`，`c_story_stop()` 中断。

### 常见问题

| 现象 | 处理 |
| --- | --- |
| `python` 不是内部或外部命令 | 重新安装 Python 并勾选 Add to PATH，然后重新打开命令行 |
| 找不到 ffmpeg | 运行 `winget install Gyan.FFmpeg` 后重新打开命令行；或用 `--ffmpeg` 指定 |
| 游戏启动了但一直不开拍 | 看看游戏是不是停在弹窗、更新或登录界面上，点掉后会继续；仍不行就查看 `文档\Klei\DoNotStarveTogether\client_log.txt` 里带 `[STORY_DIRECTOR]` 的行 |
| 提示「当前不是剧情片场世界」 | 游戏是自己打开的普通世界。关掉游戏后重新运行 `shoot.py`，让它自动建片场世界 |
| 「游戏没有响应」 | 游戏开着但没加载本模组（比如手动打开的游戏）。关掉游戏后重新运行 |
| 视频没有声音 | 检查 Windows 默认的声音输出设备是不是你在听的那个；`--check` 会显示正在录的设备 |
| 视频是黑的 | 改用窗口模式，或加 `--capture screen` |

## 目录

| 文件 | 作用 |
| --- | --- |
| `tools/shoot.py` | 一条命令拍摄：环境检查、临时启用模组、自动建世界、录制、还原 |
| `tools/record.py` | 录制：等游戏的开拍信号，录游戏窗口和系统声音，自动对齐合成 |
| `modinfo.lua`、`modmain.lua` | 模组入口：`c_story(名字)` 开拍、接收录制脚本的开拍指令、自动建世界后自动开拍 |
| `modworldgenmain.lua` | 片场世界预设「剧情片场」(`STORY_STUDIO`)：小地图，草地 + 树林 + 草原，无道路、布景、节日活动、Boss、袭击、鸟、蝴蝶、兔子 |
| `scripts/storydirector/director.lua` | 导演引擎（演员、生物、镜头、台词、画面、地形、时间天气） |
| `scripts/storydirector/autohost.lua` | 自动新建片场世界并选人 |
| `scripts/storydirector/scenes/*.lua` | 场景剧本，文件名就是场景名 |

## 写自己的剧本

新建一个 `scripts/storydirector/scenes/<场景名>.lua`（场景名只用字母、数字、下划线），然后 `python tools/shoot.py <场景名>`。长剧本可以参考 `meeting.lua`：按台词顺序写，时长按字数自动算。

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

### 导演接口 `D:`

| 类别 | 接口 |
| --- | --- |
| 演员 | `Spawn(名字, build, dx, dz)`、`Face(名字, 另一名字 或 dx, dz)`、`Walk(名字, dx, dz, 速度)`、`Say(名字, 台词, 秒)`、`Anim(名字, 动画或动画列表, 循环)`（如 `{ "eat_pre", "eat" }`）、`Idle(名字, 待机动画列表)`（如发抖 `{ "idle_shiver_pre", "idle_shiver_loop" }`）、`Exit(名字)` 下场、`Puppet(名字, bank, build, 动画, dx, dz)` 只有动画的木偶（如阿比盖尔） |
| 道具 | `Prop(prefab, dx, dz, 名字)`（名字可省）、`Scatter(prefab, dx, dz, 半径, 数量, 种子)`、`Ignite(名字, 秒)` 点燃起了名字的道具，烧完变成焦黑残骸，火不蔓延 |
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
