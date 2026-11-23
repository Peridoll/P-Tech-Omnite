lib.callback.register('ptech_omnite_garages:authorize',function(src)
    return (exports.ox_inventory:GetItemCount(src,Config.toolItem) or 0)>0
end)
