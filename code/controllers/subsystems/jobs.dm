#define GET_RANDOM_JOB 0
#define BE_ASSISTANT 1
#define RETURN_TO_LOBBY 2

SUBSYSTEM_DEF(jobs)
	name = "Jobs"
	flags = SS_NO_FIRE
	init_order = INIT_ORDER_JOBS

	//List of all jobs
	var/list/occupations = list()
	//Associative list of all jobs, by type
	var/list/occupations_by_type
	//Associative list of all jobs, by title
	var/list/occupations_by_title
	//Players who need jobs
	var/list/unassigned = list()
	//Debug info
	var/list/job_debug = list()

/datum/controller/subsystem/jobs/Initialize(start_timeofday)
	SetupOccupations(TRUE)
	LoadJobs("config/jobs.txt")

/datum/controller/subsystem/jobs/proc/SetupOccupations(var/setup_titles = 0)
	occupations = list()
	occupations_by_type = list()
	occupations_by_title = list()
	var/list/all_jobs = GLOB.using_map.allowed_jobs
	if(!all_jobs.len)
		log_error("<span class='warning'>Error setting up jobs, no job datums found!</span>")
		return 0
	for(var/J in all_jobs)
		var/datum/job/job = decls_repository.get_decl(J)
		if(!job)	continue
		occupations += job
		occupations_by_type[job.type] = job
		occupations_by_title[job.title] = job
		job.current_positions = 0
		for(var/alt_title in job.alt_titles)
			occupations_by_title[alt_title] = job
		if(!setup_titles) continue
		if(job.department_flag & COM)
			GLOB.command_positions |= job.title
		if(job.department_flag & SPT)
			GLOB.support_positions |= job.title
		if(job.department_flag & SEC)
			GLOB.security_positions |= job.title
		if(job.department_flag & ENG)
			GLOB.engineering_positions += job.title
		if(job.department_flag & MED)
			GLOB.medical_positions |= job.title
		if(job.department_flag & SCI)
			GLOB.science_positions |= job.title
		if(job.department_flag & EXP)
			GLOB.exploration_positions |= job.title
		if(job.department_flag & SUP)
			GLOB.supply_positions |= job.title
		if(job.department_flag & SRV)
			GLOB.service_positions |= job.title
		if(job.department_flag & CIV)
			GLOB.civilian_positions |= job.title
		if(job.department_flag & MSC)
			GLOB.nonhuman_positions |= job.title
		if(job.department_flag & PIL)
			GLOB.pilgrim_positions |= job.title

		if(job.social_class > SOCIAL_CLASS_MED)
			GLOB.nobles |= job.title

	return 1


/datum/controller/subsystem/jobs/proc/Debug(var/text)
	if(!Debug2)	return 0
	job_debug.Add(text)
	return 1


/datum/controller/subsystem/jobs/proc/GetJob(var/rank)
	if(!rank)	return null
	for(var/datum/job/J in occupations)
		if(!J)	continue
		if(J.title == rank)	return J
	return null

/datum/controller/subsystem/jobs/proc/ShouldCreateRecords(var/rank)
	if(!rank) return 0
	var/datum/job/job = GetJob(rank)
	if(!job) return 0
	return job.create_record

/datum/controller/subsystem/jobs/proc/GetPlayerAltTitle(mob/new_player/player, rank)
	return player.client.prefs.GetPlayerAltTitle(GetJob(rank))

/datum/controller/subsystem/jobs/proc/AssignRole(var/mob/new_player/player, var/rank, var/latejoin = 0)
	Debug("Running AR, Player: [player], Rank: [rank], LJ: [latejoin]")
	if(player && player.mind && rank)
		var/datum/job/job = GetJob(rank)
		if(!job)
			return 0
		if(job.minimum_character_age && (player.client.prefs.age < job.minimum_character_age))
			return 0
		if(jobban_isbanned(player, rank))
			return 0
		if(!job.player_old_enough(player.client))
			return 0
		if(job.is_restricted(player.client.prefs))
			return 0

		var/position_limit = job.total_positions
		if(!latejoin)
			position_limit = job.spawn_positions
		if((job.current_positions < position_limit) || position_limit == -1)
			Debug("Player: [player] is now Rank: [rank], JCP:[job.current_positions], JPL:[position_limit]")
			player.mind.assigned_role = rank
			player.mind.role_alt_title = GetPlayerAltTitle(player, rank)
			unassigned -= player
			job.current_positions++
			return 1
	Debug("AR has failed, Player: [player], Rank: [rank]")
	return 0

/datum/controller/subsystem/jobs/proc/FreeRole(var/rank)	//making additional slot on the fly
	var/datum/job/job = GetJob(rank)
	if(job && job.current_positions >= job.total_positions && job.total_positions != -1)
		job.total_positions++
		return 1
	return 0

/datum/controller/subsystem/jobs/proc/RemoveRole(var/rank)	//making additional slot on the fly
	var/datum/job/job = GetJob(rank)
	if(job && job.current_positions <= job.total_positions)
		job.total_positions = 0
		return 1
	return 0

/datum/controller/subsystem/jobs/proc/allow_one_more(var/rank)	//making additional slot on the fly regardless of whether or not the current slots are full.
	var/datum/job/job = GetJob(rank)
	if(job)
		job.total_positions++

/datum/controller/subsystem/jobs/proc/FindOccupationCandidates(datum/job/job, level, flag)
	Debug("Running FOC, Job: [job], Level: [level], Flag: [flag]")
	var/list/candidates = list()
	for(var/mob/new_player/player in unassigned)
		if(jobban_isbanned(player, job.title))
			Debug("FOC isbanned failed, Player: [player]")
			continue
		if(!job.player_old_enough(player.client))
			Debug("FOC player not old enough, Player: [player]")
			continue
		if(job.minimum_character_age && (player.client.prefs.age < job.minimum_character_age))
			Debug("FOC character not old enough, Player: [player]")
			continue
		if(flag && !(flag in player.client.prefs.be_special_role))
			Debug("FOC flag failed, Player: [player], Flag: [flag], ")
			continue
		if(player.client.prefs.CorrectLevel(job,level))
			Debug("FOC pass, Player: [player], Level:[level]")
			candidates += player
	return candidates

/datum/controller/subsystem/jobs/proc/GiveRandomJob(var/mob/new_player/player)
	Debug("GRJ Giving random job, Player: [player]")
	for(var/datum/job/job in shuffle(occupations))
		if(!job)
			continue

		if(job.minimum_character_age && (player.client.prefs.age < job.minimum_character_age))
			continue

		if(istype(job, GetJob("Assistant"))) // We don't want to give him assistant, that's boring!
			continue

		if(job.is_restricted(player.client.prefs))
			continue

		if(job.title in GLOB.command_positions) //If you want a command position, select it!
			continue

		if(jobban_isbanned(player, job.title))
			Debug("GRJ isbanned failed, Player: [player], Job: [job.title]")
			continue

		if(!job.player_old_enough(player.client))
			Debug("GRJ player not old enough, Player: [player]")
			continue

		if((job.current_positions < job.spawn_positions) || job.spawn_positions == -1)
			Debug("GRJ Random job given, Player: [player], Job: [job]")
			AssignRole(player, job.title)
			unassigned -= player
			break

/datum/controller/subsystem/jobs/proc/ResetOccupations()
	for(var/mob/new_player/player in GLOB.player_list)
		if((player) && (player.mind))
			player.mind.assigned_role = null
			player.mind.special_role = null
	SetupOccupations()
	unassigned = list()
	return


///This proc is called before the level loop of DivideOccupations() and will try to select a head, ignoring ALL non-head preferences for every level until it locates a head or runs out of levels to check
/datum/controller/subsystem/jobs/proc/FillHeadPosition()
	for(var/level = 1 to 3)
		for(var/command_position in GLOB.command_positions)
			var/datum/job/job = GetJob(command_position)
			if(!job)	continue
			var/list/candidates = FindOccupationCandidates(job, level)
			if(!candidates.len)	continue

			// Build a weighted list, weight by age.
			var/list/weightedCandidates = list()
			for(var/mob/V in candidates)
				// Log-out during round-start? What a bad boy, no head position for you!
				if(!V.client) continue
				var/age = V.client.prefs.age

				if(age < job.minimum_character_age) // Nope.
					continue
//TEMPORARY FIX swapping 'job.minimum_character_age' to '18' and 'job.ideal_character_age' to '30' because it's a mostly irrelevant mechanic and this is the easiest fix
				switch(age)
					if(18 to (18+10))
						weightedCandidates[V] = 3 // Still a bit young.
					if((18+5) to (30-5))
						weightedCandidates[V] = 6 // Better.
					if((30-10) to (30+10))
						weightedCandidates[V] = 10 // Great.
					if((30+10) to (30+20))
						weightedCandidates[V] = 6 // Still good.
					if((30+20) to INFINITY)
						weightedCandidates[V] = 3 // Geezer.
					else
						// If there's ABSOLUTELY NOBODY ELSE
						if(candidates.len == 1) weightedCandidates[V] = 1


			var/mob/new_player/candidate = pickweight(weightedCandidates)
			if(AssignRole(candidate, command_position))
				return 1
	return 0


///This proc is called at the start of the level loop of DivideOccupations() and will cause head jobs to be checked before any other jobs of the same level
/datum/controller/subsystem/jobs/proc/CheckHeadPositions(var/level)
	for(var/command_position in GLOB.command_positions)
		var/datum/job/job = GetJob(command_position)
		if(!job)	continue
		var/list/candidates = FindOccupationCandidates(job, level)
		if(!candidates.len)	continue
		var/mob/new_player/candidate = pick(candidates)
		AssignRole(candidate, command_position)
	return


/** Proc DivideOccupations
*  fills var "assigned_role" for all ready players.
*  This proc must not have any side effect besides of modifying "assigned_role".
**/
/datum/controller/subsystem/jobs/proc/DivideOccupations()
	//Setup new player list and get the jobs list
	Debug("Running DO")
	SetupOccupations()

	//Holder for Triumvirate is stored in the ticker, this just processes it
	if(ticker && ticker.triai)
		for(var/datum/job/A in occupations)
			if(A.title == "AI")
				A.spawn_positions = 3
				break

	//Get the players who are ready
	for(var/mob/new_player/player in GLOB.player_list)
		if(player.ready && player.mind && !player.mind.assigned_role)
			unassigned += player

	Debug("DO, Len: [unassigned.len]")
	if(unassigned.len == 0)	return 0

	//Shuffle players and jobs
	unassigned = shuffle(unassigned)

	HandleFeedbackGathering()

	//People who wants to be assistants, sure, go on.
	Debug("DO, Running Assistant Check 1")
/*z	var/datum/job/assist = new DEFAULT_JOB_TYPE ()
	var/list/assistant_candidates = FindOccupationCandidates(assist, 3)
	Debug("AC1, Candidates: [assistant_candidates.len]")
	for(var/mob/new_player/player in assistant_candidates)
		Debug("AC1 pass, Player: [player]")
		AssignRole(player, "Assistant")
		assistant_candidates -= player
	Debug("DO, AC1 end")*/

	//Select one head
	Debug("DO, Running Head Check")
	FillHeadPosition()
	Debug("DO, Head Check end")

	//Other jobs are now checked
	Debug("DO, Running Standard Check")


	// New job giving system by Donkie
	// This will cause lots of more loops, but since it's only done once it shouldn't really matter much at all.
	// Hopefully this will add more randomness and fairness to job giving.

	// Loop through all levels from high to low
	var/list/shuffledoccupations = shuffle(occupations)
	// var/list/disabled_jobs = ticker.mode.disabled_jobs  // So we can use .Find down below without a colon.
	for(var/level = 1 to 3)
		//Check the head jobs first each level
		CheckHeadPositions(level)

		// Loop through all unassigned players
		for(var/mob/new_player/player in unassigned)

			// Loop through all jobs
			for(var/datum/job/job in shuffledoccupations) // SHUFFLE ME BABY
				if(!job || ticker.mode.disabled_jobs.Find(job.title) )
					continue

				if(jobban_isbanned(player, job.title))
					Debug("DO isbanned failed, Player: [player], Job:[job.title]")
					continue

				if(!job.player_old_enough(player.client))
					Debug("DO player not old enough, Player: [player], Job:[job.title]")
					continue

				// If the player wants that job on this level, then try give it to him.
				if(player.client.prefs.CorrectLevel(job,level))

					// If the job isn't filled
					if((job.current_positions < job.spawn_positions) || job.spawn_positions == -1)
						Debug("DO pass, Player: [player], Level:[level], Job:[job.title]")
						AssignRole(player, job.title)
						unassigned -= player
						break

	// Hand out random jobs to the people who didn't get any in the last check
	// Also makes sure that they got their preference correct
	for(var/mob/new_player/player in unassigned)
		if(player.client.prefs.alternate_option == GET_RANDOM_JOB)
			GiveRandomJob(player)

	Debug("DO, Standard Check end")

	Debug("DO, Running AC2")

	// For those who wanted to be assistant if their preferences were filled, here you go.
	for(var/mob/new_player/player in unassigned)
		if(player.client.prefs.alternate_option == BE_ASSISTANT)
			Debug("AC2 Assistant located, Player: [player]")
			if(GLOB.using_map.flags & MAP_HAS_BRANCH)
				var/datum/mil_branch/branch = mil_branches.get_branch(player.get_branch_pref())
				AssignRole(player, branch.assistant_job)
			else
				AssignRole(player, "Assistant")

	//For ones returning to lobby
	for(var/mob/new_player/player in unassigned)
		if(player.client.prefs.alternate_option == RETURN_TO_LOBBY)
			player.ready = 0
			player.new_player_panel()
			unassigned -= player
	return 1


/datum/controller/subsystem/jobs/proc/EquipRank(var/mob/living/carbon/human/H, var/rank, var/joined_late = 0)
	if(!H)	return null

	var/datum/job/job = GetJob(rank)
	if(job)

		//Equip job items.
		job.setup_account(H)
		job.equip(H, H.mind ? H.mind.role_alt_title : "", H.char_branch, H.char_rank)
		job.apply_fingerprints(H)
		H.staminaexhaust = 250 + endToStaminaModifier(H.my_stats[STAT(end)].level)

	else
		to_chat(H, "Your job is [rank] and the game just can't handle it! Please report this bug to an administrator.")

	H.job = rank

	if(!joined_late || job.latejoin_at_spawnpoints)
		var/obj/S = get_roundstart_spawnpoint(rank)

		if(istype(S, /obj/effect/landmark/start) && istype(S.loc, /turf))
			H.forceMove(S.loc)
		else
			var/datum/spawnpoint/spawnpoint = get_spawnpoint_for(H.client, rank)
			H.forceMove(pick(spawnpoint.turfs))

		// Moving wheelchair if they have one
		if(H.buckled && istype(H.buckled, /obj/structure/bed/chair/wheelchair))
			H.buckled.forceMove(H.loc)
			H.buckled.set_dir(H.dir)

	// If they're head, give them the account info for their department
	if(H.mind && job.head_position)
		var/remembered_info = ""
		var/datum/money_account/department_account = department_accounts[job.department]

		if(department_account)
			remembered_info += "<b>Your department's account number is:</b> #[department_account.account_number]<br>"
			remembered_info += "<b>Your department's account pin is:</b> [department_account.remote_access_pin]<br>"
			remembered_info += "<b>Your department's account funds are:</b> T[department_account.money]<br>"

		H.mind.store_memory(remembered_info)

	var/alt_title = null
	if(H.mind)
		H.mind.assigned_role = rank
		alt_title = H.mind.role_alt_title

		switch(rank)
			if("Cyborg")
				return H.Robotize()
			if("AI")
				return H

	if(istype(H)) //give humans wheelchairs, if they need them.
		var/obj/item/organ/external/l_foot = H.get_organ(BP_L_FOOT)
		var/obj/item/organ/external/r_foot = H.get_organ(BP_R_FOOT)
		if(!l_foot || !r_foot)
			var/obj/structure/bed/chair/wheelchair/W = new /obj/structure/bed/chair/wheelchair(H.loc)
			H.buckled = W
			H.update_canmove()
			W.set_dir(H.dir)
			W.buckled_mob = H
			W.add_fingerprint(H)

	to_chat(H, "<B>You are [job.total_positions == 1 ? "the" : "a"] [alt_title ? alt_title : rank].</B>")

	if(job.role_desc)
		to_chat(H, "<b>Role Description:</b> <i>[job.role_desc]</i>")

	if(job.supervisors)
		to_chat(H, "<b>As the [alt_title ? alt_title : rank] you answer directly to [job.supervisors]. Special circumstances may change this.</b>")


	if(job.req_admin_notify)
		to_chat(H, "<b>You are playing a job that is important for Game Progression. If you have to disconnect, please notify the admins via adminhelp.</b>")


	if(job.has_email)
		// EMAIL GENERATION
		var/domain
		if(H.char_branch && H.char_branch.email_domain)
			domain = H.char_branch.email_domain
		else
			domain = "freemail.nt"
		var/sanitized_name = sanitize(replacetext(replacetext(lowertext(H.real_name), " ", "."), "'", ""))
		var/complete_login = "[sanitized_name]@[domain]"

		// It is VERY unlikely that we'll have two players, in the same round, with the same name and branch, but still, this is here.
		// If such conflict is encountered, a random number will be appended to the email address. If this fails too, no email account will be created.
		if(ntnet_global.does_email_exist(complete_login))
			complete_login = "[sanitized_name][random_id(/datum/computer_file/data/email_account/, 100, 999)]@[domain]"

		// If even fallback login generation failed, just don't give them an email. The chance of this happening is astronomically low.
		if(ntnet_global.does_email_exist(complete_login))
			to_chat(H, "You were not assigned an email address.")
			H.mind.store_memory("You were not assigned an email address.")
		else
			var/datum/computer_file/data/email_account/EA = new/datum/computer_file/data/email_account()
			EA.password = GenerateKey()
			EA.login = 	complete_login
			to_chat(H, "Your email account address is <b>[EA.login]</b> and the password is <b>[EA.password]</b>. This information has also been placed into your notes.")
			H.mind.store_memory("Your email account address is [EA.login] and the password is [EA.password].")
		// END EMAIL GENERATION

	//Gives glasses to the vision impaired
	if(H.disabilities & NEARSIGHTED)
		var/equipped = H.equip_to_slot_or_del(new /obj/item/clothing/glasses/regular(H), slot_glasses)
		if(equipped)
			var/obj/item/clothing/glasses/G = H.glasses
			G.prescription = 7
	if(H.client.prefs.cult != "None" && SSgods.cultist_count <= MAX_CULTISTS)
		if(!job.cultist_chance)
			to_chat(H, "<span class='warning'>Your job was unable to play as a cultist.</span>")
		if(prob(job.cultist_chance) || job.cultist_chance == 100)
			var/datum/heretic_deity/deity = GOD(H.client.prefs.cult)
				deity.add_cultist(H)
		else if(job.cultist_chance)
			to_chat(H, "<span class='warning'>Cultist roll failed. Chance [job.cultist_chance]%.</span>")
	else if(H.client.prefs.cult != "None" && SSgods.cultist_count >= MAX_CULTISTS)
		to_chat(H, "<span class='warning'>Cultists have reached capacity.</span>")

	BITSET(H.hud_updateflag, ID_HUD)
	BITSET(H.hud_updateflag, IMPLOYAL_HUD)
	BITSET(H.hud_updateflag, SPECIALROLE_HUD)
	return H

/datum/controller/subsystem/jobs/proc/LoadJobs(jobsfile) //ran during round setup, reads info from jobs.txt -- Urist
	if(!config.load_jobs_from_txt)
		return 0

	var/list/jobEntries = file2list(jobsfile)

	for(var/job in jobEntries)
		if(!job)
			continue

		job = trim(job)
		if (!length(job))
			continue

		var/pos = findtext(job, "=")
		var/name = null
		var/value = null

		if(pos)
			name = copytext(job, 1, pos)
			value = copytext(job, pos + 1)
		else
			continue

		if(name && value)
			var/datum/job/J = GetJob(name)
			if(!J)	continue
			J.total_positions = text2num(value)
			J.spawn_positions = text2num(value)
			if(name == "AI" || name == "Cyborg")//I dont like this here but it will do for now
				J.total_positions = 0

	return 1


/datum/controller/subsystem/jobs/proc/HandleFeedbackGathering()
	for(var/datum/job/job in occupations)
		var/tmp_str = "|[job.title]|"

		var/level1 = 0 //high
		var/level2 = 0 //medium
		var/level3 = 0 //low
		var/level4 = 0 //never
		var/level5 = 0 //banned
		var/level6 = 0 //account too young
		for(var/mob/new_player/player in GLOB.player_list)
			if(!(player.ready && player.mind && !player.mind.assigned_role))
				continue //This player is not ready
			if(jobban_isbanned(player, job.title))
				level5++
				continue
			if(!job.player_old_enough(player.client))
				level6++
				continue
			if(player.client.prefs.CorrectLevel(job, 1))
				level1++
			else if(player.client.prefs.CorrectLevel(job, 2))
				level2++
			else if(player.client.prefs.CorrectLevel(job, 3))
				level3++
			else level4++ //not selected

		tmp_str += "HIGH=[level1]|MEDIUM=[level2]|LOW=[level3]|NEVER=[level4]|BANNED=[level5]|YOUNG=[level6]|-"
		feedback_add_details("job_preferences",tmp_str)


/**
 *  Return appropriate /datum/spawnpoint for given client and rank
 *
 *  Spawnpoint will be the one set in preferences for the client, unless the
 *  preference is not set, or the preference is not appropriate for the rank, in
 *  which case a fallback will be selected.
 */
/datum/controller/subsystem/jobs/proc/get_spawnpoint_for(var/client/C, var/rank)

	if(!C)
		CRASH("Null client passed to get_spawnpoint_for() proc!")

	var/mob/H = C.mob
	var/spawnpoint = C.prefs.spawnpoint
	var/datum/spawnpoint/spawnpos

	if(spawnpoint == DEFAULT_SPAWNPOINT_ID)
		spawnpoint = GLOB.using_map.default_spawn

	if(spawnpoint)
		if(!(spawnpoint in GLOB.using_map.allowed_spawns))
			if(H)
				to_chat(H, "<span class='warning'>Your chosen spawnpoint ([C.prefs.spawnpoint]) is unavailable for the current map. Spawning you at one of the enabled spawn points instead. To resolve this error head to your character's setup and choose a different spawn point.</span>")
			spawnpos = null
		else
			spawnpos = spawntypes()[spawnpoint]

	if(spawnpos && !spawnpos.check_job_spawning(rank))
		if(H)
			to_chat(H, "<span class='warning'>Your chosen spawnpoint ([spawnpos.display_name]) is unavailable for your chosen job ([rank]). Spawning you at another spawn point instead.</span>")
		spawnpos = null

	if(!spawnpos)
		// Step through all spawnpoints and pick first appropriate for job
		for(var/spawntype in GLOB.using_map.allowed_spawns)
			var/datum/spawnpoint/candidate = spawntypes()[spawntype]
			if(candidate.check_job_spawning(rank))
				spawnpos = candidate
				break

	if(!spawnpos)
		// Pick at random from all the (wrong) spawnpoints, just so we have one
		warning("Could not find an appropriate spawnpoint for job [rank].")
		spawnpos = spawntypes()[pick(GLOB.using_map.allowed_spawns)]

	return spawnpos

/datum/controller/subsystem/jobs/proc/GetJobByType(var/job_type)
	return occupations_by_type[job_type]

/datum/controller/subsystem/jobs/proc/GetJobByTitle(var/job_title)
	return occupations_by_title[job_title]

/datum/controller/subsystem/jobs/proc/get_roundstart_spawnpoint(var/rank)
	var/list/loc_list = list()
	for(var/obj/effect/landmark/start/sloc in landmarks_list)
		if(sloc.name != rank)	continue
		if(locate(/mob/living) in sloc.loc)	continue
		loc_list += sloc
	if(loc_list.len)
		return pick(loc_list)
	else
		return locate("start*[rank]") // use old stype

#undef GET_RANDOM_JOB
#undef BE_ASSISTANT
#undef RETURN_TO_LOBBY
