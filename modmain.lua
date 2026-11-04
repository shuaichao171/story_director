local G = GLOBAL

-- 场景文件：scripts/storydirector/scenes/<名字>.lua
local function ScenePath(name)
    return "storydirector/scenes/"..(name or "sample")
end

local current = nil

local function PlayScene(name)
    if not G.TheWorld.ismastersim or G.ThePlayer == nil or G.ThePlayer.HUD == nil then
        print("[STORY_DIRECTOR] 需要在主机上、玩家已进入世界后运行")
        return
    end
    if current ~= nil then
        current:Stop()
    end
    local path = ScenePath(name)
    -- 方便改完台本或导演引擎后直接重拍，不用重启游戏
    G.package.loaded[path] = nil
    G.package.loaded["storydirector/director"] = nil
    local Director = G.require("storydirector/director")
    current = Director(G.require(path))
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
            cb(ok and str ~= nil and str:match("PLAY%s+%w+%s+%d+") or nil)
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
                PlayScene(cmd:match("PLAY%s+(%w+)"))
            end
        end)
    end)
end)
