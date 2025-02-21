// by ficool2 edited by notfoundname

Convars.SetValue("sv_turbophysics", 0);

const IN_FORWARD = 8;
const IN_BACK = 16;
const IN_USE = 32;
const IN_MOVELEFT = 512;
const IN_MOVERIGHT = 1024;
const MASK_IN_VEHICLE = 10245; // IN_ATTACK|IN_DUCK|IN_ATTACK2|IN_RELOAD
const DMG_CRUSH = 1;
const COLLISION_GROUP_PLAYER = 5;
const COLLISION_GROUP_IN_VEHICLE = 10;
const MOVETYPE_NONE = 0;
const MOVETYPE_WALK = 2;
const FL_DUCKING = 2;
const EFL_IS_BEING_LIFTED_BY_BARNACLE = 1048576;
const MASK_PLAYERSOLID = 33636363; // CONTENTS_SOLID|CONTENTS_MOVEABLE|CONTENTS_WINDOW|CONTENTS_PLAYERCLIP|CONTENTS_GRATE|CONTENTS_MONSTER
const DMG_VEHICLE = 16;

::VehicleInitPlayer <- function(player)
{
	player.ValidateScriptScope();
	local scope = player.GetScriptScope();
	scope.vehicle <- null;
	scope.vehicle_scope <- null;
}

::VehicleThink <- function()
{
	for (local player; player = Entities.FindByClassname(player, "player");)
	{
		if (!player.IsAlive())
			continue;
		local scope = player.GetScriptScope();
		//
		// if (scope.vehicle)
		// {
		//  	NetProps.SetPropInt(player, "m_Shared.m_nAirDucked", 8);
		//  	continue;
		//}
		local buttons = NetProps.GetPropInt(player, "m_nButtons");		
		if (buttons & IN_USE)
		{	
			// find vehicle under crosshair
			local eye_pos = player.EyePosition();
			local trace =
			{
				start = eye_pos,
				end = eye_pos + player.EyeAngles().Forward() * 192.0,
				ignore = player
			}
			TraceLineEx(trace);		
			if (trace.hit && trace.enthit.GetClassname() == "prop_vehicle_driveable")
				trace.enthit.GetScriptScope().Enter(player);
		}
	}
	return 0.1
}

// This hack allows vehicle damage to show the train kil licon
if (!("VehicleDmgOwner" in getroottable()) || !VehicleDmgOwner.IsValid())
{
	::VehicleDmgOwner <- SpawnEntityFromTable("handle_dummy", {});
	VehicleDmgOwner.KeyValueFromString("classname", "vehicle");
}
AddThinkToEnt(VehicleDmgOwner, "VehicleThink")

function Precache()
{
	driver <- null;
	vehicle <- self;
	can_enter <- true;
	can_exit <- false;
	fixup_origin <- Vector();
	fixup_angles <- QAngle();
	
    // unused spawnflags are used to define non-car vehicle type
	local flags = NetProps.GetPropInt(self, "m_spawnflags");
	if (flags > 0)
		NetProps.SetPropInt(self, "m_nVehicleType", flags);
	
	NetProps.SetPropInt(self, "m_spawnflags", 1); // per-frame physics must be on
}

function OnPostSpawn()
{
	AddThinkToEnt(self, "Think");
}

function EnableEnter()
{
	can_enter = true;
}

function EnableExit()
{
	can_exit = true;
}

function CheckExitPoint(yaw, distance, mins, maxs)
{
	local vehicleAngles = vehicle.GetLocalAngles();
	vehicleAngles.y += yaw;	
	
  	local vecStart = vehicle.GetOrigin();
	vecStart.z += 12.0;
	
  	local vecDir = vehicleAngles.Left() * -1.0;
	
  	fixup_origin = vecStart + vecDir * distance;
  
	local trace = 
	{
		start = vecStart,
		end = fixup_origin,
		hullmin = mins,
		hullmax = maxs,
		mask = MASK_PLAYERSOLID,
		ignore = vehicle
	};
	
	TraceHull(trace);
	if (trace.fraction < 1.0)
		return false;
  
  	return true;
}

function CanExit()
{
	local mins = driver.GetPlayerMins();
	local maxs = driver.GetPlayerMaxs();
	
	local attachment = vehicle.LookupAttachment("vehicle_driver_exit");
	if (!attachment)
	{
		attachment = vehicle.LookupAttachment("vehicle_passenger0_exit");
	}
	if (attachment > 0)
	{
		local attachment_origin = vehicle.GetAttachmentOrigin(attachment);
	
		local trace = 
		{
			start = attachment_origin + Vector(0, 0, 12),
			end = attachment_origin,
			hullmin = mins,
			hullmax = maxs,
			mask = MASK_PLAYERSOLID,
			ignore = vehicle
		};
		TraceHull(trace);

		if (!("startsolid" in trace))
		{
			fixup_origin = attachment_origin;
			fixup_angles = vehicle.GetAttachmentAngles(attachment);
			return true;
		}
	}
	
	if (CheckExitPoint(90.0, 90.0, mins, maxs))
		return true;
	if (CheckExitPoint(-90.0, 90.0, mins, maxs))
		return true
	if (CheckExitPoint(0.0, 100.0, mins, maxs))
		return true;
	if (CheckExitPoint(180.0, 170.0, mins, maxs))
		return true;

	local vehicle_center = vehicle.GetCenter();
	local vehicle_mins = vehicle_center + vehicle.GetBoundingMins();
	local vehicle_maxs = vehicle_center + vehicle.GetBoundingMaxs();
	fixup_origin = Vector((vehicle_mins.x + vehicle_maxs.x) * 0.5, (vehicle_mins.y + vehicle_maxs.y) * 0.5, vehicle_maxs.z + 50.0);
	
	local trace = 
	{
		start = vehicle.GetCenter(),
		end = fixup_origin,
		hullmin = mins,
		hullmax = maxs,
		mask = MASK_PLAYERSOLID,
		ignore = vehicle
	};
	TraceHull(trace);
	if (!("startsolid" in trace))
		return true;
	
	return false;
}

function Enter(player)
{
	if (!can_enter || driver)
		return;
	
	local player_scope = player.GetScriptScope();
	player_scope.vehicle = vehicle;
	player_scope.vehicle_scope = this;
	driver = player;
	can_exit = false;

	driver.SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE);
	driver.SetMoveType(MOVETYPE_NONE, 0);
	
	local origin;
	local attachment = vehicle.LookupAttachment("vehicle_driver_eyes");
	if (!attachment)
		attachment = vehicle.LookupAttachment("vehicle_passenger0_eyes");
	if (attachment > 0)
		origin = vehicle.GetAttachmentOrigin(attachment);
	else
		origin = vehicle.GetCenter();
	origin.z -= 56.0;
	driver.SetAbsOrigin(origin);
	driver.SetAbsVelocity(Vector());
	
	driver.AcceptInput("SetParent", "!activator", vehicle, vehicle);
	
	driver.RemoveFlag(FL_DUCKING);
	
	NetProps.SetPropInt(driver, "m_afButtonDisabled", MASK_IN_VEHICLE);
	NetProps.SetPropBool(driver, "m_Local.m_bDrawViewmodel", false);
	
	NetProps.SetPropBool(driver, "pl.deadflag", true);
	
	vehicle.AcceptInput("TurnOn", "", null, null)
	EntFireByHandle(vehicle, "CallScriptFunction", "EnableExit", 1.0, null, null);
}

function Exit(dead, teleport)
{
	if (driver)
	{	
		if (!dead)
			NetProps.SetPropBool(driver, "pl.deadflag", false);
		//driver.RemoveCustomAttribute("disable weapon switch");
		//driver.RemoveCustomAttribute("no_attack");
		//driver.RemoveCustomAttribute("no_duck");
		
		driver.AcceptInput("ClearParent", "", null, null)
		
		fixup_origin = driver.GetOrigin() + Vector(0, 0, 8);
		fixup_angles = driver.EyeAngles();				
	
		if (!CanExit())
		{
			// too bad
			//printl("Can't exit!");
		}
			
		fixup_angles.z = 0.0; // no roll
		
		driver.SetCollisionGroup(COLLISION_GROUP_PLAYER);
		driver.SetMoveType(MOVETYPE_WALK, 0);
	
		driver.SetAbsOrigin(fixup_origin);
		driver.SnapEyeAngles(fixup_angles);
		driver.SetAbsVelocity(vehicle.GetPhysVelocity());		

		NetProps.SetPropInt(driver, "m_afButtonDisabled", 0);
		NetProps.SetPropBool(driver, "m_Local.m_bDrawViewmodel", true);
		
		//local weapon = driver.GetActiveWeapon();
		//if (weapon)
		//{
		//	NetProps.SetPropEntity(driver, "m_hActiveWeapon", null);
		//	driver.Weapon_Switch(weapon);
		//}
	
		local driver_scope = driver.GetScriptScope();
		driver_scope.vehicle = null;
		driver_scope.vehicle_scope = null;
		driver = null;
		
	}
	
	NetProps.SetPropFloat(vehicle, "m_VehiclePhysics.m_controls.steering", 0);
	NetProps.SetPropFloat(vehicle, "m_VehiclePhysics.m_controls.throttle", 0);
	//vehicle.AcceptInput("TurnOff", "", null, null); // this breaks the vehicle permanently for some reason
	
	can_enter = false;
	EntFireByHandle(vehicle, "CallScriptFunction", "EnableEnter", 1.0, null, null);
}

function Think() 
{
	self.StudioFrameAdvance();
	
	if (driver)
	{
		local buttons = NetProps.GetPropInt(driver, "m_nButtons");
	
		if (buttons & IN_MOVERIGHT)
			NetProps.SetPropFloat(self, "m_VehiclePhysics.m_controls.steering", 1.0);
		else if (buttons & IN_MOVELEFT)
			NetProps.SetPropFloat(self, "m_VehiclePhysics.m_controls.steering", -1.0);
		else
			NetProps.SetPropFloat(self, "m_VehiclePhysics.m_controls.steering", 0);
		
		if (!(buttons & (IN_FORWARD|IN_BACK)))
			NetProps.SetPropFloat(self, "m_VehiclePhysics.m_controls.throttle", 0);
		else if (buttons & IN_FORWARD)
			NetProps.SetPropFloat(self, "m_VehiclePhysics.m_controls.throttle", 1);
		else if (buttons & IN_BACK)
			NetProps.SetPropFloat(self, "m_VehiclePhysics.m_controls.throttle", -1);
			
		if (can_exit)
		{
			if (buttons & IN_USE)
				Exit(false, true);
		}
			
		return -1;
	}
	else
	{
		return 0.1;
	}
}

if (!("VehicleEvents" in getroottable()))
	::VehicleEvents <- {};
::VehicleEvents.clear();
::VehicleEvents =
{
	OnGameEvent_player_spawn = function(params)
	{
		local player = GetPlayerFromUserID(params.userid);
		if (!player)
			return;
		
		if (player.GetTeam() == 0) // unassigned
		{
			VehicleInitPlayer(player)
			return;
		}
		
		if (player.GetTeam() & 2)
		{
			// respawned while in a vehicle?
			local vehicle_scope = player.GetScriptScope().vehicle_scope;
			if (vehicle_scope)
				vehicle_scope.Exit(false, false);
			
			player.AddEFlags(EFL_IS_BEING_LIFTED_BY_BARNACLE); // prevents game's +use from passing to vehicle
		}
	}

	OnGameEvent_player_death = function(params)
	{
		local player = GetPlayerFromUserID(params.userid);
		if (!player)
			return;
			
		local scope = player.GetScriptScope();
		if (scope && scope.vehicle_scope)
			scope.vehicle_scope.Exit(true, true);
	}

	OnGameEvent_player_disconnect = function(params)
	{
		local player = GetPlayerFromUserID(params.userid);
		if (!player)
			return;
			
		local scope = player.GetScriptScope();
		if (scope && scope.vehicle_scope)
			scope.vehicle_scope.Exit(true, false);
	}
	
	// this event probably does not exist
	OnGameEvent_scorestats_accumulated_update = function(params)
	{
		for (local vehicle; vehicle = Entities.FindByClassname(vehicle, "prop_vehicle_driveable");)
			vehicle.GetScriptScope().Exit(false, false);
	}

	OnScriptHook_OnTakeDamage = function(params)
	{
		local victim = params.const_entity;
		local inflictor = params.inflictor;
		
		if (victim.GetClassname() == "prop_vehicle_driveable")
		{
			// pass damage to driver
			local driver = victim.GetScriptScope().driver;
			if (driver && inflictor != driver)
			{
				driver.TakeDamageCustom(
					params.inflictor, 
					params.attacker,
					params.weapon,
					params.damage_force,
					params.damage_position, 
					params.damage,
					params.damage_type, 
					params.damage_custom);
			}
		}
		else if (inflictor && inflictor.GetClassname() == "prop_vehicle_driveable")
		{
			VehicleDmgOwner.SetAbsOrigin(inflictor.GetOrigin());
			
			// make driver own the damage
			params.damage_type = DMG_VEHICLE; // unfortunately this doesn't set the kill icon
			params.inflictor = VehicleDmgOwner;
			params.attacker = inflictor.GetScriptScope().driver;
		}
	}
}
__CollectGameEventCallbacks(VehicleEvents)

for (local player; player = Entities.FindByClassname(player, "player");)
{
	local scope = player.GetScriptScope()
	if (!scope || !("vehicle" in scope))
		VehicleInitPlayer(player)
}
