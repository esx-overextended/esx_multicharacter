if not ESX.GetConfig().Multichar then return end

local DB_TABLES = { users = "identifier" }
local SLOTS = Config.Slots or 4
local PREFIX = Config.Prefix or "char"
local PRIMARY_IDENTIFIER = ESX.GetConfig().Identifier or GetConvar("sv_lan", "") == "true" and "ip" or "license"
local DATABASE, isDatabaseConnected, isDatabaseFound = nil, false, false
local oneSyncState = GetConvar("onesync", "off"):lower()
local awaitingRegistration = {}

do
    local connectionString = GetConvar("mysql_connection_string", "")

    if connectionString:find("mysql://") then
        connectionString = connectionString:sub(9, -1)
        DATABASE = connectionString:sub(connectionString:find("/")+1, -1):gsub("[%?]+[%w%p]*$", "")
        isDatabaseFound = true
    elseif connectionString ~= "" then
        connectionString = {string.strsplit(";", connectionString)} ---@diagnostic disable-line: cast-local-type

        for i = 1, #connectionString do
            local v = connectionString[i]

            if v:lower():match("database") then
                DATABASE = v:sub(10, #v)
                isDatabaseFound = true
                break
            end
        end
    end
end

if not isDatabaseFound then
    return error("UNABLE TO START *MULTICHARACTER* - UNABLE TO DETERMINE DATABASE FROM mysql_connection_string", 0)
end

if next(ESX.Players) then
    local players = table.clone(ESX.Players)
    ESX.Players = {}

    for _, xPlayer in pairs(players) do
        ESX.Players[ESX.GetIdentifier(xPlayer.source)] = true
    end
else
    ESX.Players = {}
end

local function setupCharacters(source)
    while not isDatabaseConnected do Wait(1000) end

    local characters
    local identifier = ESX.GetIdentifier(source)
    ESX.Players[identifier] = true

    local slots = MySQL.scalar.await("SELECT slots FROM multicharacter_slots WHERE identifier = ?", { identifier }) or SLOTS
    local result = MySQL.query.await("SELECT identifier, accounts, job, job_grade, firstname, lastname, dateofbirth, sex, skin, disabled FROM users WHERE identifier LIKE ? LIMIT ?", { ("%s%%:%s"):format(PREFIX, identifier), slots })

    if result then
        local characterCount = #result
        characters = table.create(0, characterCount)

        for i = 1, characterCount do
            local data = result[i]
            local job, grade = data.job or "unemployed", tostring(data.job_grade)

            if ESX.DoesJobExist(job, grade) then
                grade = job ~= "unemployed" and ESX.Jobs[job].grades[grade]?.label or ""
                job = ESX.Jobs[job].label
            else
                job = ESX.Jobs["unemployed"]?.label
                grade = ""
            end

            local accounts = json.decode(data.accounts)
            local id = tonumber(string.sub(data.identifier, #PREFIX+1, string.find(data.identifier, ":")-1)) --[[@as number]]

            characters[id] = {
                id = id,
                bank = accounts.bank,
                money = accounts.money,
                job = job,
                job_grade = grade,
                firstname = data.firstname,
                lastname = data.lastname,
                dateofbirth = data.dateofbirth,
                skin = data.skin and json.decode(data.skin) or {},
                disabled = data.disabled,
                sex = data.sex == "m" and _U("male") or _U("female")
            }
        end
    end

    TriggerClientEvent("esx_multicharacter:SetupUI", source, characters, slots)
end

AddEventHandler("playerConnecting", function(_, _, deferrals)
    deferrals.defer()

    local identifier = ESX.GetIdentifier(source)

    if oneSyncState == "off" or oneSyncState == "legacy" then
        return deferrals.done(("[ESX] ESX Requires Onesync Infinity to work. This server currently has Onesync set to: %s"):format(oneSyncState))
    end

    if not isDatabaseFound then
        return deferrals.done(("[ESX Multicharacter] Cannot Find the server's mysql_connection_string. Please make sure it is correctly configured on the server.cfg"):format(oneSyncState))
    end

    if not isDatabaseConnected then
        return deferrals.done(("[ESX Multicharacter] ESX Cannot Connect to the database. Please make sure it is correctly configured on the server.cfg"):format(oneSyncState))
    end

    if not identifier then
        return deferrals.done(("Unable to retrieve player identifier.\nIdentifier type: %s"):format(PRIMARY_IDENTIFIER))
    end

    if not ESX.GetConfig().EnableDebug then
        if ESX.Players[identifier] then
            return deferrals.done(("[ESX Multicharacter] A player is already connected to the server with this identifier.\nYour identifier: %s:%s"):format(PRIMARY_IDENTIFIER, identifier))
        end

        return deferrals.done()
    end

    return deferrals.done()
end)

local function deleteCharacter(source, charid)
    local identifier = ("%s%s:%s"):format(PREFIX, charid, ESX.GetIdentifier(source))
    local query = "DELETE FROM %s WHERE %s = ?"
    local queries = {}
    local count = 0

    for table, column in pairs(DB_TABLES) do
        count += 1
        queries[count] = {query = query:format(table, column), values = {identifier}}
    end

    MySQL.transaction(queries, function(result)
        if result then
            print(("[^2INFO^7] Player ^5%s %s^7 has deleted a character ^5(%s)^7"):format(GetPlayerName(source), source, identifier))
            return setupCharacters(source)
        end

        error("\n^1Transaction failed while trying to delete "..identifier.."^0")
    end)
end

MySQL.ready(function()
    local length = 42 + #PREFIX
    local DB_COLUMNS = MySQL.query.await(("SELECT TABLE_NAME, COLUMN_NAME, CHARACTER_MAXIMUM_LENGTH FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = '%s' AND DATA_TYPE = 'varchar' AND COLUMN_NAME IN (?)"):format(DATABASE, length), { Config.ColumnsToModify })

    if DB_COLUMNS then
        local columns = {}
        local count = 0

        for i = 1, #DB_COLUMNS do
            local column = DB_COLUMNS[i]
            DB_TABLES[column.TABLE_NAME] = column.COLUMN_NAME

            if column?.CHARACTER_MAXIMUM_LENGTH ~= length then
                count += 1
                columns[column.TABLE_NAME] = column.COLUMN_NAME
            end
        end

        if next(columns) then
            local query = "ALTER TABLE `%s` MODIFY COLUMN `%s` VARCHAR(%s)"
            local queries, qCount = table.create(count, 0), 1

            queries[qCount] = {query = "SET FOREIGN_KEY_CHECKS = 0"}

            for k, v in pairs(columns) do
                qCount += 1
                queries[qCount] = {query = query:format(k, v, length)}
            end

            qCount += 1
            queries[qCount] = {query = "SET FOREIGN_KEY_CHECKS = 1"}

            if MySQL.transaction.await(queries) then
                print(("[^2INFO^7] Updated ^5%s^7 columns to use ^5VARCHAR(%s)^7"):format(count, length))
            else
                print(("[^2INFO^7] Unable to update ^5%s^7 columns to use ^5VARCHAR(%s)^7"):format(count, length))
            end
        end

        repeat Wait(1000) ESX.Jobs = ESX.GetJobs() until next(ESX.Jobs)

        isDatabaseConnected = true
    end
end)

RegisterNetEvent("esx_multicharacter:SetupCharacters", function()
    setupCharacters(source)
end)

RegisterNetEvent("esx_multicharacter:CharacterChosen", function(charid, isNew)
    if type(charid) == "number" and string.len(charid) <= 2 and type(isNew) == "boolean" then
        if isNew then
            awaitingRegistration[source] = charid
        else
            ESX.Players[ESX.GetIdentifier(source)] = true

            TriggerEvent("esx:onPlayerJoined", source, ("%s%s"):format(PREFIX, charid))
        end
    end
end)

AddEventHandler("esx_identity:completedRegistration", function(source, data)
    local charId = awaitingRegistration[source]
    awaitingRegistration[source] = nil
    ESX.Players[ESX.GetIdentifier(source)] = true

    TriggerEvent("esx:onPlayerJoined", source, ("%s%s"):format(PREFIX, charId), data)
end)

AddEventHandler("playerDropped", function()
    awaitingRegistration[source] = nil
    ESX.Players[ESX.GetIdentifier(source)] = nil
end)

RegisterNetEvent("esx_multicharacter:DeleteCharacter", function(charid)
    if Config.CanDelete and type(charid) == "number" and string.len(charid) <= 2 then
        deleteCharacter(source, charid)
    end
end)

if Config.Relog then
    RegisterNetEvent("esx_multicharacter:relog", function()
        TriggerEvent("esx:playerLogout", source)
    end)
end
