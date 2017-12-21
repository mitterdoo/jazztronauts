AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
 
include("shared.lua")

ENT.ShadowControl = {}
ENT.ShadowControl.secondstoarrive  = 0.0000001
ENT.ShadowControl.pos              = Vector(0, 0, 0)
ENT.ShadowControl.angle            = Angle(0, 0, 0)
ENT.ShadowControl.maxspeed         = 1000000000000
ENT.ShadowControl.maxangular       = 1000000
ENT.ShadowControl.maxspeeddamp     = 10000
ENT.ShadowControl.maxangulardamp   = 1000000
ENT.ShadowControl.dampfactor       = 1
ENT.ShadowControl.teleportdistance = 0
ENT.ShadowControl.deltatime = deltatime

ENT.TravelTime = 1.5
ENT.SkidPlayed = false
ENT.EngineOffPlayed = false

util.AddNetworkString("jazz_bus_launcheffects")

sound.Add( {
	name = "jazz_bus_accelerate",
	channel = CHAN_AUTO,
	volume = 1.0,
	level = 80,
	pitch = { 95, 110 },
	sound = "vehicles/v8/v8_turbo_on_loop1.wav"
} )

sound.Add( {
	name = "jazz_bus_accelerate2",
	channel = CHAN_AUTO,
	volume = 1.0,
	level = 80,
	pitch = { 95, 110 },
	sound = "vehicles/v8/v8_rev_short_loop1.wav"
} )

sound.Add( {
	name = "jazz_bus_idle",
	channel = CHAN_AUTO,
	volume = 1.0,
	level = 80,
	pitch = { 95, 110 },
	sound = "vehicles/v8/v8_start_loop1.wav"
} )

function ENT:Initialize()

	self:SetModel( self.Model )
	self:PhysicsInit( SOLID_VPHYSICS )
	self:SetMoveType( MOVETYPE_VPHYSICS )
	self:SetSolid( SOLID_VPHYSICS )
	//self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
	
	local phys = self:GetPhysicsObject()
	if phys then
		phys:EnableGravity( true )
		phys:EnableMotion( true )
		phys:Wake()
	end

	-- Setup seat offsets
	for i=1, 8 do
		self:AttachSeat(Vector(40, i * 45 - 150, 80), Angle(0, 180, 0))
		self:AttachSeat(Vector(-40, i * 45 - 150, 80), Angle(0, 180, 0))
	end

	self.StartPos = self:GetPos() + self:GetAngles():Right() * -2000 + Vector(0, 0, 40)
	self.GoalPos = self:GetPos()
	self.StartTime = CurTime()
	self.StartAngles = self:GetAngles()

	-- Start us off right at the start
	self:SetPos(self.StartPos)

	-- Setup shadow controller
	self:StartMotionController()

	self:EmitSound( "vehicles/v8/vehicle_impact_heavy1.wav", 90, 150 )
	self:EmitSound( "jazz_bus_idle", 90, 150 )

	-- Hook into when the map is changed so this bus knows to leave
	if SERVER then
		hook.Add("JazzMapRandomized", self, function(self, newmap)
			if self:GetDestination() != newmap then self:LeaveStation() end
		end )

		hook.Add("PlayerEnteredVehicle", self, function(self, ply, veh, role) 
			self:CheckLaunch()
		end)
	end
end

function ENT:AttachSeat(pos, ang)
	pos = self:LocalToWorld(pos)
	ang = self:LocalToWorldAngles(ang)

	local ent = ents.Create("prop_vehicle_prisoner_pod")
	ent:SetModel("models/nova/airboat_seat.mdl")
	ent:SetKeyValue("vehiclescript","scripts/vehicles/prisoner_pod.txt")
	ent:SetPos(pos)
	ent:SetAngles(ang)
	ent:SetParent(self)
	ent:Spawn()
	ent:Activate()

	self.Seats = self.Seats or {}
	table.insert(self.Seats, ent)
end

function ENT:GetNumOccupants()
	if !self.Seats then return 0 end
	local count = 0
	for _, v in pairs(self.Seats) do
		if IsValid(v) and IsValid(v:GetDriver()) then
			count = count + 1
		end
	end

	return count
end

function ENT:CheckLaunch()
	if self:GetNumOccupants() >= player.GetCount() then
		self:EmitSound( "jazz_bus_idle", 90, 150 )
		util.ScreenShake(self:GetPos(), 10, 5, 1, 1000)

		timer.Simple(1, function()
			self.IsLaunching = true
			self:LeaveStation()

			net.Start("jazz_bus_launcheffects")
				net.WriteEntity(self)
			net.Broadcast()
		end )
	end
end

function ENT:PhysicsCollide( data, phys )

end

function ENT:LeaveStation()
	if self.Leaving then return end 

	self:EmitSound("jazz_bus_accelerate2")

	self.StartTime = CurTime()
	self.StartPos = self:GetPos()
	self.GoalPos = self.GoalPos + self:GetAngles():Right() * 2000

	self.Leaving = true
	self:ResetTrigger("arrived")
	self:GetPhysicsObject():EnableMotion(true)
	self:GetPhysicsObject():Wake()
end

function ENT:GetProgress()
	local t = CurTime() - self.StartTime 

	return t, t / self.TravelTime
end

function ENT:PhysicsSimulate( phys, deltatime )
	local t, perc = self:GetProgress()
	local rotAng = 0
	if self.Leaving then
		p = math.pow(perc, 2)

		-- Bus is speeding up, rotate backward a bit
		rotAng = math.Clamp(perc * 16, 0, 1) * -3.5
	else
		p = math.pow(perc, 0.4)
		
		-- Bus slowing down, rotate forwards
		rotAng = math.Clamp(1.2 - perc, 0, 1) * 3.5
	end

	local percC = math.Clamp(p, 0, 1)
	self.ShadowControl.pos = LerpVector(percC, self.StartPos, self.GoalPos)
	self.ShadowControl.angle = Angle(self.StartAngles)
	self.ShadowControl.angle:RotateAroundAxis(self.StartAngles:Forward(), rotAng)

	//print(t .. ", MissedBus: " .. tostring(self.MissedBus))

	phys:ComputeShadowControl( self.ShadowControl )
end

function ENT:TriggerAt(name, time, func)
	local t, p = self:GetProgress()
	local fullname = name .. "_Trigger"
	if t - self.TravelTime > time and not self[fullname] then
		self[fullname] = true
		func()
	end
end

function ENT:ResetTrigger(name)
	local fullname = name .. "_Trigger"
	self[fullname] = false
end

function ENT:Think()
	local t, p = self:GetProgress()

	-- Keep the bus awake while it should be moving
	if p < 1 and self:GetPhysicsObject():IsAsleep() then
		self:GetPhysicsObject():Wake() 
	end

	if self.Leaving then
		self:TriggerAt("accelturbo", -1.0, function()
			self:EmitSound( "jazz_bus_accelerate", 90, 150 )
		end )
	end

	-- Skid sound when stopping
	self:TriggerAt("stopslide", -0.8, function()
		self:EmitSound( "vehicles/v8/skid_normalfriction.wav", 90, 110 )	
	end )

	self:TriggerAt("engineoff", 0.0, function()
		self:EmitSound( "vehicles/v8/v8_stop1.wav", 90, 110 )
		self:StopSound("jazz_bus_idle")
	end )

	-- Allow the bus to settle into its spot before stopping movement
	local endTime = self.IsLaunching and 2.2 or 1
	self:TriggerAt("arrived", endTime, function()
		self:GetPhysicsObject():EnableMotion(false)
		self:SetPos(self.GoalPos)
		self:SetAngles(self.StartAngles)

		if self.Leaving then
			self:Remove()
		end
	end )

	-- TODO: actual transition effects
	if self.IsLaunching then

		--if !self.NextExplode or self.NextExplode < CurTime() then
		--	local expl = ents.Create( "env_explosion" ) //creates the explosion
		--	expl:SetPos( self:GetPos() + self:GetAngles():Right() * 550 + self:GetAngles():Up() * 50)
		--	expl:Spawn() //this actually spawns the explosion
		--	expl:Fire( "Explode", 0, 0 )
		--end
	end
end

function ENT:OnRemove()
	self:StopSound("jazz_bus_accelerate")
	self:StopSound("jazz_bus_accelerate2")
	self:StopSound("jazz_bus_idle")

	if self.Seats then 
		for _, v in pairs(self.Seats) do
			if IsValid(v) then v:Remove() end
		end
	end

	-- Tastefully wait just a bit to let the players know they fucked up when they wanted to travel by cat
	if self.IsLaunching then
		local mapname = self:GetDestination()
		timer.Simple(2, function()
			mapcontrol.Launch(mapname)
		end )
	end
end