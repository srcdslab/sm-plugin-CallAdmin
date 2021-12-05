#include <sourcemod>
#include <sourcecomms>
#include <AFKManager>
#include <Discord>
#include <clientprefs>

#define PLUGIN_VERSION "1.1"

#pragma newdecls required

ConVar g_cvServerName, g_cvCooldown;

Handle g_hLastUse = INVALID_HANDLE;

int g_iLastUse[MAXPLAYERS+1] = { -1, ... }

bool g_Plugin_AFKManager;

bool g_bLate = false;

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

	g_cvServerName = CreateConVar("sm_calladmin_servername", "ServerName", "Server Name", FCVAR_NONE);
	g_cvCooldown = CreateConVar("sm_calladmin_cooldown", "600", "Cooldown in seconds before a player can use sm_calladmin again", FCVAR_NONE);

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
		ReplyToCommand(client, "\x04[Call Admin] \x03AFKManager plugin required");
		LogMessage("[CallAdmin] AFKManager plugin required");
		return Plugin_Handled;
	}

	int IsGagged = SourceComms_GetClientGagType(client);
	
	if(IsGagged > 0)
	{
		ReplyToCommand(client, "\x04[Call Admin] \x03You are not allowed to use \x04Call Admin \x03since you are gagged.");
		return Plugin_Handled;
	}

	if(GetAdminFlag(GetUserAdmin(client), Admin_Generic))
	{
		ReplyToCommand(client, "\x04[Call Admin] \x03You are an admin nigger, why the f*ck do you use that command?");
		return Plugin_Handled;
	}

	int currentTime = GetTime();
	int cooldownDiff = currentTime - g_iLastUse[client];
	if (cooldownDiff < g_cvCooldown.IntValue)
	{
		ReplyToCommand(client, "\x04[Call Admin] \x03You are on cooldown, wait %d seconds.", g_cvCooldown.IntValue - cooldownDiff);
		return Plugin_Handled;
	}

	int Admins = 0;
	int AfkAdmins = 0;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || IsFakeClient(i))
			continue;

		if(GetAdminFlag(GetUserAdmin(i), Admin_Generic))
		{
			int IdleTime;
			IdleTime = GetClientIdleTime(i);
			if(IdleTime > 30) AfkAdmins++;
			Admins++;
		}
	}

	if(Admins > AfkAdmins)
	{
		ReplyToCommand(client, "\x04[Call Admin] \x03You can't use \x04CallAdmin \x03since there is admins online. Type \x04!admins \x03to check currently online admins.");
		return Plugin_Handled;
	}
	
	if(args < 1)
	{
		ReplyToCommand(client, "\x04[Call Admin] \x03sm_calladmin <reason>");
		return Plugin_Handled;
	}

	g_iLastUse[client] = currentTime;

	char sWebhook[64];
	Format(sWebhook, sizeof(sWebhook), "calladmin");

	char sMessageDiscord[4096];
	GetCmdArgString(sMessageDiscord, sizeof(sMessageDiscord));
	
	char sAuth[32], ServerName[64];
	GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth), true);

	char currentMap[PLATFORM_MAX_PATH];
	GetCurrentMap(currentMap, sizeof(currentMap));

	GetConVarString(g_cvServerName, ServerName, sizeof(ServerName));
	
	// Generate discord message
	Format(sMessageDiscord, sizeof(sMessageDiscord), "@here Player **%N** [ *%s* ] just called admin on ***%S*** with reason: ```%s```", client,  sAuth, currentMap, sMessageDiscord);

	if (!Discord_SendMessage(sWebhook, sMessageDiscord))
	{
		ReplyToCommand(client, "\x04[Call Admin] \x03Failed to send your message.");
		return Plugin_Handled;
	}

	ReplyToCommand(client, "\x04[Call Admin] \x03Message sent.\nRemember that abuse/spam of \x04CallAdmin \x03will result your block from chat");
	return Plugin_Handled;
}
