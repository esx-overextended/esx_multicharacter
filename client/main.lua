if not ESX.GetConfig().Multichar then return end

local playerId = PlayerId()
local mp_m_freemode_01, mp_f_freemode_01 = `mp_m_freemode_01`, `mp_f_freemode_01`
local hidingPlayers, canRelog, cam, spawned = false, true, nil, nil
local setupCharacter, characterOptions, characterDeleteConfirmation, selectCharacterMenu
local Characters = {}

CreateThread(function()
    while true do
        if NetworkIsPlayerActive(playerId) then
            exports.spawnmanager:setAutoSpawn(false)

            DoScreenFadeOut(1000)

            TriggerEvent("esx_multicharacter:SetupCharacters")
            break
        end

        Wait(500)
    end
end)

local function startLoop()
    if hidingPlayers then return end

    hidingPlayers = true

    MumbleSetVolumeOverride(playerId, 0.0)

    CreateThread(function()
        local keysToKeepEnabled = { 18, 27, 172, 173, 174, 175, 176, 177, 187, 188, 191, 201, 108, 109 }
        local playerPedId

        while hidingPlayers do
            playerPedId = PlayerPedId()

            SetEntityVisible(playerPedId, false, false)
            SetLocalPlayerVisibleLocally(true)
            SetPlayerInvincible(playerId, true)

            ThefeedHideThisFrame()
            HideHudComponentThisFrame(11)
            HideHudComponentThisFrame(12)
            HideHudComponentThisFrame(21)
            HideHudAndRadarThisFrame()

            DisableAllControlActions(0)

            for i = 1, #keysToKeepEnabled do
                EnableControlAction(0, keysToKeepEnabled[i], true)
            end

            local vehicles = GetGamePool("CVehicle")
            for i = 1, #vehicles do
                SetEntityLocallyInvisible(vehicles[i])
            end

            Wait(0)
        end

        MumbleSetVolumeOverride(playerId, -1.0)
        SetEntityVisible(playerPedId, true, false)
        SetPlayerInvincible(playerId, false)
        FreezeEntityPosition(playerPedId, false)

        Wait(10000)

        canRelog = true
    end)

    CreateThread(function()
        local hiddenPlayers = {}

        while hidingPlayers do
            local players = GetActivePlayers()

            for i = 1, #players do
                local player = players[i]

                if player ~= playerId and not hiddenPlayers[player] then
                    hiddenPlayers[player] = true

                    NetworkConcealPlayer(player, true, true)
                end
            end

            Wait(500)
        end

        for player in pairs(hiddenPlayers) do
            NetworkConcealPlayer(player, false, false)
        end
    end)
end

function setupCharacter(index)
    if not spawned then
        exports.spawnmanager:spawnPlayer({
            x = Config.Spawn.x,
            y = Config.Spawn.y,
            z = Config.Spawn.z,
            heading = Config.Spawn.w,
            model = Characters[index].model or mp_m_freemode_01,
            skipFade = true
        }, function()
            canRelog = false

            if Characters[index] then
                local skin = Characters[index].skin or Config.Default

                if not Characters[index].model then
                    if Characters[index].sex == _U("female") then skin.sex = 1 else skin.sex = 0 end
                end

                TriggerEvent("skinchanger:loadSkin", skin)
            end

            DoScreenFadeIn(1000)
        end)

        repeat Wait(200) until not IsScreenFadedOut()
    elseif Characters[index] and Characters[index].skin then
        if Characters[spawned] and Characters[spawned].model then
            RequestModel(Characters[index].model)

            while not HasModelLoaded(Characters[index].model) do
                RequestModel(Characters[index].model)
                Wait(500)
            end

            SetPlayerModel(playerId, Characters[index].model)
            SetModelAsNoLongerNeeded(Characters[index].model)
        end

        TriggerEvent("skinchanger:loadSkin", Characters[index].skin)
    end

    local playerPedId = PlayerPedId()
    spawned = index

    FreezeEntityPosition(playerPedId, true)
    SetPedAoBlobRendering(playerPedId, true)
    SetEntityAlpha(playerPedId, 255, false)

    SendNUIMessage({
        action = "openui",
        character = Characters[spawned]
    })
end

function characterOptions(characters, slots, selectedCharacter)
    local elements = {
        {
            title = _U("character", characters[selectedCharacter.value].firstname .. " " .. characters[selectedCharacter.value].lastname),
            icon = "fa-regular fa-user",
            unselectable = true
        },
        {
            title = _U("return"),
            unselectable = false,
            icon = "fa-solid fa-arrow-left",
            description = _U("return_description"),
            action = "return"
        }
    }

    if characters[selectedCharacter.value].disabled then
        elements[3] = {
            title = _U("char_disabled"),
            value = selectedCharacter.value,
            icon = "fa-solid fa-xmark",
            description = _U("char_disabled_description"),
        }
    else
        elements[3] = {
            title = _U("char_play"),
            description = _U("char_play_description"),
            icon = "fa-solid fa-play",
            action = "play",
            value = selectedCharacter.value
        }
    end

    if Config.CanDelete then
        elements[4] = {
            title = _U("char_delete"),
            icon = "fa-solid fa-xmark",
            description = _U("char_delete_description"),
            action = "delete",
            value = selectedCharacter.value
        }
    end

    ESX.OpenContext("left", elements, function(_, element)
        if element.action == "play" then
            SendNUIMessage({
                action = "closeui"
            })

            ESX.CloseContext()

            TriggerServerEvent("esx_multicharacter:CharacterChosen", element.value, false)
        elseif element.action == "delete" then
            characterDeleteConfirmation(characters, slots, selectedCharacter, element.value)
        elseif element.action == "return" then
            selectCharacterMenu(characters, slots)
        end
    end, nil, false)
end

function characterDeleteConfirmation(characters, slots, selectedCharacter, value)
    local elements = {
        {
            title = _U("char_delete_confirmation"),
            icon = "fa-solid fa-users",
            description = _U("char_delete_confirmation_description"),
            unselectable = true
        },
        {
            title = _U("char_delete"),
            icon = "fa-solid fa-xmark",
            description = _U("char_delete_yes_description"),
            action = "delete",
            value = value
        },
        {
            title = _U("return"),
            unselectable = false,
            icon = "fa-solid fa-arrow-left",
            description = _U("char_delete_no_description"),
            action = "return"
        }
    }

    ESX.OpenContext("left", elements, function(_, element)
        if element.action == "delete" then
            spawned = false

            ESX.CloseContext()

            TriggerServerEvent("esx_multicharacter:DeleteCharacter", element.value)
        elseif element.action == "return" then
            characterOptions(characters, slots, selectedCharacter)
        end
    end, nil, false)
end

function selectCharacterMenu(characters, slots)
    local firstCharacter = next(characters)
    local elements = {
        {
            title = _U("select_char"),
            icon = "fa-solid fa-users",
            description = _U("select_char_description"),
            unselectable = true
        }
    }

    for _, v in pairs(characters) do
        if not v.model and v.skin then
            if v.skin.model then
                v.model = v.skin.model
            elseif v.skin.sex == 1 then
                v.model = mp_f_freemode_01
            else
                v.model = mp_m_freemode_01
            end
        end

        if not spawned then setupCharacter(firstCharacter) end

        elements[#elements + 1] = { title = ("%s %s"):format(v.firstname, v.lastname), icon = "fa-regular fa-user", value = v.id }
    end

    if #elements - 1 < slots then
        elements[#elements + 1] = { title = _U("create_char"), icon = "fa-solid fa-plus", value = (#elements + 1), new = true }
    end

    ESX.OpenContext("left", elements, function(_, element)
        if element.new then
            local slot

            for i = 1, slots do
                if not characters[i] then
                    slot = i
                    break
                end
            end

            ESX.CloseContext()

            TriggerServerEvent("esx_multicharacter:CharacterChosen", slot, true)
            TriggerEvent("esx_identity:showRegisterIdentity")

            local playerPedId = PlayerPedId()

            SetPedAoBlobRendering(playerPedId, false)
            SetEntityAlpha(playerPedId, 0, false)

            SendNUIMessage({
                action = "closeui"
            })
        else
            local playerPedId = PlayerPedId()

            SetPedAoBlobRendering(playerPedId, true)
            ResetEntityAlpha(playerPedId)

            characterOptions(characters, slots, element)

            setupCharacter(element.value)
        end
    end, nil, false)
end

RegisterNetEvent("esx_multicharacter:SetupCharacters")
AddEventHandler("esx_multicharacter:SetupCharacters", function()
    ESX.PlayerLoaded = false
    ESX.PlayerData = {}

    local playerPedId = PlayerPedId()
    spawned = false
    cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)

    SetEntityCoords(playerPedId, Config.Spawn.x, Config.Spawn.y, Config.Spawn.z, true, false, false, false)
    SetEntityHeading(playerPedId, Config.Spawn.w)

    DoScreenFadeOut(1000)

    local offset = GetOffsetFromEntityInWorldCoords(playerPedId, 0, 1.7, 0.4)

    SetCamActive(cam, true)
    RenderScriptCams(true, false, 1, true, true)
    SetCamCoord(cam, offset.x, offset.y, offset.z)
    PointCamAtCoord(cam, Config.Spawn.x, Config.Spawn.y, Config.Spawn.z + 1.3)

    startLoop()

    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

    TriggerEvent("esx:loadingScreenOff")
    TriggerServerEvent("esx_multicharacter:SetupCharacters")
end)

RegisterNetEvent("esx_multicharacter:SetupUI")
AddEventHandler("esx_multicharacter:SetupUI", function(data, slots)
    DoScreenFadeOut(1000)

    local character = next(data)
    Characters = data
    slots = slots

    exports.spawnmanager:forceRespawn()

    if not character then
        SendNUIMessage({
            action = "closeui"
        })

        exports.spawnmanager:spawnPlayer({
            x = Config.Spawn.x,
            y = Config.Spawn.y,
            z = Config.Spawn.z,
            heading = Config.Spawn.w,
            model = mp_m_freemode_01,
            skipFade = true
        }, function()
            canRelog = false

            DoScreenFadeIn(1000)

            local playerPedId = PlayerPedId()

            SetPedAoBlobRendering(playerPedId, false)
            SetEntityAlpha(playerPedId, 0, false)

            TriggerServerEvent("esx_multicharacter:CharacterChosen", 1, true)
            TriggerEvent("esx_identity:showRegisterIdentity")
        end)
    else
        selectCharacterMenu(Characters, slots)
    end
end)

AddEventHandler("esx:playerLoaded", function(playerData, isNew, skin)
    local spawn = playerData.coords or Config.Spawn

    if isNew or not skin or #skin == 1 then
        local finished = false
        local model = (type(playerData.sex) == "string" and playerData.sex:lower() == "f") and mp_f_freemode_01 or mp_m_freemode_01
        skin = Config.Default[playerData.sex]
        skin.sex = model == mp_m_freemode_01 and 0 or 1

        RequestModel(model)

        while not HasModelLoaded(model) do
            RequestModel(model)
            Wait(500)
        end

        SetPlayerModel(playerId, model)
        SetModelAsNoLongerNeeded(model)

        TriggerEvent("skinchanger:loadSkin", skin, function()
            local playerPedId = PlayerPedId()

            SetPedAoBlobRendering(playerPedId, true)
            ResetEntityAlpha(playerPedId)

            TriggerEvent("esx_skin:openSaveableMenu", function()
                finished = true
            end, function()
                finished = true
            end)
        end)

        repeat Wait(200) until finished
    end

    DoScreenFadeOut(1000)

    SetCamActive(cam, false)
    RenderScriptCams(false, false, 0, true, true)
    cam = nil

    local playerPedId = PlayerPedId()

    FreezeEntityPosition(playerPedId, true)
    SetEntityCoordsNoOffset(playerPedId, spawn.x, spawn.y, spawn.z, false, false, false)
    SetEntityHeading(playerPedId, spawn.heading)

    if not isNew then TriggerEvent("skinchanger:loadSkin", skin or Characters[spawned].skin) end

    DoScreenFadeIn(1000)

    repeat Wait(200) until not IsScreenFadedOut()

    TriggerServerEvent("esx:onPlayerSpawn")
    TriggerEvent("esx:onPlayerSpawn")
    TriggerEvent("playerSpawned")
    TriggerEvent("esx:restoreLoadout")

    Characters, hidingPlayers, canRelog = {}, false, true
end)

AddEventHandler("esx:onPlayerLogout", function()
    DoScreenFadeOut(1000)

    spawned = false

    TriggerEvent("esx_multicharacter:SetupCharacters")
    TriggerEvent("esx_skin:resetFirstSpawn")
end)

if Config.Relog then
    RegisterCommand("relog", function()
        if canRelog then
            canRelog = false

            TriggerServerEvent("esx_multicharacter:relog")
        end
    end, false)
end
