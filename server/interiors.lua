local ROUTING_BUCKET_OFFSET <const> = 1000
local inside = {}

lib.callback.register('hw_garage:enterInterior', function(source, type)
    local player = Framework.getPlayerFromId(source)
    
    if not player then return end

    local bucketId = ROUTING_BUCKET_OFFSET + source
    inside[source] = true

    SetPlayerRoutingBucket(source, bucketId)
    SetRoutingBucketPopulationEnabled(bucketId, false)
    if Config.Debug then
        print("^0[^1DEBUG^0] ^5Player: ^3" .. source .. "^5 entered the garage exterior^0")
    end

    local vehicles = MySQL.query.await(Queries.getStoredGarage, { player:getIdentifier(), type })
    return vehicles
end)

RegisterNetEvent('hw_garage:exitInterior', function()
    local source = source

    if inside[source] then
        SetPlayerRoutingBucket(source, 0)
        if Config.Debug then
            print("^0[^1DEBUG^0] ^5Player: ^3" .. source .. "^5 left the garage exterior^0")
        end
        inside[source] = false
    end
end)