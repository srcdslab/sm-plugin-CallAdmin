#include <sourcemod>
#include <clientprefs>
#include <cstrike>
#include <basecomm>

#include <AFKManager>
#include <discordWebhookAPI>
#include <multicolors>

#undef REQUIRE_PLUGIN
#tryinclude <sourcecomms>
#tryinclude <sourcebanschecker>
#tryinclude <zombiereloaded>
#define REQUIRE_PLUGIN

#define CHAT_PREFIX "{gold}[Call Admin]{orchid}"

#pragma newdecls required

ConVar g_cvCooldown, g_cvAdmins, g_cvNetPublicAddr, g_cvPort;
ConVar g_cCountBots = null;
ConVar g_cvWebhook;

Handle g_hLastUse = INVALID_HANDLE;

int g_iLastUse[MAXPLAYERS+1] = { -1, ... }

bool g_bLate = false;
bool g_Plugin_AFKManager = false;
bool g_Plugin_ZR = false;
bool g_Plugin_SourceBans = false;

public Plugin myinfo = 
{
	name = "CallAdmin",
	author = "inGame, maxime1907, .Rushaway",
	description = "Send a calladmin message to discord and forum",
	version = "1.10.3",
	url = "https://nide.gg"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLate = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	RegConsoleCmd("sm_calladmin", Command_CallAdmin, "Send a message to call admins.");

	g_hLastUse = RegClientCookie("calladmin_last_use", "Last call admin", CookieAccess_Protected);

	g_cvWebhook = CreateConVar("sm_calladmin_webhook", "", "The webhook URL of your Discord channel.", FCVAR_PROTECTED);

	g_cvCooldown = CreateConVar("sm_calladmin_cooldown", "600", "Cooldown in seconds before a player can use sm_calladmin again", FCVAR_NONE);
	g_cCountBots = CreateConVar("sm_calladmin_count_bots", "0", "Should we count bots as players ?(1 = Yes, 0 = No)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvAdmins = CreateConVar("sm_calladmin_block", "0", "Block calladmin usage if an admin is online?(1 = Yes, 0 = No)", FCVAR_PROTECTED, true, 0.0, true, 1.0);

	AutoExecConfig(true);

	// Late load
	if (g_bLate)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

public void OnAllPluginsLoaded()
{
	g_Plugin_AFKManager = LibraryExists("AFKManager");
	g_Plugin_SourceBans = LibraryExists("sourcebans++");
	g_Plugin_ZR = LibraryExists("zombiereloaded");

	LogMessage("[CallAdmin] Capabilities: AFKManager: %s",
		(g_Plugin_AFKManager ? "Loaded" : "Not loaded"));
}

public void OnLibraryAdded(const char[] sName)
{
	if (strcmp(sName, "zombiereloaded", false) == 0)
		g_Plugin_ZR = true;
	if (strcmp(sName, "sourcebans++", false) == 0)
		g_Plugin_SourceBans = true;
}

public void OnLibraryRemoved(const char[] sName)
{
	if (strcmp(sName, "zombiereloaded", false) == 0)
		g_Plugin_ZR = false;
	if (strcmp(sName, "sourcebans++", false) == 0)
		g_Plugin_SourceBans = false;
}

public void OnClientPutInServer(int client)
{
	if (AreClientCookiesCached(client))
		ReadClientCookies(client);
}

public void OnClientDisconnect(int client)
{
	SetClientCookies(client);
}

public void OnClientCookiesCached(int client)
{
	ReadClientCookies(client);
}

public void ReadClientCookies(int client)
{
	char sValue[32];

	GetClientCookie(client, g_hLastUse, sValue, sizeof(sValue));
	g_iLastUse[client] = (sValue[0] == '\0' ? 0 : StringToInt(sValue));
}

public void SetClientCookies(int client)
{
	char sValue[32];

	Format(sValue, sizeof(sValue), "%i", g_iLastUse[client]);
	SetClientCookie(client, g_hLastUse, sValue);
}

public Action Command_CallAdmin(int client, int args)
{	
	if(!g_Plugin_AFKManager)
	{
		CReplyToCommand(client, "%s {red}ERROR: AFKManager Plugin not detected. Aborting.", CHAT_PREFIX);
		return Plugin_Handled;
	}

	if (!client)
	{
		ReplyToCommand(client, "[SM] Cannot use this command from server console.");
		return Plugin_Handled;
	}

	if (client)
	{
		bool bIsGagged = false;
		if (g_Plugin_SourceBans)
		{
#if defined _sourcecomms_included
			int iGagType = SourceComms_GetClientGagType(client);
			bIsGagged = iGagType > 0
#endif
		}
		else
		{
			bIsGagged = BaseComm_IsClientGagged(client)
		}

		if (bIsGagged)
		{
			CReplyToCommand(client, "%s You are not allowed to use {gold}Call Admin {orchid}since you are gagged.", CHAT_PREFIX);
			return Plugin_Handled;
		}
	}

	if(GetAdminFlag(GetUserAdmin(client), Admin_Ban))
	{
		CReplyToCommand(client, "%s You are an admin nigger, why the f*ck do you use that command?", CHAT_PREFIX);
		return Plugin_Handled;
	}

	int currentTime = GetTime();
	int cooldownDiff = currentTime - g_iLastUse[client];
	if (cooldownDiff < g_cvCooldown.IntValue)
	{
		CReplyToCommand(client, "%s You are on cooldown, wait {default}%d {orchid}seconds.", CHAT_PREFIX, g_cvCooldown.IntValue - cooldownDiff);
		return Plugin_Handled;
	}

	if(g_cvAdmins.IntValue >= 1)
	{
		int Admins = 0;
		int AfkAdmins = 0;

		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsClientInGame(i) || IsFakeClient(i))
				continue;

			if(GetAdminFlag(GetUserAdmin(i), Admin_Ban))
			{
				int IdleTime;
				IdleTime = GetClientIdleTime(i);
				if(IdleTime > 30) AfkAdmins++;
				Admins++;
			}
		}

		if(Admins > AfkAdmins)
		{
			CReplyToCommand(client, "%s You can't use {gold}CallAdmin {orchid}since there is admins online. Type {red}!admins {orchid}to check currently online admins.", CHAT_PREFIX);
			return Plugin_Handled;
		}
	}

	if(args < 1)
	{
		CReplyToCommand(client, "%s sm_calladmin <reason>", CHAT_PREFIX);
		return Plugin_Handled;
	}

	g_iLastUse[client] = currentTime;

	char sTime[64];
	int iTime = GetTime();
	FormatTime(sTime, sizeof(sTime), "Date : %d/%m/%Y @ %H:%M:%S", iTime);

	char sCount[64];
	int iMaxPlayers = MaxClients;
	int iConnected = GetClientCountEx(g_cCountBots.BoolValue);
	Format(sCount, sizeof(sCount), "Players : %d/%d", iConnected, iMaxPlayers);

	char sAliveCount[64];
	if (g_Plugin_ZR)
		Format(sAliveCount, sizeof(sAliveCount), "Alive : %d Humans - %d Zombies", GetTeamAliveCount(CS_TEAM_CT), GetTeamAliveCount(CS_TEAM_T));
	else
		Format(sAliveCount, sizeof(sAliveCount), "Alive : %d CTs - %d Ts", GetTeamAliveCount(CS_TEAM_CT), GetTeamAliveCount(CS_TEAM_T));

	g_cvNetPublicAddr = FindConVar("net_public_adr");
	g_cvPort = FindConVar("hostport");

	char sConnect[256];
	char sNetIP[32], sNetPort[32];
	if (g_cvPort != null)
		GetConVarString(g_cvPort, sNetPort, sizeof (sNetPort));
	if (g_cvNetPublicAddr != null)
		GetConVarString(g_cvNetPublicAddr, sNetIP, sizeof(sNetIP));
	Format(sConnect, sizeof(sConnect), "**steam://connect/%s:%s**", sNetIP, sNetPort);

	char sMessageDiscord[4096];
	GetCmdArgString(sMessageDiscord, sizeof(sMessageDiscord));
	ReplaceString(sMessageDiscord, sizeof(sMessageDiscord), "\\n", "\n");

	char sAuth[32];
	GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth), true);

	/*		>> Will implant this when Discord will have custom link... <<
	char sInfos[2048], sClientID[256], sSteamClientID[64];	
	GetClientAuthId(client, AuthId_SteamID64, sSteamClientID, sizeof(sSteamClientID));
	Format(sClientID, sizeof(sClientID), "More infos about the caller:  %s (https://steamcommunity.com/profiles/%s)", client, sSteamClientID);*/

	char currentMap[PLATFORM_MAX_PATH];
	GetCurrentMap(currentMap, sizeof(currentMap));

	char sTimeLeft[32];
	int timeleft;
	if(GetMapTimeLeft(timeleft))
	{
		if(timeleft > 0)
			Format(sTimeLeft, sizeof(sTimeLeft), "%i:%02i", timeleft / 60, timeleft % 60);
		else if(timeleft <= 0)
			Format(sTimeLeft, sizeof(sTimeLeft), "Last Round");
	}

	char sPluginVersion[256];
	GetPluginInfo(INVALID_HANDLE, PlInfo_Version, sPluginVersion, sizeof(sPluginVersion));

	// Generate discord message
	if (g_Plugin_SourceBans)
	{
		int iClientBans = 0;
		int iClientComms = 0;

	#if defined _sourcebanschecker_included
		iClientBans = SBPP_CheckerGetClientsBans(client);
		iClientComms = SBPP_CheckerGetClientsComms(client);
	#endif

		Format(sMessageDiscord, sizeof(sMessageDiscord), "@here ```%N (%d bans - %d comms) [%s] is calling an Admin. \nCurrent map : %s \n%s \n%s \n%s \nTimeLeft : %s \nReason: %s```(*v%s*) **Quick join:** %s", client, iClientBans, iClientComms, sAuth, currentMap, sTime, sAliveCount, sCount, sTimeLeft, sMessageDiscord, sPluginVersion, sConnect);
	}
	else
	{
		Format(sMessageDiscord, sizeof(sMessageDiscord), "@here ```%N [%s] is calling an Admin. \nCurrent map : %s \n%s \n%s \n%s \nTimeLeft : %s \nReason: %s```(*v%s*) **Quick join:** %s", client, sAuth, currentMap, sTime, sAliveCount, sCount, sTimeLeft, sMessageDiscord, sPluginVersion, sConnect);
	}

	char szWebhookURL[1000];
	g_cvWebhook.GetString(szWebhookURL, sizeof szWebhookURL);
	if(!szWebhookURL[0])
	{
		LogError("[CallAdmin] No webhook found or specified.");
		return Plugin_Handled;
	}
	
	Webhook webhook = new Webhook(sMessageDiscord);

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteCell(view_as<int>(webhook));
	pack.WriteString(szWebhookURL);

	webhook.Execute(szWebhookURL, OnWebHookExecuted, pack);

	return Plugin_Handled;
}

stock int GetClientCountEx(bool countBots)
{
	int iRealClients = 0;
	int iFakeClients = 0;

	for(int player = 1; player <= MaxClients; player++)
	{
		if(IsClientConnected(player))
		{
			if(IsFakeClient(player))
				iFakeClients++;
			else
				iRealClients++;
		}
	}
	return countBots ? iFakeClients + iRealClients : iRealClients;
}

stock int GetTeamAliveCount(int team)
{
	int count = 0;
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i))
			continue;
		if(IsPlayerAlive(i) && GetClientTeam(i) == team)
			count++;
	}
	return count;
}

public void OnWebHookExecuted(HTTPResponse response, DataPack pack)
{
	static int retries;
	
	pack.Reset();
	int userid = pack.ReadCell();
	int client = GetClientOfUserId(userid);
	Webhook hook = view_as<Webhook>(pack.ReadCell());

	if (!client || !IsClientInGame(client))
	{
		delete hook;
		delete pack;
		return;
	}

	if (response.Status != HTTPStatus_OK)
	{
		if(retries < 3)
			CPrintToChat(client, "%s {red}Failed to send your message. Resending it .. (%d/3)", CHAT_PREFIX, retries);
		
		else if(retries >= 3)
		{
			CPrintToChat(client, "%s {red}An error has occurred. Your message can't be sent.", CHAT_PREFIX);
			LogError("[CallAdmin] Message can't be sent after %d retries.", retries);
			delete hook;
			delete pack;
			return;
		}
		
		char webhookURL[PLATFORM_MAX_PATH];
		pack.ReadString(webhookURL, sizeof(webhookURL));
		
		DataPack newPack;
		CreateDataTimer(0.5, ExecuteWebhook_Timer, newPack);
		newPack.WriteCell(userid);
		newPack.WriteCell(view_as<int>(hook));
		newPack.WriteString(webhookURL);
		retries++;
	}
	else
	{	
		CPrintToChat(client, "%s Message sent.\nRemember that abuse/spam of {gold}CallAdmin {orchid}will result your block from chat", CHAT_PREFIX);
		retries = 0;
	}
	
	delete pack;
	delete hook;
	retries = 0;
}

Action ExecuteWebhook_Timer(Handle timer, DataPack pack)
{
	pack.Reset();
	int userid = pack.ReadCell();
	Webhook hook = view_as<Webhook>(pack.ReadCell());
	
	char webhookURL[PLATFORM_MAX_PATH];
	pack.ReadString(webhookURL, sizeof(webhookURL));
	
	DataPack newPack = new DataPack();
	newPack.WriteCell(userid);
	newPack.WriteCell(view_as<int>(hook));
	newPack.WriteString(webhookURL);	
	hook.Execute(webhookURL, OnWebHookExecuted, newPack);
	return Plugin_Continue;
}
