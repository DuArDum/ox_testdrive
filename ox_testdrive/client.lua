local ESX = exports['es_extended']:getSharedObject()

local spawnedVehicle = nil
local testActive = false

local pendingVehicle = nil
local pendingMods = nil

-------------------------------------------------
-- PAYMENT RESPONSE
-------------------------------------------------

RegisterNetEvent('testdrive:paid', function(success)

    if not success then
        lib.notify({
            title = 'Testkörning',
            description = 'Du har inte råd.',
            type = 'error'
        })
        return
    end

    if pendingVehicle then
        StartTestDrive(pendingVehicle, pendingMods)
    end

end)

-------------------------------------------------
-- NPC SPAWN
-------------------------------------------------

CreateThread(function()

    local model = Config.Ped.model
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    local ped = CreatePed(0, model, Config.Ped.coords.xyz, Config.Ped.coords.w, false, true)

    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    if Config.Ped.scenario then
        TaskStartScenarioInPlace(ped, Config.Ped.scenario, 0, true)
    end

    exports.ox_target:addLocalEntity(ped, {
        {
            icon = 'fa-solid fa-car',
            label = 'Testkör fordon',
            onSelect = function()
                OpenCategoryMenu()
            end
        }
    })

end)

-------------------------------------------------
-- MENUS
-------------------------------------------------

function OpenCategoryMenu()

    local options = {}

    for category, _ in pairs(Config.Categories) do
        table.insert(options, {
            title = category,
            arrow = true,
            onSelect = function()
                OpenVehicleMenu(category)
            end
        })
    end

    lib.registerContext({
        id = 'vehicle_categories',
        title = 'Fordonskategorier',
        options = options
    })

    lib.showContext('vehicle_categories')
end


function OpenVehicleMenu(category)

    local options = {}

    for _, vehicle in ipairs(Config.Categories[category]) do

        local price = vehicle.price or Config.DefaultPrice

        local desc = string.format(
            "Top Speed: %s\nHP: %s\nDrive: %s\nPris: $%s",
            vehicle.info.topSpeed,
            vehicle.info.horsepower,
            vehicle.info.drivetrain,
            price
        )

        table.insert(options, {
            title = vehicle.label,
            description = desc,
            icon = vehicle.image,
            onSelect = function()
                ConfirmTest(vehicle)
            end
        })
    end

    lib.registerContext({
        id = 'vehicle_list',
        title = category,
        menu = 'vehicle_categories',
        options = options
    })

    lib.showContext('vehicle_list')
end

-------------------------------------------------
-- CONFIRM + CUSTOMIZATION
-------------------------------------------------

function ConfirmTest(vehicle)

    local alert = lib.alertDialog({
        header = 'Testkörning',
        content = ('Vill du testköra %s?'):format(vehicle.label),
        centered = true,
        cancel = true
    })

    if alert ~= 'confirm' then return end

    local input = lib.inputDialog('Anpassa fordon', {

        {
            type = 'color',
            label = 'Primär färg',
            default = '#ffffff'
        },

        {
            type = 'color',
            label = 'Sekundär färg',
            default = '#000000'
        },

        {
            type = 'slider',
            label = 'Motor uppgradering',
            min = 0,
            max = 4,
            default = 0
        }

    })

    if not input then return end

    -- STARTA TEST DIREKT
    StartTestDrive(vehicle, input)

end


-------------------------------------------------
-- APPLY MODS
-------------------------------------------------

local function HexToRGB(hex)
    hex = hex:gsub("#","")
    return tonumber("0x"..hex:sub(1,2)),
           tonumber("0x"..hex:sub(3,4)),
           tonumber("0x"..hex:sub(5,6))
end


function ApplyMods(vehicle, input)

    if not input then return end

    SetVehicleModKit(vehicle, 0)

    local r1,g1,b1 = HexToRGB(input[1])
    local r2,g2,b2 = HexToRGB(input[2])

    SetVehicleCustomPrimaryColour(vehicle, r1,g1,b1)
    SetVehicleCustomSecondaryColour(vehicle, r2,g2,b2)

    local level = input[3] or 0

    SetVehicleMod(vehicle, 11, level)
    SetVehicleMod(vehicle, 12, level)
    SetVehicleMod(vehicle, 13, level)

    ToggleVehicleMod(vehicle, 18, true)
end

-------------------------------------------------
-- START TEST
-------------------------------------------------

function StartTestDrive(data, input)

    if testActive then return end
    testActive = true

    local ped = PlayerPedId()

    DoScreenFadeOut(1000)
    Wait(1000)

    RequestModel(data.model)
    while not HasModelLoaded(data.model) do Wait(0) end

    spawnedVehicle = CreateVehicle(data.model, Config.TestSpawn.xyz, Config.TestSpawn.w, true, false)

    SetVehicleNumberPlateText(spawnedVehicle, "TEST")

    ApplyMods(spawnedVehicle, input)

    TaskWarpPedIntoVehicle(ped, spawnedVehicle, -1)

    DoScreenFadeIn(1000)

    StartProgress()

end

-------------------------------------------------
-- PROGRESS TIMER
-------------------------------------------------

function StartProgress()
    CreateThread(function()
        local startTime = GetGameTimer()
        local duration = Config.TestTime * 1000

        while testActive do
            local elapsed = GetGameTimer() - startTime
            local remaining = math.max(0, duration - elapsed)
            local label = ('Tid kvar: %s - /endtest för att avsluta'):format(math.ceil(remaining / 1000))

            -- Visa countdown med textUI
            lib.showTextUI(label)
            Wait(500)

            if remaining <= 0 then
                break
            end
        end

        lib.hideTextUI()

        if testActive then
            EndTestDrive()
        end
    end)
end



-------------------------------------------------
-- END TEST
-------------------------------------------------

function EndTestDrive()
    if not testActive and not spawnedVehicle then return end

    testActive = false

    local ped = PlayerPedId()

    DoScreenFadeOut(1000)
    Wait(1000)

    -- Radera bilen om den finns
    if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
        DeleteEntity(spawnedVehicle)
        spawnedVehicle = nil
    end

    -- Flytta spelaren tillbaka
    if Config.ReturnCoords then
        SetEntityCoords(ped, Config.ReturnCoords.xyz)
        SetEntityHeading(ped, Config.ReturnCoords.w)
    end

    -- Dölj countdown / textUI
    lib.hideTextUI()

    DoScreenFadeIn(1000)

    lib.notify({
        title = 'Testkörning',
        description = 'Testkörningen är slut!',
        type = 'success'
    })
end


-------------------------------------------------
-- COMMAND
-------------------------------------------------

RegisterCommand('endtest', function()
    if not testActive then
        lib.notify({
            title = 'Testkörning',
            description = 'Du testkör inget fordon.',
            type = 'error'
        })
        return
    end

    -- Stänger av test
    testActive = false
    EndTestDrive()
end)



