-- 片场世界：小地图，只有出生空地、草地、树林和稀树草原，没有道路、布景、节日活动、Boss 和袭击。
-- 建服时世界预设选「剧情片场」，或由自动建服流程（autohost.lua）直接选用。

local G = GLOBAL
local TILES = G.WORLD_TILES

AddRoom("StoryStudio_Start", {
    colour = { r = .5, g = .8, b = .5, a = .5 },
    value = TILES.GRASS,
    contents = {
        countprefabs = { spawnpoint_multiplayer = 1 },
        distributepercent = .03,
        distributeprefabs = { flower = .5, grass = .3, sapling = .2 },
    },
})

AddRoom("StoryStudio_Meadow", {
    colour = { r = .5, g = .8, b = .5, a = .5 },
    value = TILES.GRASS,
    contents = {
        distributepercent = .06,
        distributeprefabs = { flower = .4, grass = .3, sapling = .2, berrybush = .05, carrot_planted = .05 },
    },
})

AddRoom("StoryStudio_Woods", {
    colour = { r = .2, g = .6, b = .2, a = .5 },
    value = TILES.FOREST,
    contents = {
        distributepercent = .3,
        distributeprefabs = { evergreen = 1, evergreen_sparse = .3, grass = .05, fireflies = .05 },
    },
})

AddRoom("StoryStudio_Savanna", {
    colour = { r = .8, g = .8, b = .2, a = .5 },
    value = TILES.SAVANNA,
    contents = {
        distributepercent = .08,
        distributeprefabs = { grass = .8, rock1 = .1, flint = .1 },
    },
})

AddTask("StoryStudio", {
    locks = G.LOCKS.NONE,
    keys_given = { G.KEYS.PICKAXE, G.KEYS.AXE, G.KEYS.GRASS, G.KEYS.WOOD, G.KEYS.TIER1 },
    room_choices = {
        StoryStudio_Start = 1,
        StoryStudio_Meadow = 4,
        StoryStudio_Woods = 3,
        StoryStudio_Savanna = 2,
    },
    room_bg = TILES.GRASS,
    background_room = "StoryStudio_Meadow",
    colour = { r = 0, g = 1, b = 0, a = 1 },
})

AddStartLocation("story_studio", {
    name = "剧情片场",
    location = "forest",
    start_setpeice = "DefaultStart",
    start_node = "StoryStudio_Start",
})

AddTaskSet("story_studio", {
    name = "剧情片场",
    location = "forest",
    tasks = { "StoryStudio" },
    valid_start_tasks = { "StoryStudio" },
    required_prefabs = {},
    set_pieces = {},
})

AddLevel(G.LEVELTYPE.SURVIVAL, {
    id = "STORY_STUDIO",
    name = "剧情片场",
    desc = "拍剧情用的小地图：空旷草地、树林和草原，没有道路、布景、Boss 和袭击。",
    location = "forest",
    version = 4,
    overrides = {
        task_set = "story_studio",
        start_location = "story_studio",
        world_size = "small",
        roads = "never",
        specialevent = "none",  -- 不跟随节日活动（万圣节南瓜、传送门装饰等）

        butterfly = "never",
        rabbits = "never",

        hounds = "never",
        deerclops = "never",
        bearger = "never",
        goosemoose = "never",
        deciduousmonster = "never",
        liefs = "never",
        krampus = "never",
        spiderqueen = "never",
        hunt = "never",
        penguins = "never",
        birds = "never",
        perd = "never",
        meteorshowers = "never",
        wildfires = "never",
        frograin = "never",
    },
    required_setpieces = {},
    numrandom_set_pieces = 0,
    random_set_pieces = {},
})
