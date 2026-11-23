OmniteSeatExit={}
function OmniteSeatExit.find(seat,ped,active)
    local options=Config.Seating.exitSearch
    local minimum=GetModelDimensions(GetEntityModel(ped))
    local reference=seat.returnCoords or seat.sitCoords
    local floor=reference.z+minimum.z
    local function result(handle)
        local deadline=GetGameTimer()+options.probeTimeout
        repeat
            Wait(0)
            if not active() then return end
            local status,hit,point,normal=GetShapeTestResult(handle)
            if status==2 then return hit==true or hit==1,point,normal end
            if status==0 then return end
        until GetGameTimer()>=deadline
    end
    local function check(x,y,heading)
        local hit,point,normal=result(StartShapeTestRay(x,y,floor+0.45,x,y,floor-0.6,17,ped,7))
        if not hit or not normal or normal.z<0.7 or math.abs(point.z-floor)>0.4 then return end
        local wall=result(StartShapeTestRay(seat.sitCoords.x,seat.sitCoords.y,point.z+1.4,x,y,point.z+1.4,19,ped,7))
        if wall~=false then return end
        local blocked=result(StartShapeTestCapsule(x,y,point.z+0.4,x,y,point.z+1.5,0.3,23,ped,7))
        if blocked~=false then return end
        return {coords=vec3(x,y,point.z-minimum.z),heading=heading}
    end
    for _,distance in ipairs(options.distances) do
        for _,angle in ipairs({0,90,-90,180}) do
            if not active() then return end
            local heading=(seat.heading+angle)%360
            local radians=math.rad(heading)
            local candidate=check(seat.sitCoords.x-math.sin(radians)*distance,seat.sitCoords.y+math.cos(radians)*distance,heading)
            if candidate then return candidate end
        end
    end
    if active() and seat.returnCoords then return check(reference.x,reference.y,seat.returnHeading or seat.heading) end
end
