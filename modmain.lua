local G = GLOBAL

local LOG_TAG = "[STORY_DIRECTOR]"
-- 场景名：字母、数字、下划线
local SCENE_NAME = "[%w_]+"

-- 场景文件：scripts/storydirector/scenes/<名字>.lua
local function ScenePath(name)
    return "storydirector/scenes/"..(name or "sample")
end

-- 开拍失败：写进日志、在玩家头上显示，并写入信号文件让录制脚本停止等待并报告原因
local function Fail(msg)
    print(LOG_TAG, "ERROR", msg)
    G.TheSim:SetPersistentString("story_director_signal", "ERROR "..msg.." "..tostring(os.time()), false)
    if G.ThePlayer ~= nil and G.ThePlayer.components.talker ~= nil then
        G.ThePlayer.components.talker:Say(msg, 8)
    end
end

-- 剧本会清空布景区（半径几十格）里的原有物件，只允许在片场世界里拍，避免误删正常存档
local function IsStudioWorld()
    local topology = G.TheWorld.topology
    return topology ~= nil and topology.overrides ~= nil and topology.overrides.task_set == "story_studio"
end

local current = nil

-- force = true 时跳过片场世界检查（会清掉当前世界布景区里的东西）
local function PlayScene(name, force)
    name = name or "sample"
    if not G.TheWorld.ismastersim or G.ThePlayer == nil or G.ThePlayer.HUD == nil then
        print(LOG_TAG, "需要在主机上、玩家已进入世界后运行")
        return
    end
    if not name:match("^"..SCENE_NAME.."$") then
        Fail("场景名只能用字母、数字和下划线："..name)
        return
    end
    local path = ScenePath(name)
    if not G.kleifileexists(MODROOT.."scripts/"..path..".lua") then
        Fail("找不到场景文件 scripts/"..path..".lua")
        return
    end
    if not force and not IsStudioWorld() then
        Fail("当前不是「剧情片场」世界，为免清掉存档里的东西没有开拍。用 tools/shoot.py 自动建片场世界，或在控制台 c_story(\""..name.."\", true) 强制开拍")
        return
    end
    if current ~= nil then
        current:Stop()
    end
    -- 方便改完台本或导演引擎后直接重拍，不用重启游戏
    G.package.loaded[path] = nil
    G.package.loaded["storydirector/director"] = nil
    local ok, err = G.pcall(function()
        local Director = G.require("storydirector/director")
        current = Director(G.require(path))
    end)
    if not ok then
        current = nil
        Fail("场景加载出错："..tostring(err))
        return
    end
    current:Play(function() current = nil end)
end

-- 控制台：c_story("storm") 开拍指定场景（默认 sample），c_story_stop() 中断
G.rawset(G, "c_story", PlayScene)
G.rawset(G, "c_story_stop", function()
    if current ~= nil then
        current:Stop()
        current = nil
        G.TheFrontEnd:Fade(G.FADE_IN, 0.5)
    end
end)

-- 自动建世界与选人（只在外部写入 autohost 标记时生效，见 autohost.lua）
local AutoHost = G.require("storydirector/autohost")
AddClassPostConstruct("screens/redux/multiplayermainscreen", function(self)
    AutoHost.OnMainScreen(self)
end)
AddClassPostConstruct("screens/redux/lobbyscreen", function(self)
    AutoHost.OnLobby(self)
end)

AddPrefabPostInit("world", function(world)
    if not world.ismastersim then
        return
    end

    -- 自动建的世界：玩家进入、出生动画播完后开拍标记里的场景
    world:ListenForEvent("playeractivated", function(_, player)
        if player == G.ThePlayer then
            AutoHost.TakeAutoplayScene(function(scene)
                world:DoTaskInTime(8, function() PlayScene(scene) end)
            end)
        end
    end)

    -- 外部指令：tools/record.py --play 会在 client_save/story_director_cmd 写 "PLAY <场景> <时间戳>"
    local last_cmd = nil
    local function ReadCommand(cb)
        G.TheSim:GetPersistentString("story_director_cmd", function(ok, str)
            cb(ok and str ~= nil and str:match("PLAY%s+"..SCENE_NAME.."%s+%d+") or nil)
        end)
    end
    ReadCommand(function(cmd) last_cmd = cmd or "" end)
    world:DoPeriodicTask(1, function()
        if last_cmd == nil or G.ThePlayer == nil then
            return
        end
        ReadCommand(function(cmd)
            if cmd ~= nil and cmd ~= last_cmd then
                last_cmd = cmd
                PlayScene(cmd:match("PLAY%s+("..SCENE_NAME..")"))
            end
        end)
    end)
end)
