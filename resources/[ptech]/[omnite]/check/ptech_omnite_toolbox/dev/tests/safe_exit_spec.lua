local testClock,blocked,mode=0,0,'first_blocked'
function GetEntityModel() return 1 end
function GetModelDimensions() return vec3(-0.3,-0.3,-1),vec3(0.3,0.3,1) end
function GetGameTimer() return testClock end
function Wait() testClock=testClock+1 end
function StartShapeTestRay(x,y,z,ex,ey,ez) return {kind=z==ez and 'path' or 'floor',x=x,y=y} end
function StartShapeTestCapsule(x,y) return {kind='body',x=x,y=y} end
function GetShapeTestResult(handle)
    if handle.kind=='path' then return 2,mode=='wall' end
    if handle.kind=='floor' then
        if mode=='no_floor' then return 2,false end
        return 2,true,vec3(handle.x,handle.y,0),vec3(0,0,1)
    end
    blocked=blocked+1
    return 2,mode=='first_blocked' and blocked==1
end
function runSafeExitSpecs()
    local seat={sitCoords=vec3(0,0,1),returnCoords=vec3(0,0,1),returnHeading=0,heading=0}
    local point=OmniteSeatExit.find(seat,1,function() return true end)
    assert(point and point.coords.x < -0.8 and math.abs(point.coords.y)<0.01 and point.coords.z==1,'occupied front skipped in favor of free side with standing clearance')
    mode='no_floor'
    assert(not OmniteSeatExit.find(seat,1,function() return true end),'no destination without a verified floor')
    mode='clear'
    assert(not OmniteSeatExit.find(seat,1,function() return false end),'cancelled search cannot choose destination')
    mode='wall'
    assert(not OmniteSeatExit.find(seat,1,function() return true end),'standing space across a wall is rejected')
end
