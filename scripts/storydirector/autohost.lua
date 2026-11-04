-- 自动开拍用的建服流程，由 client_save/story_director_autohost 的内容驱动（<场景> 可省略，默认 sample）：
--   HOST <场景>：主菜单自动新建离线、无洞穴、不带其他模组的片场世界，改写为 PICK <场景>
--   PICK <场景>：选人界面自动选威尔逊，改写为 DONE <场景>
--   DONE <场景>：玩家进入世界后自动开拍该场景，改写为 PLAYED
-- 外部脚本写入 HOST 后启动游戏即可；其他内容（或文件不存在）时什么都不做。

local FLAG_FILE = "story_director_autohost"
local LOG_TAG = "[STORY_DIRECTOR]"
local STUDIO_PRESET = "STORY_STUDIO"

local AutoHost = {}

-- cb(state, scene)；读到的内容已由引擎去掉 SetPersistentString 的文件头
local function ReadFlag(cb)
    TheSim:GetPersistentString(FLAG_FILE, function(ok, str)
        if not ok or str == nil then
            cb(nil)
            return
        end
        local state, scene = str:match("^%s*(%u+)%s*(%w*)")
        cb(state, scene ~= "" and scene or "sample")
    end)
end

local function WriteFlag(state, scene)
    TheSim:SetPersistentString(FLAG_FILE, scene ~= nil and (state.." "..scene) or state, false)
end

local function HostNewWorld(mainscreen, scene)
    local ServerSlotScreen = require "screens/redux/serverslotscreen"
    local ServerCreationScreen = require "screens/redux/servercreationscreen"
    local slot = ShardSaveGameIndex:GetNextNewSlot("local")
    print(LOG_TAG, "autohost: 新建世界，存档位", slot)

    -- 建服界面依赖上一层的存档位列表界面，按游戏原本的层级压栈
    local slotscreen = ServerSlotScreen(mainscreen)
    TheFrontEnd:PushScreen(slotscreen)
    local screen = ServerCreationScreen(slotscreen, slot)
    TheFrontEnd:PushScreen(screen)

    local settings = screen.server_settings_tab
    settings.online_mode.spinner:SetSelected(false)
    if settings:GetServerName() == "" then
        settings.server_name.textbox:SetString("Story Director")
    end
    for i, tab in ipairs(screen.world_tabs) do
        if i > 1 then
            tab:RemoveMultiLevel()
        end
    end
    -- 片场世界预设（modworldgenmain.lua），找不到时游戏会退回默认世界
    local Levels = require "map/levels"
    if Levels.GetDataForID(LEVELCATEGORY.WORLDGEN, STUDIO_PRESET) ~= nil then
        screen.world_tabs[1]:OnCombinedPresetButton(STUDIO_PRESET)
    else
        print(LOG_TAG, "autohost: 找不到片场预设，使用默认世界")
    end
    -- 不应用模组页：新存档不带任何服务器模组，导演模组靠 ForceEnableMod 加载
    screen.mods_enabled = false

    WriteFlag("PICK", scene)
    screen.inst:DoTaskInTime(1, function()
        screen:Create(true, true, true)
    end)
end

function AutoHost.OnMainScreen(mainscreen)
    ReadFlag(function(state, scene)
        if state ~= "HOST" then
            return
        end
        -- 等主菜单位于最上层（公告等弹窗关掉后）
        local tries = 0
        local task
        task = mainscreen.inst:DoPeriodicTask(1, function()
            tries = tries + 1
            if TheFrontEnd:GetActiveScreen() == mainscreen then
                task:Cancel()
                HostNewWorld(mainscreen, scene)
            elseif tries > 120 then
                task:Cancel()
                print(LOG_TAG, "autohost: 120 秒内没等到主菜单，放弃")
            end
        end)
    end)
end

function AutoHost.OnLobby(lobby)
    ReadFlag(function(state, scene)
        if state ~= "PICK" or lobby.cb == nil then
            return
        end
        lobby.inst:DoTaskInTime(2, function()
            print(LOG_TAG, "autohost: 选择威尔逊")
            WriteFlag("DONE", scene)
            lobby.cb("wilson", "wilson_none")
        end)
    end)
end

-- 玩家进入世界后调用：标记为 DONE 时取出要自动开拍的场景
function AutoHost.TakeAutoplayScene(cb)
    ReadFlag(function(state, scene)
        if state == "DONE" then
            WriteFlag("PLAYED")
            cb(scene)
        end
    end)
end

return AutoHost
