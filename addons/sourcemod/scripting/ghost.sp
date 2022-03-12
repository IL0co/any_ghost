#include <sdktools>
#include <sdkhooks>
#include <sourcemod>
#include <clientprefs>
#include <csgo_colors>
#include <string>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo =
{
	name		= "Ghost",
	author	  	= "iLoco",
	description = "Призраки на месте смерти",
	version	 	= "2.0.3",
	url			= "http://www.hlmod.ru"
};

// TODO: перевести на спрайты
// добавить ambient звук

KeyValues kv;
char gBuff[256];
bool gDebug;
ArrayList arZones;
int gEntBits[2048];

int gBeamLaser, gBeamMat;

public void OnPluginEnd()
{
	for(int pos; pos < arZones.Length; pos++)
		KillEntities(EntRefToEntIndex(arZones.Get(pos)));
}

public void OnPluginStart()
{
	arZones = new ArrayList(256);
	kv = new KeyValues("Config");
	BuildPath(Path_SM, gBuff, sizeof(gBuff), "configs/ghost.txt");
	if(!kv.ImportFromFile(gBuff))
		SetFailState("File %s does not found!", gBuff);
	)
	if(kv.GotoFirstSubKey())
	{
		int count; 

		do
		{
			count++;
		}
		while(kv.GotoNextKey());

		kv.Rewind();
		kv.SetNum("all count", count);
	}

	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	ConVar cvar;
	(cvar = CreateConVar("sm_ghost_debug", "0", "Debug enable.")).AddChangeHook(Cvar_OnChanged);
	gDebug = cvar.BoolValue;

	AutoExecConfig(true, "ghosts.cfg");

	RegConsoleCmd("sm_ghost_spawn", CMD_SpawnGhost, "Заспавнить на месте прицела призрака");
}

public Action CMD_SpawnGhost(int client, int args)
{
	float pos[3];
	TracePlayerAim(client, pos);
	
	SpawnGhost(pos, client);

	return Plugin_Handled;
}

public void Cvar_OnChanged(ConVar cvar, char[] oldVal, char[] newVal)
{
	gDebug = cvar.BoolValue;
}

public void OnMapStart()
{
	char buff[256];

	gBeamLaser = PrecacheModel("materials/sprites/laserbeam.vmt");
	gBeamMat = PrecacheModel("materials/sprites/glow01.vmt");
	PrecacheModel("models/error.mdl");

	BuildPath(Path_SM, buff, sizeof(buff), "configs/ghost_download.txt");
	File file = OpenFile(buff, "r");

	if(file) {
		while(file.ReadLine(buff, sizeof(buff)))		if(buff[0]) {
			TrimString(buff);
			if(buff[0] == '/' && buff[2] == '/') {
				continue;
			}
			if(FileExists(buff, true) || FileExists(buff, false)) {
				AddFileToDownloadsTable(buff);

				if(strcmp(buff[FindCharInString(buff, '.')+1], "pcf", false) == 0) {
					PrecacheGeneric(buff, true);
				}
			}
		}

		delete file;
	}

	kv.Rewind();

	if(!kv.GotoFirstSubKey())
		return;
		
	PrecacheEffect("ParticleEffect");

	do
	{
		kv.GetString("particle name", buff, sizeof(buff));
		if(buff[0])
			PrecacheParticleEffect(buff);

		kv.GetString("sound file", buff, sizeof(buff));
		if(buff[0]) {
			PrecacheSound(buff, true);
		}
	}
	while(kv.GotoNextKey());

	kv.Rewind();
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	if(!IsClientInGame(client) || IsPlayerAlive(client) || (kv.GetNum("spawn on warmup", 0) && GameRules_GetProp("m_bWarmupPeriod") == 1))
		return Plugin_Continue;

	float pos[3];
	GetClientAbsOrigin(client, pos);
	pos[2] -= 60.0;
	
	SpawnGhost(pos, client);

	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	if(!IsClientInGame(client) || kv.GetNum("delete on spawn", 0))
		return Plugin_Continue;
	
	for(int pos, zone, particle; pos < arZones.Length; pos++)
	{
		zone = EntRefToEntIndex(arZones.Get(pos));
		particle = GetEntPropEnt(zone, Prop_Data, "m_pParent");

		if(client == GetEntPropEnt(particle, Prop_Data, "m_hOwnerEntity"))
			KillEntities(zone);
	}

	return Plugin_Continue;
}

public void SpawnGhost(float pos[3], int client)
{
	bool loop = true;
	int num, current, teamlimit, cycle,
	maxNum = kv.GetNum("all count"), 
	maxCycle = kv.GetNum("max spawn chance"), 
	team = GetClientTeam(client);

	if(maxCycle <= 0)
		maxCycle = 50;

	if(!kv.GotoFirstSubKey())
		return;
		
	do
	{
		if(cycle++ >= maxCycle)
			break; 

		num = GetRandomInt(1, maxNum);
		current = 1;

		do
		{
			if(current++ != num || ((teamlimit = kv.GetNum("team spawn", 0)) != 0 && team != teamlimit))
				continue;

			if(GetRandomFloat(0.0, 100.0) > kv.GetFloat("spawn chance", 50.0))
				break;
				
			float fbuff,
			mins[3] = {-16.0, 0.0, -16.0}, 
			maxs[3] = {16.0, 32.0, 16.0};

			kv.GetVector("mins", mins, mins);
			fbuff = mins[1];
			mins[1] = mins[2];
			mins[2] = fbuff;

			kv.GetVector("maxs", maxs, maxs);
			fbuff = maxs[1];
			maxs[1] = maxs[2];
			maxs[2] = fbuff;

			pos[0] += kv.GetFloat("uplift");

			kv.GetSectionName(gBuff, sizeof(gBuff));
			int zone = Create_TriggerZone(mins, maxs, pos, gBuff);
			int particle = CreateParticle(pos, gBuff);
			arZones.Push(EntIndexToEntRef(zone));

			SetEntPropEnt(particle, Prop_Send, "m_hOwnerEntity", client);
			
			if((gEntBits[particle] = kv.GetNum("visions bits", 0)) != 0)
				SDKHook(particle, SDKHook_SetTransmit, Hook_SetTransmit);
			
			SetVariantString("!activator");
			AcceptEntityInput(zone, "SetParent", particle);

			float lifetime = kv.GetFloat("lifetime", -1.0);
			if(lifetime != -1.0)
			{
				SetEntLifeTime(zone, lifetime);
				SetEntLifeTime(particle, lifetime, true);
			}

			loop = false;

			if(gDebug) 
			{
				DataPack data = new DataPack();
				data.WriteCell(EntIndexToEntRef(zone));
				
				float point[8][3];
				
				AddVectors(pos, mins, mins);
				AddVectors(pos, maxs, maxs);

				for(int p; p < 3; p++)
				{
					AddVectors(point[p+3], mins, point[p+3]);
					point[p+3][p] = maxs[p];

					AddVectors(point[p], maxs, point[p]);
					point[p][p] = mins[p];
				}

				point[6] = mins;
				point[7] = maxs;
				
				for(int first; first < 8; first++)
					for(int sec; sec < 3; sec++)
						data.WriteFloat(point[first][sec]);

				TE_SendBeamBoxToAll(point);
				CreateTimer(2.0, Timer_DrawBeamBox, data, TIMER_REPEAT|TIMER_DATA_HNDL_CLOSE|TIMER_FLAG_NO_MAPCHANGE);
			}
			
			break;
		}
		while(kv.GotoNextKey());

		if(maxNum == 1)
			break;
	}
	while(loop);

	kv.Rewind();
}

public Action Hook_SetTransmit(int particle, int client)
{
	if(!particle || !client)
		return Plugin_Continue;
		
	if(GetEdictFlags(particle) & FL_EDICT_ALWAYS)
	 	SetEdictFlags(particle, (GetEdictFlags(particle) ^ FL_EDICT_ALWAYS));

	if(!IsBitsSuccessful(particle, client))
		return Plugin_Handled;

	return Plugin_Continue;
}

stock bool IsBitsSuccessful(int particle, int client)
{
	static int owner, ownerTeam, clientTeam;

	owner = GetEntPropEnt(particle, Prop_Send, "m_hOwnerEntity");
	if(owner == -1) 
		owner = 0;

	if(gEntBits[particle] & 1 && owner == client)
		return false;

	clientTeam = GetClientTeam(client);

	if(gEntBits[particle] & 8 && clientTeam < 2)
		return false;

	ownerTeam = GetClientTeam(owner);

	if(gEntBits[particle] & 4 && clientTeam == ownerTeam)
		return false;

	if(gEntBits[particle] & 2 && clientTeam != ownerTeam)
		return false;

	return true;
}

stock void SetEntLifeTime(int ent, float time, bool isParticle = false)
{
	Format(gBuff, sizeof(gBuff), "OnUser1 !self:%s::%1.1f:1", isParticle ? "DestroyImmediately" : "kill", time);
	SetVariantString(gBuff);  

	if(isParticle) {
		Format(gBuff, sizeof(gBuff), "OnUser1 !self:%s::%1.1f:1", "kill", time + 0.1);
		SetVariantString(gBuff);  
	}

	AcceptEntityInput(ent,"AddOutput");  
	AcceptEntityInput(ent,"FireUser1");
}

stock int CreateParticle(const float pos[3], char[] name)
{
	char buff[64];
	int ent = CreateEntityByName("info_particle_system");

	if(ent)
	{
		DispatchKeyValue(ent, "targetname", name);

		kv.GetString("particle name", buff, sizeof(buff));
		DispatchKeyValue(ent, "effect_name", buff);

		DispatchSpawn(ent);
		DispatchKeyValue(ent, "start_active", "1");
		ActivateEntity(ent);
		AcceptEntityInput(ent, "Start");
		TeleportEntity(ent, pos, NULL_VECTOR, NULL_VECTOR);

		SetVariantString("!activator");
	}

	return ent;
}

stock int Create_TriggerZone(const float mins[3], const float maxs[3], const float middle[3], char[] name) 
{
	int ent = CreateEntityByName("trigger_multiple");
	
	DispatchKeyValue(ent, "spawnflags", "64");

	SetEntPropString(ent, Prop_Data, "m_target", name);
	DispatchKeyValue(ent, "wait", "0");
	
	DispatchSpawn(ent);
	ActivateEntity(ent);

	SetEntityModel(ent, "models/error.mdl");
	
	SetEntPropVector(ent, Prop_Send, "m_vecMins", mins);
	SetEntPropVector(ent, Prop_Send, "m_vecMaxs", maxs);
	SetEntProp(ent, Prop_Send, "m_nSolidType", 2);
	
	TeleportEntity(ent, middle, NULL_VECTOR, NULL_VECTOR);

	int iEffects = GetEntProp(ent, Prop_Send, "m_fEffects");
	iEffects |= 32;
	SetEntProp(ent, Prop_Send, "m_fEffects", iEffects);
	
	HookSingleEntityOutput(ent, "OnStartTouch", EntOut_OnStartTouch);
	
	return ent;
}

public void OnEntityDestroyed(int entity)
{
	static int pos, ref;

	if(entity <= MaxClients || entity > 2048 || !arZones.Length || (ref = EntIndexToEntRef(entity)) == INVALID_ENT_REFERENCE || (pos = arZones.FindValue(ref)) < 0)
		return;
		
	arZones.Erase(pos);
}

public void EntOut_OnStartTouch(const char[] output, int zone, int activator, float delay) 
{
	if(activator < 1 || activator > MaxClients || !IsClientInGame(activator) || !IsPlayerAlive(activator))
		return;

	int particle = GetEntPropEnt(zone, Prop_Data, "m_pParent");
	if(gEntBits[particle] && !IsBitsSuccessful(particle, activator))
		return;

	kv.Rewind();
	GetEntPropString(zone, Prop_Data, "m_target", gBuff, sizeof(gBuff));
	if(kv.JumpToKey(gBuff))
	{
		kv.GetString("command on take", gBuff, sizeof(gBuff));
		if(gBuff[0])
		{
			char buff[10];
			Format(buff, sizeof(buff), "\"#%i\"", GetClientUserId(activator));
			ReplaceString(gBuff, sizeof(gBuff), "{client}", buff);
			ServerCommand(gBuff);
		}

		kv.GetString("message to all", gBuff, sizeof(gBuff));
		if(gBuff[0])
		{
			char buff[32];
			Format(buff, sizeof(buff), "%N", activator);
			ReplaceString(gBuff, sizeof(gBuff), "{name}", buff);
			CGOPrintToChatAll(gBuff);
		}

		kv.GetString("message to taker", gBuff, sizeof(gBuff));
		if(gBuff[0])
		{
			char buff[32];
			Format(buff, sizeof(buff), "%N", activator);
			ReplaceString(gBuff, sizeof(gBuff), "{name}", buff);
			CGOPrintToChat(activator, gBuff);
		}

		kv.GetString("sound file", gBuff, sizeof(gBuff));
		if(gBuff[0])
			EmitSoundToAll(gBuff, zone, SNDCHAN_STREAM, kv.GetNum("sound pitch", 100), _, kv.GetFloat("sound volume", 1.0));

		kv.Rewind();
	}

	KillEntities(zone);
}

public Action Timer_DestroyParticle(Handle timer, int particle)
{
	if(particle == INVALID_ENT_REFERENCE)
		return;
		
	particle = EntRefToEntIndex(particle);
	if(particle > MaxClients+1 && IsValidEntity(particle))	 
		AcceptEntityInput(particle, "DestroyImmediately");
		// AcceptEntityInput(particle, "kill");

	CreateTimer(0.1, Timer_KillParticle, EntIndexToEntRef(particle)); 
}

public Action Timer_KillParticle(Handle timer, int particle)
{
	if(particle == INVALID_ENT_REFERENCE)
		return;

	particle = EntRefToEntIndex(particle);
	if(particle > MaxClients+1 && IsValidEntity(particle))	 
		AcceptEntityInput(particle, "kill");
}

stock void KillEntities(int zone)
{
	int particle = GetEntPropEnt(zone, Prop_Data, "m_pParent");
	
	if(zone > MaxClients && zone <= 2048 && IsValidEntity(zone))  
		AcceptEntityInput(zone, "kill");

	if(particle > MaxClients && particle <= 2048 && IsValidEntity(particle))  
		CreateTimer(0.2, Timer_DestroyParticle, EntIndexToEntRef(particle)); 
}

public Action Timer_DrawBeamBox(Handle timer, DataPack data)
{
	data.Reset();
	int ent = EntRefToEntIndex(data.ReadCell());

	if(ent <= MaxClients || ent > 2048 || !IsValidEntity(ent) || !gDebug)
		return Plugin_Stop;

	static float point[8][3];
	
	for(int first; first < 8; first++)
		for(int sec; sec < 3; sec++)
			point[first][sec] = data.ReadFloat();

	TE_SendBeamBoxToAll(point);
	
	return Plugin_Continue;
}

stock void PrecacheEffect(const char[] sEffectName)
{
	static int table = INVALID_STRING_TABLE;
	
	if(table == INVALID_STRING_TABLE)
		table = FindStringTable("EffectDispatch");

	bool save = LockStringTables(false);
	AddToStringTable(table, sEffectName);
	LockStringTables(save);
}

stock void PrecacheParticleEffect(const char[] sEffectName)
{
	PrecacheEffect("ParticleEffect");
	static int table = INVALID_STRING_TABLE;
	
	if(table == INVALID_STRING_TABLE)
		table = FindStringTable("ParticleEffectNames");

	bool save = LockStringTables(false);
	AddToStringTable(table, sEffectName);
	LockStringTables(save);
}  

stock void TE_SendBeamBoxToAll(const float point[8][3]) 
{
	TE_SetupBeamPoints(point[7], point[0], gBeamLaser, gBeamMat, 0, 30, 2.0, 1.0, 1.0, 0, 0.0, {255, 255, 255, 75}, 0);
	TE_SendToAll();
	TE_SetupBeamPoints(point[7], point[1], gBeamLaser, gBeamMat, 0, 30, 2.0, 1.0, 1.0, 0, 0.0, {255, 255, 255, 75}, 0);
	TE_SendToAll();
	TE_SetupBeamPoints(point[7], point[2], gBeamLaser, gBeamMat, 0, 30, 2.0, 1.0, 1.0, 0, 0.0, {255, 255, 255, 75}, 0);
	TE_SendToAll();
	TE_SetupBeamPoints(point[5], point[0], gBeamLaser, gBeamMat, 0, 30, 2.0, 1.0, 1.0, 0, 0.0, {255, 255, 255, 75}, 0);
	TE_SendToAll();
	TE_SetupBeamPoints(point[5], point[1], gBeamLaser, gBeamMat, 0, 30, 2.0, 1.0, 1.0, 0, 0.0, {255, 255, 255, 75}, 0);
	TE_SendToAll();
	TE_SetupBeamPoints(point[5], point[6], gBeamLaser, gBeamMat, 0, 30, 2.0, 1.0, 1.0, 0, 0.0, {255, 255, 255, 75}, 0);
	TE_SendToAll();
	TE_SetupBeamPoints(point[3], point[6], gBeamLaser, gBeamMat, 0, 30, 2.0, 1.0, 1.0, 0, 0.0, {255, 255, 255, 75}, 0);
	TE_SendToAll();
	TE_SetupBeamPoints(point[4], point[6], gBeamLaser, gBeamMat, 0, 30, 2.0, 1.0, 1.0, 0, 0.0, {255, 255, 255, 75}, 0);
	TE_SendToAll();
	TE_SetupBeamPoints(point[4], point[0], gBeamLaser, gBeamMat, 0, 30, 2.0, 1.0, 1.0, 0, 0.0, {255, 255, 255, 75}, 0);
	TE_SendToAll();
	TE_SetupBeamPoints(point[4], point[2], gBeamLaser, gBeamMat, 0, 30, 2.0, 1.0, 1.0, 0, 0.0, {255, 255, 255, 75}, 0);
	TE_SendToAll();
	TE_SetupBeamPoints(point[3], point[2], gBeamLaser, gBeamMat, 0, 30, 2.0, 1.0, 1.0, 0, 0.0, {255, 255, 255, 75}, 0);
	TE_SendToAll();
	TE_SetupBeamPoints(point[3], point[1], gBeamLaser, gBeamMat, 0, 30, 2.0, 1.0, 1.0, 0, 0.0, {255, 255, 255, 75}, 0);
	TE_SendToAll();
}

public bool TracePlayerAim(int client, float vec[3]) 
{
	if (!IsClientInGame(client))
		return false;

	float ang[3], pos[3];
	GetClientEyeAngles(client, ang);
	GetClientEyePosition(client, pos);
	
	Handle traceray = TR_TraceRayFilterEx(pos, ang, MASK_SHOT_HULL, RayType_Infinite, TraceEntityFilterPlayers);
	if (TR_DidHit(traceray)) {
		TR_GetEndPosition(vec, traceray);
		delete traceray;

		return true;
	}
	
	delete traceray;
	return false;
}

stock bool TraceEntityFilterPlayers(int entity, int contentsMask) {
	return entity > MaxClients;
} 
