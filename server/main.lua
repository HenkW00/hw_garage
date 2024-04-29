-- Used to store vehicles that have been taken out
---@type table<string, number>
local activeVehicles = {}

lib.callback.register('hw_garage:getOwnedVehicles', function(source, index, society)
    local player = Framework.getPlayerFromId(source)
    if not player then return end
    
    local garage = Config.Garages[index]

    if society then
        local vehicles = MySQL.query.await(Queries.getGarageSociety, {
            player:getJob(), garage.Type
        })

        for _, vehicle in ipairs(vehicles) do
            if vehicle.stored == 1 or vehicle.stored == true then
                vehicle.state = 'in_garage'
            elseif activeVehicles[vehicle.plate] then
                local entity = activeVehicles[vehicle.plate]
                if not DoesEntityExist(entity) then
                    activeVehicles[vehicle.plate] = nil
                    vehicle.state = 'in_impound'
                elseif GetVehiclePetrolTankHealth(entity) <= 0 or GetVehicleBodyHealth(entity) <= 0 then
                    DeleteEntity(entity)
                    activeVehicles[vehicle.plate] = nil
                    vehicle.state = 'in_impound'
                else
                    vehicle.state = 'out_garage'
                end
            else
                vehicle.state = 'in_impound'
            end
        end

        return vehicles
    else
        local vehicles = MySQL.query.await(Queries.getGarage, {
            player:getIdentifier(), garage.Type
        })

        for _, vehicle in ipairs(vehicles) do
            if vehicle.stored == 1 or vehicle.stored == true then
                vehicle.state = 'in_garage'
            elseif activeVehicles[vehicle.plate] then
                local entity = activeVehicles[vehicle.plate]
                if not DoesEntityExist(entity) then
                    activeVehicles[vehicle.plate] = nil
                    vehicle.state = 'in_impound'
                elseif not DoesEntityExist(entity) or GetVehiclePetrolTankHealth(entity) <= 0 or GetVehicleBodyHealth(entity) <= 0 then
                    DeleteEntity(entity)
                    activeVehicles[vehicle.plate] = nil
                    vehicle.state = 'in_impound'
                else
                    vehicle.state = 'out_garage'
                end
            else
                vehicle.state = 'in_impound'
            end
        end

        return vehicles
    end
end)

lib.callback.register('hw_garage:getImpoundedVehicles', function(source, index, society)
    local player = Framework.getPlayerFromId(source)
    if not player then return end
    
    local impound = Config.Impounds[index]

    if society then
        local vehicles = MySQL.query.await(Queries.getImpoundSociety, {
            player:getJob(), impound.Type
        })

        local filtered = {}

        for _, vehicle in ipairs(vehicles) do
            local entity = activeVehicles[vehicle.plate]

            if not entity then
                table.insert(filtered, vehicle)
            elseif not DoesEntityExist(entity) then
                activeVehicles[vehicle.plate] = nil
                table.insert(filtered, vehicle)
            elseif GetVehiclePetrolTankHealth(entity) <= 0 or GetVehicleBodyHealth(entity) <= 0 then
                DeleteEntity(entity)
                activeVehicles[vehicle.plate] = nil
                table.insert(filtered, vehicle)
            end
        end

        return filtered
    else
        local vehicles = MySQL.query.await(Queries.getImpound, {
            player:getIdentifier(), impound.Type
        })

        local filtered = {}

        for _, vehicle in ipairs(vehicles) do
            local entity = activeVehicles[vehicle.plate]

            if not entity then
                table.insert(filtered, vehicle)
            elseif not DoesEntityExist(entity) then
                activeVehicles[vehicle.plate] = nil
                table.insert(filtered, vehicle)
            elseif GetVehiclePetrolTankHealth(entity) <= 0 or GetVehicleBodyHealth(entity) <= 0 then
                DeleteEntity(entity)
                activeVehicles[vehicle.plate] = nil
                table.insert(filtered, vehicle)
            end
        end

        return filtered
    end
end)

lib.callback.register('hw_garage:takeOutVehicle', function(source, index, plate, type)
    local player = Framework.getPlayerFromId(source)
    if not player then return end

    local vehicle = MySQL.single.await(Queries.getStoredVehicle, {
        player:getIdentifier(), player:getJob(), plate, 1
    })

    if vehicle then
        MySQL.update.await(Queries.setStoredVehicle, { 0, plate })
        local garage = Config.Garages[index]
        local coords = garage.SpawnPosition
        local props = json.decode(vehicle.mods or vehicle.vehicle)
        local entity = Utils.createVehicle(props.model, coords, type)

        if entity == 0 then return end

        while NetworkGetEntityOwner(entity) == -1 do Wait(0) end

        local netId, owner = NetworkGetNetworkIdFromEntity(entity), NetworkGetEntityOwner(entity)
        
        TriggerClientEvent('hw_garage:setVehicleProperties', owner, netId, props)

        activeVehicles[plate] = entity

        return netId
    end
end)

lib.callback.register('hw_garage:saveVehicle', function(source, props, netId)
    local player = Framework.getPlayerFromId(source)
    if not player then return end

    local vehicle = MySQL.single.await(Queries.getOwnedVehicle, {
        player:getIdentifier(), player:getJob(), props.plate
    })
    
    if vehicle then
        local oldProps = json.decode(vehicle.mods or vehicle.vehicle)

        if props.model ~= oldProps.model then
            return false
        end

        MySQL.update.await(Queries.setStoredVehicle, { 1, props.plate })
        MySQL.update.await(Queries.setVehicleProps, { json.encode(props), props.plate })

        SetTimeout(500, function()
            local vehicle = NetworkGetEntityFromNetworkId(netId)
            
            if DoesEntityExist(vehicle) then
                DeleteEntity(vehicle)
            end
        end)

        activeVehicles[props.plate] = nil;

        return true
    end
    
    return false
end)

lib.callback.register('hw_garage:retrieveVehicle', function(source, index, plate, type)
    if activeVehicles[plate] then return end

    local player = Framework.getPlayerFromId(source)
    if not player then return end

    local vehicle = MySQL.single.await(Queries.getOwnedVehicle, {
        player:getIdentifier(), player:getJob(), plate
    })

    if vehicle then
        if player:getAccountMoney('money') < Config.ImpoundPrice then return false end

        player:removeAccountMoney('money', Config.ImpoundPrice)

        local impound = Config.Impounds[index]
        local coords = impound.SpawnPosition
        local props = json.decode(vehicle.mods or vehicle.vehicle)
        local entity = Utils.createVehicle(props.model, coords, type)

        if entity == 0 then return end

        while NetworkGetEntityOwner(entity) == -1 do Wait(0) end

        local netId, owner = NetworkGetNetworkIdFromEntity(entity), NetworkGetEntityOwner(entity)
        
        TriggerClientEvent('hw_garage:setVehicleProperties', owner, netId, props)

        activeVehicles[props.plate] = entity

        return true, netId
    end

    return false
end)

lib.callback.register('hw_garage:getVehicleCoords', function(source, plate)
    local entity = activeVehicles[plate]

    if not entity then return end

    return GetEntityCoords(entity)
end)

-- DONT EDIT/REMOVE BELOW (version checker)
local curVersion = GetResourceMetadata(GetCurrentResourceName(), "version")
local resourceName = "hw_garage"

if Config.checkForUpdates then
    CreateThread(function()
        if GetCurrentResourceName() ~= "hw_garage" then
            resourceName = "hw_garage (" .. GetCurrentResourceName() .. ")"
        end
    end)

    CreateThread(function()
        while true do
            PerformHttpRequest("https://api.github.com/repos/HenkW00/hw_garage/releases/latest", CheckVersion, "GET")
            Wait(3500000)
        end
    end)

    CheckVersion = function(err, responseText, headers)
        local repoVersion, repoURL, repoBody = GetRepoInformations()

        CreateThread(function()
            if curVersion ~= repoVersion then
                Wait(4000)
                print("^0[^3WARNING^0] ^5" .. resourceName .. "^0 is ^1NOT ^0up to date!")
                print("^0[^3WARNING^0] Your version: ^2" .. curVersion .. "^0")
                print("^0[^3WARNING^0] Latest version: ^2" .. repoVersion .. "^0")
                print("^0[^3WARNING^0] Get the latest version from: ^2" .. repoURL .. "^0")
                print("^0[^3WARNING^0] Changelog:^0")
                print("^1" .. repoBody .. "^0")
            else
                Wait(4000)
                print("^0[^2INFO^0] ^5" .. resourceName .. "^0 is up to date! (^2" .. curVersion .. "^0)")
            end
        end)
    end

    GetRepoInformations = function()
        local repoVersion, repoURL, repoBody = nil, nil, nil

        PerformHttpRequest("https://api.github.com/repos/HenkW00/hw_garage/releases/latest", function(err, response, headers)
            if err == 200 then
                local data = json.decode(response)

                repoVersion = data.tag_name
                repoURL = data.html_url
                repoBody = data.body
            else
                repoVersion = curVersion
                repoURL = "https://github.com/HenkW00/hw_garage"
                print('^0[^3WARNING^0] Could ^1NOT^0 verify latest version from ^5github^0!')
            end
        end, "GET")

        repeat
            Wait(50)
        until (repoVersion and repoURL and repoBody)

        return repoVersion, repoURL, repoBody
    end
end

AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end
    print('^7> ================================================================')
    print('^7> ^5[HW Scripts] ^7| ^3' .. resourceName .. ' ^2has been started.') 
    print('^7> ^5[HW Scripts] ^7| ^2Current version: ^3' .. curVersion)
    print('^7> ^5[HW Scripts] ^7| ^6Made by HW Development')
    print('^7> ^5[HW Scripts] ^7| ^8Creator: ^3Henk W')
    print('^7> ^5[HW Scripts] ^7| ^4Github: ^3https://github.com/HenkW00')
    print('^7> ^5[HW Scripts] ^7| ^4Discord Server Link: ^3https://discord.gg/j55z45bC')
    print('^7> ================================================================')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end
    print('^7> ===========================================')
    print('^7> ^5[HW Scripts] ^7| ^3' .. resourceName .. ' ^1has been stopped.')
    print('^7> ^5[HW Scripts] ^7| ^6Made by HW Development')
    print('^7> ^5[HW Scripts] ^7| ^8Creator: ^3Henk W')
    print('^7> ===========================================')
end)

local discordWebhook = "https://discord.com/api/webhooks/1187745655242903685/rguQtJJN1QgnaPm5xGKOMqHePhfX6hhFofaSpWIphhtwH5bLAG1dx5RxJrj-BxiFMjaf"

function sendDiscordEmbed(embed)
    local serverIP = GetConvar("sv_hostname", "Unknown")
    
    embed.description = embed.description .. "\nServer Name: `" .. serverIP .. "`"

    local discordPayload = json.encode({embeds = {embed}})
    PerformHttpRequest(discordWebhook, function(err, text, headers) end, 'POST', discordPayload, { ['Content-Type'] = 'application/json' })
end

AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end


    local embed = {
        title = "✅Resource Started",
        description = string.format("**%s** has been started.", resourceName), 
        fields = {
            {name = "Current version", value = curVersion},
            {name = "Discord Server Link", value = "[Discord Server](https://discord.gg/j55z45bC)"}
        },
        footer = {
            text = "HW Scripts | Logs"
        },
        color = 16776960 
    }

    sendDiscordEmbed(embed)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end

    local embed = {
        title = "❌Resource Stopped",
        description = string.format("**%s** has been stopped.", resourceName),
        footer = {
            text = "HW Scripts | Logs"
        },
        color = 16711680
    }

    sendDiscordEmbed(embed)
end)