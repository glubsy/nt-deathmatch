
/*=========================
VOTE from funvotes
=========================*/
#define VOTE_NO "###no###"
#define VOTE_YES "###yes###"


Menu g_hVoteMenu = null;

ConVar g_Cvar_Limits[5] = {null, ...};
ConVar g_Cvar_Neorestart;
ConVar g_Cvar_TDM;
ConVar g_Cvar_KF;
ConVar g_Cvar_Healthkits;
ConVar g_Cvar_KF_Hardcore;

enum voteType
{
	neorestart, // = 0,
	tdm,
	kf,
	healthkits,
	kf_hardcore
};
new voteType:g_voteType = voteType:neorestart;
#define VOTE_CLIENTID	0
#define VOTE_USERID	1
//new g_voteClient[2];		/* Holds the target's client id and user id */

#define VOTE_NAME	0
#define VOTE_AUTHID	1
#define	VOTE_IP		2
new String:g_voteInfo[3][65];	/* Holds the target's name, authid, and IP */

TopMenu hTopMenu;
/*=========================
		VOTE
=========================*/
void InitVoteCvars()
{
	RegAdminCmd("sm_voterestart", Command_VoteNeoRestart, 0, "sm_voterestart");
	RegAdminCmd("sm_votetdm", Command_VoteTDM, 0, "sm_votetdm");
	RegAdminCmd("sm_votekf", Command_VoteKF, 0, "sm_votekf");
	RegAdminCmd("sm_votehealthkits", Command_VoteHealthkits, 0, "sm_votehealthkits");
	RegAdminCmd("sm_votekfhardcore", Command_VoteKF_Hardcore, 0, "sm_votekfhardcore");
	
	g_Cvar_Limits[0] = CreateConVar("sm_vote_restart", "0.60", "percent required for successful round restart.", 0, true, 0.05, true, 1.0);
	g_Cvar_Limits[1] = CreateConVar("sm_vote_tdm", "0.60", "percent required for successful TDM start.", 0, true, 0.05, true, 1.0);
	g_Cvar_Limits[2] = CreateConVar("sm_vote_kf", "0.60", "percent required for successful Kill Confirmed mode start.", 0, true, 0.05, true, 1.0);
	g_Cvar_Limits[3] = CreateConVar("sm_vote_healthkits", "0.60", "percent required to disable random healthkit spawning.", 0, true, 0.05, true, 1.0);
	g_Cvar_Limits[4] = CreateConVar("sm_vote_kf_hardcore", "0.60", "percent required to disable Kill Confirmed HARDCORE mode.", 0, true, 0.05, true, 1.0);
	
	g_Cvar_Neorestart = FindConVar("neo_restart_this");
	g_Cvar_TDM = FindConVar("nt_tdm_enabled");
	g_Cvar_KF = FindConVar("nt_tdm_kf_enabled");
	g_Cvar_Healthkits = FindConVar("nt_healthkitdrop");
	g_Cvar_KF_Hardcore = FindConVar("nt_tdm_kf_hardcore_enabled");
	
	CreateTimer(5.0, CheckLateCvars);
	
	/* Account for late loading */
	TopMenu topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null))
	{
		OnAdminMenuReady(topmenu);
	}
}



public Action:CheckLateCvars(Handle:timer)
{
	g_Cvar_TDM = FindConVar("nt_tdm_enabled");
	g_Cvar_KF = FindConVar("nt_tdm_kf_enabled");
	g_Cvar_Healthkits = FindConVar("nt_healthkitdrop");
	g_Cvar_KF_Hardcore = FindConVar("nt_tdm_kf_hardcore_enabled");
}

public OnAdminMenuReady(Handle aTopMenu)
{
	TopMenu topmenu = TopMenu.FromHandle(aTopMenu);

	/* Block us from being called twice */
	if (topmenu == hTopMenu)
	{
		return;
	}
	
	/* Save the Handle */
	hTopMenu = topmenu;
	
	/* Build the "Voting Commands" category */
	new TopMenuObject:voting_commands = hTopMenu.FindCategory(ADMINMENU_VOTINGCOMMANDS);

	if (voting_commands != INVALID_TOPMENUOBJECT)
	{
		hTopMenu.AddItem("sm_voterestartthis", AdminMenu_VoteNeoRestart, voting_commands, "sm_voterestartthis", ADMFLAG_VOTE);
		hTopMenu.AddItem("sm_votetdm", AdminMenu_VoteTDM, voting_commands, "sm_votetdm", ADMFLAG_VOTE);
		hTopMenu.AddItem("sm_votekf", AdminMenu_VoteKF, voting_commands, "sm_votekf", ADMFLAG_VOTE);
		hTopMenu.AddItem("sm_votehealthkits", AdminMenu_VoteHealthkits, voting_commands, "sm_votehealthkits", ADMFLAG_VOTE);
		hTopMenu.AddItem("sm_votekfhardcore", AdminMenu_VoteKF_Hardcore, voting_commands, "sm_votekfhardcore", ADMFLAG_VOTE);
	}
}


public Handler_VoteCallback(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		VoteMenuClose();
	}
	else if (action == MenuAction_Display)
	{
	 	char title[64];
		menu.GetTitle(title, sizeof(title));

	 	char buffer[255];
		Format(buffer, sizeof(buffer), "%s", title, param1, g_voteInfo[VOTE_NAME]);

		Panel panel = Panel:param2;
		panel.SetTitle(buffer);
	}
	else if (action == MenuAction_DisplayItem)
	{
		char display[64];
		menu.GetItem(param2, "", 0, _, display, sizeof(display));
	 
	 	if (strcmp(display, VOTE_NO) == 0 || strcmp(display, VOTE_YES) == 0)
	 	{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%s", display, param1);

			return RedrawMenuItem(buffer);
		}
	} 
	/* else if (action == MenuAction_Select)
	{
		VoteSelect(menu, param1, param2);
	}*/
	else if (action == MenuAction_VoteCancel && param1 == VoteCancel_NoVotes)
	{
		PrintToChatAll("[SM] No Votes Cast");
	}
	else if (action == MenuAction_VoteEnd)
	{
		char item[64];
		float percent, limit;
		int votes, totalVotes;

		GetMenuVoteInfo(param2, votes, totalVotes);
		menu.GetItem(param1, item, sizeof(item));
		
		if (strcmp(item, VOTE_NO) == 0 && param1 == 1)
		{
			votes = totalVotes - votes; // Reverse the votes to be in relation to the Yes option.
		}
		
		percent = GetVotePercent(votes, totalVotes);
		
		limit = g_Cvar_Limits[g_voteType].FloatValue;
		
		// A multi-argument vote is "always successful", but have to check if its a Yes/No vote.
		if ((strcmp(item, VOTE_YES) == 0 && FloatCompare(percent,limit) < 0 && param1 == 0) || (strcmp(item, VOTE_NO) == 0 && param1 == 1))
		{
			//TODO: g_voteClient[userid] should be used here and set to -1 if not applicable.
			LogAction(-1, -1, "Vote failed.");
			PrintToChatAll("[SM] Vote Failed", RoundToNearest(100.0*limit), RoundToNearest(100.0*percent), totalVotes);
		}
		else
		{
			PrintToChatAll("[SM] Vote Successful", RoundToNearest(100.0*percent), totalVotes);
			
			switch (g_voteType)
			{
				case (voteType:neorestart):
				{
					PrintToChatAll("RESTARTING CURRENT ROUND! Cvar changed", "neo_restart_this", (g_Cvar_Neorestart.BoolValue ? "0" : "1"));
					LogAction(-1, -1, "Restarting round due to vote.", (g_Cvar_Neorestart.BoolValue ? "0" : "1"));
					g_Cvar_Neorestart.BoolValue = !g_Cvar_Neorestart.BoolValue;
				}
				case (voteType:tdm):
				{
					PrintToChatAll("[SM] Cvar changed", "nt_tdm_enabled", (g_Cvar_TDM.BoolValue ? "0" : "1"));
					LogAction(-1, -1, "Changing TDM state due to vote.", (g_Cvar_TDM.BoolValue ? "0" : "1"));
					g_Cvar_TDM.BoolValue = !g_Cvar_TDM.BoolValue;
				}
				case (voteType:kf):
				{
					PrintToChatAll("[SM] Cvar changed", "nt_tdm_kf_enabled", (g_Cvar_KF.BoolValue ? "0" : "1"));
					LogAction(-1, -1, "Changing KF state due to vote.", (g_Cvar_KF.BoolValue ? "0" : "1"));
					g_Cvar_KF.BoolValue = !g_Cvar_KF.BoolValue;
				}
				case (voteType:healthkits):
				{
					PrintToChatAll("[SM] Cvar changed", "nt_healthkitdrop", (g_Cvar_Healthkits.BoolValue ? "0" : "1"));
					LogAction(-1, -1, "Changing healthkitdrop state due to vote.", (g_Cvar_Healthkits.BoolValue ? "0" : "1"));
					g_Cvar_Healthkits.BoolValue = !g_Cvar_Healthkits.BoolValue;
				}
				case (voteType:kf_hardcore):
				{
					PrintToChatAll("[SM] Cvar changed", "nt_tdm_kf_hardcore_enabled", (g_Cvar_KF_Hardcore.BoolValue ? "0" : "1"));
					LogAction(-1, -1, "Changing KF Hardcore state due to vote.", (g_Cvar_KF_Hardcore.BoolValue ? "0" : "1"));
					g_Cvar_KF_Hardcore.BoolValue = !g_Cvar_KF_Hardcore.BoolValue;
				}
			}
		}
	}
	
	return 0;
}


VoteMenuClose()
{
	delete g_hVoteMenu;
	g_hVoteMenu = null;
}

Float:GetVotePercent(votes, totalVotes)
{
	return FloatDiv(float(votes),float(totalVotes));
}

bool:TestVoteDelay(client)
{
 	new delay = CheckVoteDelay();
 	
 	if (delay > 0)
 	{
 		if (delay > 60)
 		{
 			ReplyToCommand(client, "[SM] Vote Delay Minutes %i", delay % 60);
 		}
 		else
 		{
 			ReplyToCommand(client, "[SM] Vote Delay Seconds %i", delay);
 		}
 		
 		return false;
 	}
 	
	return true;
}






























DisplayVoteNeoRestartMenu(client)
{
	if (IsVoteInProgress())
	{
		ReplyToCommand(client, "[SM] Vote in Progress");
		return;
	}	
	
	if (!TestVoteDelay(client))
	{
		return;
	}
	
	LogAction(client, -1, "\"%L\" initiated an NeoRestart vote.", client);
	ShowActivity2(client, "[SM]", "Initiated Vote NeoRestart");
	
	g_voteType = voteType:neorestart;
	g_voteInfo[VOTE_NAME][0] = '\0';

	g_hVoteMenu = CreateMenu(Handler_VoteCallback, MenuAction:MENU_ACTIONS_ALL);
	
	if (g_Cvar_Neorestart.BoolValue)
	{
		g_hVoteMenu.SetTitle("VoteNeorestart Off");
	}
	else
	{
		g_hVoteMenu.SetTitle("VoteNeorestart On");
	}
	
	g_hVoteMenu.AddItem(VOTE_YES, "Yes");
	g_hVoteMenu.AddItem(VOTE_NO, "No");
	g_hVoteMenu.ExitButton = false;
	g_hVoteMenu.DisplayVoteToAll(20);
}


public AdminMenu_VoteNeoRestart(Handle:topmenu, 
							  TopMenuAction:action,
							  TopMenuObject:object_id,
							  param,
							  String:buffer[],
							  maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "NeoRestart vote", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		DisplayVoteNeoRestartMenu(param);
	}
	else if (action == TopMenuAction_DrawOption)
	{	
		/* disable this option if a vote is already running */
		buffer[0] = !IsNewVoteAllowed() ? ITEMDRAW_IGNORE : ITEMDRAW_DEFAULT;
	}
}

public Action:Command_VoteNeoRestart(client, args)
{
	if (args > 0)
	{
		ReplyToCommand(client, "[SM] Usage: sm_voterestart");
		return Plugin_Handled;	
	}
	
	DisplayVoteNeoRestartMenu(client);
	
	return Plugin_Handled;
}







DisplayVoteTDMMenu(client)
{
	if (IsVoteInProgress())
	{
		ReplyToCommand(client, "[SM] Vote in Progress");
		return;
	}	
	
	if (!TestVoteDelay(client))
	{
		return;
	}
	
	LogAction(client, -1, "\"%L\" initiated a TDM vote.", client);
	ShowActivity2(client, "[SM]", "Initiated Vote TDM");
	
	g_voteType = voteType:tdm;
	g_voteInfo[VOTE_NAME][0] = '\0';

	g_hVoteMenu = CreateMenu(Handler_VoteCallback, MenuAction:MENU_ACTIONS_ALL);
	
	if (g_Cvar_TDM.BoolValue)
	{
		g_hVoteMenu.SetTitle("Vote Team DeathMatch Off");
	}
	else
	{
		g_hVoteMenu.SetTitle("Vote Team DeathMatch On");
	}
	
	g_hVoteMenu.AddItem(VOTE_YES, "Yes");
	g_hVoteMenu.AddItem(VOTE_NO, "No");
	g_hVoteMenu.ExitButton = false;
	g_hVoteMenu.DisplayVoteToAll(20);
}


public AdminMenu_VoteTDM(Handle:topmenu, 
							  TopMenuAction:action,
							  TopMenuObject:object_id,
							  param,
							  String:buffer[],
							  maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "TeamDeathMatch vote", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		DisplayVoteTDMMenu(param);
	}
	else if (action == TopMenuAction_DrawOption)
	{	
		/* disable this option if a vote is already running */
		buffer[0] = !IsNewVoteAllowed() ? ITEMDRAW_IGNORE : ITEMDRAW_DEFAULT;
	}
}

public Action:Command_VoteTDM(client, args)
{
	if (args > 0)
	{
		ReplyToCommand(client, "[SM] Usage: sm_voteTDM");
		return Plugin_Handled;	
	}
	
	DisplayVoteTDMMenu(client);
	
	return Plugin_Handled;
}



DisplayVoteKFMenu(client)
{
	if (IsVoteInProgress())
	{
		ReplyToCommand(client, "[SM] Vote in Progress");
		return;
	}	
	
	if (!TestVoteDelay(client))
	{
		return;
	}
	
	LogAction(client, -1, "\"%L\" initiated a vote for Kill Confirmed.", client);
	ShowActivity2(client, "[SM]", "Initiated Vote KF");
	
	g_voteType = voteType:kf;
	g_voteInfo[VOTE_NAME][0] = '\0';

	g_hVoteMenu = CreateMenu(Handler_VoteCallback, MenuAction:MENU_ACTIONS_ALL);
	
	if (g_Cvar_TDM.BoolValue)
	{
		g_hVoteMenu.SetTitle("Vote Kill Confirmed mode Off");
	}
	else
	{
		g_hVoteMenu.SetTitle("Vote Kill Confirmed mode On");
	}
	
	g_hVoteMenu.AddItem(VOTE_YES, "Yes");
	g_hVoteMenu.AddItem(VOTE_NO, "No");
	g_hVoteMenu.ExitButton = false;
	g_hVoteMenu.DisplayVoteToAll(20);
}


public AdminMenu_VoteKF(Handle:topmenu, 
							  TopMenuAction:action,
							  TopMenuObject:object_id,
							  param,
							  String:buffer[],
							  maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "Kill Confirmed vote", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		DisplayVoteKFMenu(param);
	}
	else if (action == TopMenuAction_DrawOption)
	{	
		/* disable this option if a vote is already running */
		buffer[0] = !IsNewVoteAllowed() ? ITEMDRAW_IGNORE : ITEMDRAW_DEFAULT;
	}
}

public Action:Command_VoteKF(client, args)
{
	if (args > 0)
	{
		ReplyToCommand(client, "[SM] Usage: sm_voteKF");
		return Plugin_Handled;	
	}
	
	DisplayVoteKFMenu(client);
	
	return Plugin_Handled;
}





DisplayVoteHealthkitsMenu(client)
{
	if (IsVoteInProgress())
	{
		ReplyToCommand(client, "[SM] Vote in Progress");
		return;
	}	
	
	if (!TestVoteDelay(client))
	{
		return;
	}
	
	LogAction(client, -1, "\"%L\" initiated a vote about healthkits.", client);
	ShowActivity2(client, "[SM]", "Initiated Vote healthkits");
	
	g_voteType = voteType:healthkits;
	g_voteInfo[VOTE_NAME][0] = '\0';

	g_hVoteMenu = CreateMenu(Handler_VoteCallback, MenuAction:MENU_ACTIONS_ALL);
	
	if (g_Cvar_Healthkits.BoolValue)
	{
		g_hVoteMenu.SetTitle("Vote healthkit drops Off");
	}
	else
	{
		g_hVoteMenu.SetTitle("Vote healthkit drops On");
	}
	
	g_hVoteMenu.AddItem(VOTE_YES, "Yes");
	g_hVoteMenu.AddItem(VOTE_NO, "No");
	g_hVoteMenu.ExitButton = false;
	g_hVoteMenu.DisplayVoteToAll(20);
}


public AdminMenu_VoteHealthkits(Handle:topmenu, 
							  TopMenuAction:action,
							  TopMenuObject:object_id,
							  param,
							  String:buffer[],
							  maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "Healthkit drops vote", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		DisplayVoteHealthkitsMenu(param);
	}
	else if (action == TopMenuAction_DrawOption)
	{	
		/* disable this option if a vote is already running */
		buffer[0] = !IsNewVoteAllowed() ? ITEMDRAW_IGNORE : ITEMDRAW_DEFAULT;
	}
}

public Action:Command_VoteHealthkits(client, args)
{
	if (args > 0)
	{
		ReplyToCommand(client, "[SM] Usage: sm_voteHealthkits");
		return Plugin_Handled;	
	}
	
	DisplayVoteHealthkitsMenu(client);
	
	return Plugin_Handled;
}





DisplayVoteKF_Hardcore_Menu(client)
{
	if (IsVoteInProgress())
	{
		ReplyToCommand(client, "[SM] Vote in Progress");
		return;
	}	
	
	if (!TestVoteDelay(client))
	{
		return;
	}
	
	LogAction(client, -1, "\"%L\" initiated a vote about KF Hardcore mode.", client);
	ShowActivity2(client, "[SM]", "Initiated Vote about Kill Confirmed Hardcore mode.");
	
	g_voteType = voteType:kf_hardcore;
	g_voteInfo[VOTE_NAME][0] = '\0';

	g_hVoteMenu = CreateMenu(Handler_VoteCallback, MenuAction:MENU_ACTIONS_ALL);
	
	if (g_Cvar_KF_Hardcore.BoolValue)
	{
		g_hVoteMenu.SetTitle("Vote Kill Confirmed HARCDORE mode Off");
	}
	else
	{
		g_hVoteMenu.SetTitle("Vote Kill Confirmed HARCDORE mode On");
	}
	
	g_hVoteMenu.AddItem(VOTE_YES, "Yes");
	g_hVoteMenu.AddItem(VOTE_NO, "No");
	g_hVoteMenu.ExitButton = false;
	g_hVoteMenu.DisplayVoteToAll(20);
}


public AdminMenu_VoteKF_Hardcore(Handle:topmenu, 
							  TopMenuAction:action,
							  TopMenuObject:object_id,
							  param,
							  String:buffer[],
							  maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "Kill Confirmed HARDCORE vote", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		DisplayVoteHealthkitsMenu(param);
	}
	else if (action == TopMenuAction_DrawOption)
	{	
		/* disable this option if a vote is already running */
		buffer[0] = !IsNewVoteAllowed() ? ITEMDRAW_IGNORE : ITEMDRAW_DEFAULT;
	}
}

public Action:Command_VoteKF_Hardcore(client, args)
{
	if (args > 0)
	{
		ReplyToCommand(client, "[SM] Usage: sm_votekfhardcore");
		return Plugin_Handled;	
	}
	
	DisplayVoteKF_Hardcore_Menu(client);
	
	return Plugin_Handled;
}
