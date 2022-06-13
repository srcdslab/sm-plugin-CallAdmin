#include <sourcemod>
#include <AFKManager>
#include <Discord>
#include <clientprefs>
#include <multicolors>
#include <basecomm>
#tryinclude <sourcecomms>
#tryinclude <sourcebanschecker>
#tryinclude <sourcecomms>

#define PLUGIN_VERSION "1.6"
#define CHAT_PREFIX "{gold}[Call Admin]{orchid}"

#pragma newdecls required

char sNetIP[32], sNetPort[32];

ConVar g_cvCooldown, g_cvAdmins, g_cvNetPublicAddr, g_cvPort;
ConVar g_cCountBots = null;

Handle g_hLastUse = INVALID_HANDLE;

int g_iLastUse[MAXPLAYERS+1] = { -1, ... }

bool g_bLate = false;
bool g_Plugin_AFKManager;

public Plugin myinfo = 
{
	name = "CallAdmin",
	author = "inGame, maxime1907, .Rushaway",
	description = "Send a calladmin message to discord and forum",
	version = PLUGIN_VERSION,
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

	g_cvCooldown = CreateConVar("sm_calladmin_cooldown", "600", "Cooldown in seconds before a player can use sm_calladmin again", FCVAR_NONE);
	g_cCountBots = CreateConVar("sm_calladmin_count_bots", "0", "Should we count bots as players ?(1 = Yes, 0 = No)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvAdmins = CreateConVar("sm_calladmin_block", "0", "Block calladmin usage if an admin is online?(1 = Yes, 0 = No)", FCVAR_PROTECTED, true, 0.0, true, 1.0);

	g_cvNetPublicAddr  = FindConVar("net_public_adr");
	if (g_cvNetPublicAddr != null)
		g_cvNetPublicAddr.GetString(sNetIP, sizeof(sNetIP));
		
	g_cvPort = FindConVar("hostport");
	g_cvPort.GetString(sNetPort, sizeof (sNetPort));

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

public void OnAllPluginsLoaded()
{
	g_Plugin_AFKManager = LibraryExists("AFKManager");

	LogMessage("CallAdmin capabilities:\nAFKManager:",
		(g_Plugin_AFKManager ? "loaded" : "not loaded"));
}

public Action Command_CallAdmin(int client, int args)
{	
	if(!g_Plugin_AFKManager)
	{
		CReplyToCommand(client, "%s AFKManager plugin required", CHAT_PREFIX);
		LogMessage("[CallAdmin] AFKManager plugin required");
		return Plugin_Handled;
	}

	if (!client)
	{
		ReplyToCommand(client, "[SM] Cannot use this command from server console.");
		return Plugin_Handled;
	}

	#if defined _sourcecomms_included
		if (client)
		{
			int IsGagged = SourceComms_GetClientGagType(client);
			if(IsGagged > 0)
			{
				CReplyToCommand(client, "%s You are not allowed to use {gold}Call Admin {orchid}since you are gagged.", CHAT_PREFIX);
				return Plugin_Handled;
			}
		}
	#else
		if (BaseComm_IsClientGagged(client))
		{
			CReplyToCommand(client, "%s You are not allowed to use {gold}Call Admin {orchid}since you are gagged.", CHAT_PREFIX);
			return Plugin_Handled;
		}
	#endif

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

	char sWebhook[64];
	Format(sWebhook, sizeof(sWebhook), "calladmin");

	char sTime[64];
	int iTime = GetTime();
	FormatTime(sTime, sizeof(sTime), "Date : %d/%m/%Y @ %H:%M:%S", iTime);

	char sCount[64];
	int iMaxPlayers = MaxClients;
	int iConnected = GetClientCountEx(g_cCountBots.BoolValue);
	Format(sCount, sizeof(sCount), "Players : %d/%d", iConnected, iMaxPlayers);

	char sConnect[256];
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
	
	// Generate discord message
	#if defined _sourcebanschecker_included
		Format(sMessageDiscord, sizeof(sMessageDiscord), "@here ```%N (%d bans - %d comms) [%s] is calling an Admin. \nCurrent map : %s \n%s \n%s \nReason: %s```(*v%s*) **Quick connect shortcut:** %s", client, SBCheckerGetClientsBans(client), SBCheckerGetClientsComms(client), sAuth, currentMap, sTime, sCount, sMessageDiscord, PLUGIN_VERSION, sConnect);
	#else
		Format(sMessageDiscord, sizeof(sMessageDiscord), "@here ```%N [%s] is calling an Admin. \nCurrent map : %s \n%s \n%s \nReason: %s```(*v%s*) **Quick connect shortcut:** %s", client, sAuth, currentMap, sTime, sCount, sMessageDiscord, PLUGIN_VERSION, sConnect);
	#endif

	if (!Discord_SendMessage(sWebhook, sMessageDiscord))
	{
		CReplyToCommand(client, "%s {red}Failed to send your message.", CHAT_PREFIX);
		return Plugin_Handled;
	}

	CReplyToCommand(client, "%s Message sent.\nRemember that abuse/spam of {gold}CallAdmin {orchid}will result your block from chat", CHAT_PREFIX);
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
