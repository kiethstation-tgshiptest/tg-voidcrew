/*
 * Cloning revival method.
 * The pod handles the actual cloning while the computer manages the clone profiles

 * Potential replacement for genetics revives or something I dunno (?)
 */

///Clones in clonepods start with 150 cloneloss damage and 150 brainloss damage, thats just logical
#define CLONE_INITIAL_DAMAGE 150
#define MINIMUM_HEAL_LEVEL 40

#define SPEAK(message) radio.talk_into(src, message, radio_channel)

/obj/machinery/clonepod
	name = "cloning pod"
	desc = "An electronically-lockable pod for growing organic tissue."
	density = TRUE
	icon = 'voidcrew/modules/cloning/icons/cloning.dmi'
	icon_state = "pod_0"
	req_access = list(ACCESS_MEDICAL) //FOR PREMATURE UNLOCKING.
	verb_say = "states"
	circuit = /obj/item/circuitboard/machine/clonepod

	///The clone is released once its health reaches this level.
	var/heal_level
	///So we remember the connected clone machine.
	var/obj/machinery/computer/cloning/connected
	///Need to clean out it if it's full of exploded clone.
	var/mess = FALSE
	///One clone attempt at a time thanks
	var/attempting = FALSE
	var/speed_coeff
	var/efficiency

	///Beaker full of what SHOULD be synthflesh
	var/obj/item/reagent_containers/cup/beaker
	///Amount of synthflesh needed per cloning cycle, is divided by efficiency
	var/fleshamnt = 1

	var/datum/mind/clonemind
	var/grab_ghost_when = CLONER_MATURE_CLONE

	var/internal_radio = TRUE
	var/obj/item/radio/radio
	var/radio_key = /obj/item/encryptionkey/headset_med
	var/radio_channel = RADIO_CHANNEL_MEDICAL

	var/obj/effect/countdown/clonepod/countdown

	var/list/unattached_flesh
	var/flesh_number = 0
	var/datum/bank_account/current_insurance
	fair_market_price = 5 // He nodded, because he knew I was right. Then he swiped his credit card to pay me for arresting him.
	payment_department = ACCOUNT_MED


/obj/machinery/clonepod/Initialize()
	. = ..()

	countdown = new(src)

	if(internal_radio)
		radio = new(src)
		radio.keyslot = new radio_key
		radio.subspace_transmission = TRUE
		radio.canhear_range = 0
		radio.recalculateChannels()

/obj/machinery/clonepod/Destroy()
	var/mob/living/mob_occupant = occupant
	go_out()
	if(mob_occupant)
		log_combat("[key_name(mob_occupant)] ejected from [src] at [AREACOORD(src)] due to Destroy().")
	QDEL_NULL(radio)
	QDEL_NULL(countdown)
	if(connected)
		connected.DetachCloner(src)
	QDEL_LIST(unattached_flesh)
	. = ..()

/obj/machinery/clonepod/RefreshParts()
	. = ..()
	speed_coeff = 0
	efficiency = 0
	fleshamnt = 1
	for(var/obj/item/stock_parts/scanning_module/S in component_parts)
		efficiency += S.rating
		fleshamnt = 1/max(efficiency-1, 1)
	for(var/obj/item/stock_parts/manipulator/P in component_parts)
		speed_coeff += P.rating
	heal_level = (efficiency * 15) + 10
	if(heal_level < MINIMUM_HEAL_LEVEL)
		heal_level = MINIMUM_HEAL_LEVEL
	if(heal_level > 100)
		heal_level = 100

/obj/machinery/clonepod/proc/replace_beaker(mob/living/user, obj/item/reagent_containers/new_beaker)
	if(beaker)
		beaker.forceMove(drop_location())
		if(user && Adjacent(user) && !issiliconoradminghost(user))
			user.put_in_hands(beaker)
	if(new_beaker)
		beaker = new_beaker
	else
		beaker = null
	update_icon()
	return TRUE

/obj/machinery/clonepod/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Cloner", name)
		ui.open()

/obj/machinery/clonepod/ui_data()
	var/list/data = list()
	data["isBeakerLoaded"] = beaker ? TRUE : FALSE
	var/beakerContents = list()
	if(beaker && beaker.reagents && beaker.reagents.reagent_list.len)
		for(var/datum/reagent/R in beaker.reagents.reagent_list)
			beakerContents += list(list("name" = R.name, "volume" = R.volume))
	data["beakerContents"] = beakerContents
	data["progress"] = round(get_completion())
	return data

/obj/machinery/clonepod/ui_act(action, params)
	. = ..()
	if(.)
		return
	switch(action)
		if("ejectbeaker")
			replace_beaker(usr)
			. = TRUE

/obj/machinery/chem_dispenser/AltClick(mob/living/user)
	..()
	if(istype(user) && user.canUseTopic(src, BE_CLOSE, FALSE, NO_TK))
		replace_beaker(user)

/obj/machinery/clonepod/attack_ai(mob/user)
	return attack_hand(user)

/obj/machinery/clonepod/examine(mob/user)
	. = ..()
	. += "<span class='notice'>The <i>linking</i> device can be <i>scanned<i> with a multitool. It can be emptied by Alt-Clicking it.</span>"
	if(in_range(user, src) || isobserver(user))
		. += "<span class='notice'>The status display reads: Cloning speed at <b>[speed_coeff*50]%</b>.<br>Predicted amount of cellular damage: <b>[100-heal_level]%</b><br>"
		. += "Synthflesh consumption at <b>[round(fleshamnt*90, 1)]cm<sup>3</sup></b> per clone.</span><br>"

		if(efficiency > 5)
			. += "<span class='notice'>Pod has been upgraded to support autoprocessing and apply beneficial mutations.</span>"

//The return of data disks?? Just for transferring between genetics machine/cloning machine.
//TO-DO: Make the genetics machine accept them.
/obj/item/disk/data
	var/list/fields = list()

//Clonepod

/obj/machinery/clonepod/examine(mob/user)
	. = ..()
	var/mob/living/mob_occupant = occupant
	if(mess)
		. += "It's filled with blood and viscera. You swear you can see it moving..."
	if(is_operational && istype(mob_occupant))
		if(mob_occupant.stat != DEAD)
			. += "Current clone cycle is [round(get_completion())]% complete."

/obj/machinery/clonepod/return_air()
	// We want to simulate the clone not being in contact with
	// the atmosphere, so we'll put them in a constant pressure
	// nitrogen. They don't need to breathe while cloning anyway.
	var/static/datum/gas_mixture/immutable/cloner/GM //global so that there's only one instance made for all cloning pods
	if(!GM)
		GM = new
	return GM

/obj/machinery/clonepod/proc/get_completion()
	. = FALSE
	var/mob/living/mob_occupant = occupant
	if(mob_occupant)
		. = (100 * ((mob_occupant.health + 100) / (heal_level + 100)))

/obj/machinery/clonepod/attack_ai(mob/user)
	return examine(user)

//Start growing a human clone in the pod!
/obj/machinery/clonepod/proc/growclone(clonename, ui, mutation_index, mindref, last_death, blood_type, datum/species/mrace, list/features, factions, list/quirks, datum/bank_account/insurance, list/traumas, empty)
	if(!beaker)
		connected_message("Cannot start cloning: No beaker found.")
		return NONE
	if(!beaker.reagents.has_reagent(/datum/reagent/medicine/c2/synthflesh, fleshamnt))
		connected_message("Cannot start cloning: Not enough synthflesh.")
		return NONE
	if(panel_open)
		return NONE
	if(mess || attempting)
		return NONE

	if(!empty) //Doesn't matter if we're just making a copy
		clonemind = locate(mindref) in SSticker.minds
		if(!istype(clonemind))	//not a mind
			return NONE
		if(clonemind.last_death != last_death) //The soul has advanced, the record has not.
			return NONE
		if(!QDELETED(clonemind.current))
			if(clonemind.current.stat != DEAD)	//mind is associated with a non-dead body
				return NONE
			if(clonemind.current.suiciding) // Mind is associated with a body that is suiciding.
				return NONE
		if(!clonemind.active)
			// get_ghost() will fail if they're unable to reenter their body
			var/mob/dead/observer/G = clonemind.get_ghost()
			if(!G)
				return NONE
			if(G.suiciding) // The ghost came from a body that is suiciding.
				return NONE
		current_insurance = insurance
	attempting = TRUE //One at a time!!
	countdown.start()

	var/mob/living/carbon/human/cloned_human = new /mob/living/carbon/human(src)

	if(!clonename)	//to prevent null names
		clonename = "clone ([rand(1,999)])"
	cloned_human.real_name = clonename

	cloned_human.hardset_dna(ui, mutation_index, null, cloned_human.real_name, blood_type, mrace, features)

	cloned_human.silent = 20 //Prevents an extreme edge case where clones could speak if they said something at exactly the right moment.
	occupant = cloned_human

	icon_state = "pod_1"
	//Get the clone body ready
	maim_clone(cloned_human)
	ADD_TRAIT(cloned_human, TRAIT_STABLEHEART, CLONING_POD_TRAIT)
	ADD_TRAIT(cloned_human, TRAIT_STABLELIVER, CLONING_POD_TRAIT)
	ADD_TRAIT(cloned_human, TRAIT_EMOTEMUTE, CLONING_POD_TRAIT)
	ADD_TRAIT(cloned_human, TRAIT_MUTE, CLONING_POD_TRAIT)
	ADD_TRAIT(cloned_human, TRAIT_NOBREATH, CLONING_POD_TRAIT)
	ADD_TRAIT(cloned_human, TRAIT_NOCRITDAMAGE, CLONING_POD_TRAIT)
	cloned_human.Unconscious(80)

	if(!empty)
		clonemind.transfer_to(cloned_human)

		if(grab_ghost_when == CLONER_FRESH_CLONE)
			cloned_human.grab_ghost()
			to_chat(cloned_human, "<span class='notice'><b>Consciousness slowly creeps over you as your body regenerates.</b><br><i>So this is what cloning feels like?</i></span>")

		if(grab_ghost_when == CLONER_MATURE_CLONE)
			cloned_human.ghostize(TRUE)	//Only does anything if they were still in their old body and not already a ghost
			to_chat(cloned_human.get_ghost(TRUE), "<span class='notice'>Your body is beginning to regenerate in a cloning pod. You will become conscious when it is complete.</span>")

	if(cloned_human)
		cloned_human.faction |= factions

		for(var/V in quirks)
			var/datum/quirk/Q = new V(cloned_human)
			Q.on_clone(quirks[V])

		for(var/t in traumas)
			var/datum/brain_trauma/BT = t
			var/datum/brain_trauma/cloned_trauma = BT.on_clone()
			if(cloned_trauma)
				cloned_human.gain_trauma(cloned_trauma, BT.resilience)

		cloned_human.set_cloned_appearance()

		cloned_human.set_suicide(FALSE)
	attempting = FALSE
	return CLONING_SUCCESS

//Grow clones to maturity then kick them out.  FREELOADERS
/obj/machinery/clonepod/process()
	var/mob/living/mob_occupant = occupant

	if(!is_operational) //Autoeject if power is lost
		if(mob_occupant)
			go_out()
			log_combat("[key_name(mob_occupant)] ejected from [src] at [AREACOORD(src)] due to power loss.")

			connected_message("Clone Ejected: Loss of power.")
		return

	if(mob_occupant && (mob_occupant.loc == src))
		if(!beaker.reagents.has_reagent(/datum/reagent/medicine/c2/synthflesh, fleshamnt))
			go_out()
			log_combat("[key_name(mob_occupant)] ejected from [src] at [AREACOORD(src)] due to insufficient material.")
			connected_message("Clone Ejected: Not enough material.")
			if(internal_radio)
				SPEAK("The cloning of [mob_occupant.real_name] has been ended prematurely due to insufficient material.")
		if(SSeconomy.full_ancap)
			if(!current_insurance)
				go_out()
				log_combat("[key_name(mob_occupant)] ejected from [src] at [AREACOORD(src)] due to invalid bank account.")
				connected_message("Clone Ejected: No bank account.")
				if(internal_radio)
					SPEAK("The cloning of [mob_occupant.real_name] has been terminated due to no bank account to draw payment from.")
			else if(!current_insurance.adjust_money(-fair_market_price))
				go_out()
				log_combat("[key_name(mob_occupant)] ejected from [src] at [AREACOORD(src)] due to insufficient funds.")
				connected_message("Clone Ejected: Out of Money.")
				if(internal_radio)
					SPEAK("The cloning of [mob_occupant.real_name] has been ended prematurely due to being unable to pay.")
			else
				var/datum/bank_account/D = SSeconomy.get_dep_account(payment_department)
				if(D)
					D.adjust_money(fair_market_price)
		if(mob_occupant && (mob_occupant.stat == DEAD) || (mob_occupant.suiciding))  //Autoeject corpses and suiciding dudes.
			connected_message("Clone Rejected: Deceased.")
			if(internal_radio)
				SPEAK("The cloning of [mob_occupant.real_name] has been \
					aborted due to unrecoverable tissue failure.")
			go_out()
			log_combat("[key_name(mob_occupant)] ejected from [src] at [AREACOORD(src)] after suiciding.")

		else if(mob_occupant && mob_occupant.cloneloss > (100 - heal_level))
			mob_occupant.Unconscious(80)
			var/dmg_mult = CONFIG_GET(number/damage_multiplier)
			//Slowly get that clone healed and finished.
			mob_occupant.adjustCloneLoss(-((speed_coeff / 2) * dmg_mult))
			if(beaker.reagents.has_reagent(/datum/reagent/medicine/c2/synthflesh, fleshamnt))
				beaker.reagents.remove_reagent(/datum/reagent/medicine/c2/synthflesh, fleshamnt)
			else if(beaker.reagents.has_reagent(/datum/reagent/blood, fleshamnt*3))
				beaker.reagents.remove_reagent(/datum/reagent/blood, fleshamnt*3)
			var/progress = CLONE_INITIAL_DAMAGE - mob_occupant.getCloneLoss()
			// To avoid the default cloner making incomplete clones
			progress += (100 - MINIMUM_HEAL_LEVEL)
			var/milestone = CLONE_INITIAL_DAMAGE / flesh_number
			var/installed = flesh_number - unattached_flesh.len

			if((progress / milestone) >= installed)
				// attach some flesh
				var/obj/item/I = pick_n_take(unattached_flesh)
				if(isorgan(I))
					var/obj/item/organ/O = I
					O.organ_flags &= ~ORGAN_FROZEN
					O.Insert(mob_occupant)
				else if(isbodypart(I))
					var/obj/item/bodypart/BP = I
					BP.attach_limb(mob_occupant)

			use_power(7500) //This might need tweaking.

		else if(mob_occupant && (mob_occupant.cloneloss <= (100 - heal_level)))
			connected_message("Cloning Process Complete.")
			if(internal_radio)
				SPEAK("The cloning cycle of [mob_occupant.real_name] is complete.")

			// If the cloner is upgraded to debugging high levels, sometimes
			// organs and limbs can be missing.
			for(var/i in unattached_flesh)
				if(isorgan(i))
					var/obj/item/organ/O = i
					O.organ_flags &= ~ORGAN_FROZEN
					O.Insert(mob_occupant)
				else if(isbodypart(i))
					var/obj/item/bodypart/BP = i
					BP.attach_limb(mob_occupant)

			go_out()
			log_combat("[key_name(mob_occupant)] completed cloning cycle in [src] at [AREACOORD(src)].")

	else if (!mob_occupant || mob_occupant.loc != src)
		occupant = null
		if (!mess && !panel_open)
			icon_state = "pod_0"
		use_power(200)

//Let's unlock this early I guess.  Might be too early, needs tweaking. Mark says: Jesus, even I'm not that indecisive.
/obj/machinery/clonepod/attackby(obj/item/attacking_item, mob/user, params)
	if(istype(attacking_item, /obj/item/reagent_containers) && !(attacking_item.item_flags & ABSTRACT) && attacking_item.is_open_container())
		var/obj/item/reagent_containers/B = attacking_item
		. = TRUE //no afterattack
		if(!user.transferItemToLoc(B, src))
			return
		var/reagentlist = pretty_string_from_reagent_list(attacking_item.reagents.reagent_list)
		replace_beaker(user, B)
		to_chat(user, "<span class='notice'>You add [B] to [src].</span>")
		log_game("[key_name(user)] added an [attacking_item] to the [src] at [src.loc] containing [reagentlist]")
	if(!(occupant || mess))
		if(default_deconstruction_screwdriver(user, "[icon_state]_maintenance", "[initial(icon_state)]",attacking_item))
			return

	if(default_deconstruction_crowbar(attacking_item))
		return

	if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
		if(!multitool_check_buffer(user, attacking_item))
			return
		var/obj/item/multitool/P = attacking_item

		if(istype(P.buffer, /obj/machinery/computer/cloning))
			if(get_area(P.buffer) != get_area(src))
				to_chat(user, "<font color = #666633>-% Cannot link machines across power zones. Buffer cleared %-</font color>")
				P.buffer = null
				return
			to_chat(user, "<font color = #666633>-% Successfully linked [P.buffer] with [src] %-</font color>")
			var/obj/machinery/computer/cloning/comp = P.buffer
			if(connected)
				connected.DetachCloner(src)
			comp.AttachCloner(src)
		else
			P.buffer = src
			to_chat(user, "<font color = #666633>-% Successfully stored [REF(P.buffer)] [P.buffer.name] in buffer %-</font color>")
		return

	var/mob/living/mob_occupant = occupant
	if(attacking_item.GetID())
		if(!check_access(attacking_item))
			to_chat(user, "<span class='danger'>Access Denied.</span>")
			return
		if(!(mob_occupant || mess))
			to_chat(user, "<span class='danger'>Error: Pod has no occupant.</span>")
			return
		else
			add_fingerprint(user)
			connected_message("Emergency Ejection")
			SPEAK("An emergency ejection of [clonemind.name] has occurred. Survival not guaranteed.")
			to_chat(user, "<span class='notice'>You force an emergency ejection. </span>")
			go_out()
			log_combat("[key_name(user)] manually ejected [key_name(mob_occupant)] from [src] at [AREACOORD(src)].")
			log_combat(user, mob_occupant, "ejected", attacking_item, "from [src]")
	else
		return ..()

/obj/machinery/clonepod/emag_act(mob/user)
	if(!occupant)
		return
	to_chat(user, "<span class='warning'>You corrupt the genetic compiler.</span>")
	malfunction()
	add_fingerprint(user)
	log_combat("[key_name(user)] emagged [src] at [AREACOORD(src)], causing it to malfunction.")
	if(user)
		log_combat(user, src, "emagged", null, occupant ? "[occupant] inside, killing them via malfunction." : null)

//Put messages in the connected computer's temp var for display.
/obj/machinery/clonepod/proc/connected_message(message)
	if ((isnull(connected)) || (!istype(connected, /obj/machinery/computer/cloning)))
		return FALSE
	if (!message)
		return FALSE

	connected.temp = message
	connected.updateUsrDialog()
	return TRUE

/obj/machinery/clonepod/proc/go_out()
	countdown.stop()
	var/mob/living/mob_occupant = occupant
	var/turf/T = get_turf(src)

	if(mess) //Clean that mess and dump those gibs!
		for(var/obj/fl in unattached_flesh)
			fl.forceMove(T)
			if(istype(fl, /obj/item/organ))
				var/obj/item/organ/O = fl
				O.organ_flags &= ~ORGAN_FROZEN
		unattached_flesh.Cut()
		mess = FALSE
		new /obj/effect/gibspawner/generic(get_turf(src), mob_occupant)
		audible_message("<span class='hear'>You hear a splat.</span>")
		icon_state = "pod_0"
		return

	if(!mob_occupant)
		return
	current_insurance = null
	REMOVE_TRAIT(mob_occupant, TRAIT_STABLEHEART, CLONING_POD_TRAIT)
	REMOVE_TRAIT(mob_occupant, TRAIT_STABLELIVER, CLONING_POD_TRAIT)
	REMOVE_TRAIT(mob_occupant, TRAIT_EMOTEMUTE, CLONING_POD_TRAIT)
	REMOVE_TRAIT(mob_occupant, TRAIT_MUTE, CLONING_POD_TRAIT)
	REMOVE_TRAIT(mob_occupant, TRAIT_NOCRITDAMAGE, CLONING_POD_TRAIT)
	REMOVE_TRAIT(mob_occupant, TRAIT_NOBREATH, CLONING_POD_TRAIT)

	if(grab_ghost_when == CLONER_MATURE_CLONE)
		mob_occupant.grab_ghost()
		to_chat(occupant, "<span class='notice'><b>There is a bright flash!</b><br><i>You feel like a new being.</i></span>")
		mob_occupant.flash_act()

	occupant.forceMove(T)
	icon_state = "pod_0"
	mob_occupant.domutcheck(1) //Waiting until they're out before possible monkeyizing. The 1 argument forces powers to manifest.
	for(var/fl in unattached_flesh)
		qdel(fl)
	unattached_flesh.Cut()

	occupant = null
	clonemind = null

/obj/machinery/clonepod/proc/malfunction()
	var/mob/living/mob_occupant = occupant
	if(mob_occupant)
		connected_message("Critical Error!")
		SPEAK("Critical error! Please contact a Thinktronic Systems \
			technician, as your warranty may be affected.")
		mess = TRUE
		maim_clone(mob_occupant)	//Remove every bit that's grown back so far to drop later, also destroys bits that haven't grown yet
		icon_state = "pod_g"
		if(clonemind && mob_occupant.mind != clonemind)
			clonemind.transfer_to(mob_occupant)
		mob_occupant.grab_ghost() // We really just want to make you suffer.
		flash_color(mob_occupant, flash_color="#960000", flash_time=100)
		to_chat(mob_occupant, "<span class='warning'><b>Agony blazes across your consciousness as your body is torn apart.</b><br><i>Is this what dying is like? Yes it is.</i></span>")
		playsound(src, 'sound/machines/warning-buzzer.ogg', 50)
		SEND_SOUND(mob_occupant, sound('sound/hallucinations/veryfar_noise.ogg',0,1,50))
		log_combat("[key_name(mob_occupant)] destroyed within [src] at [AREACOORD(src)] due to malfunction.")
		QDEL_IN(mob_occupant, 40)

/obj/machinery/clonepod/relaymove(mob/user)
	container_resist_act(user)

/obj/machinery/clonepod/container_resist_act(mob/living/user)
	if(user.stat == CONSCIOUS)
		go_out()

/obj/machinery/clonepod/emp_act(severity)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	var/mob/living/mob_occupant = occupant
	if(mob_occupant && prob(100/(severity*efficiency)))
		connected_message(Gibberish("EMP-caused Accidental Ejection"))
		SPEAK(Gibberish("Exposure to electromagnetic fields has caused the ejection of [mob_occupant.real_name] prematurely."))
		go_out()
		log_combat("[key_name(mob_occupant)] ejected from [src] at [AREACOORD(src)] due to EMP pulse.")

/obj/machinery/clonepod/ex_act(severity, target)
	. = ..()
	if(QDELETED(src) || !occupant)
		return
	var/mob/living/mob_occupant = occupant
	go_out()
	log_combat("[key_name(mob_occupant)] ejected from [src] at [AREACOORD(src)] due to explosion.")

/obj/machinery/clonepod/handle_atom_del(atom/A)
	if(A == occupant)
		occupant = null
		countdown.stop()

/obj/machinery/clonepod/proc/horrifyingsound()
	for(var/i in 1 to 5)
		playsound(src,pick('sound/hallucinations/growl1.ogg','sound/hallucinations/growl2.ogg','sound/hallucinations/growl3.ogg'), 100, (rand(95,105) * 0.01))
		sleep(1)
	sleep(10)
	playsound(src,'sound/hallucinations/wail.ogg', 100, TRUE)

/obj/machinery/clonepod/deconstruct(disassembled = TRUE)
	if(beaker)
		beaker.forceMove(drop_location())
		beaker = null
	if(occupant)
		var/mob/living/mob_occupant = occupant
		go_out()
		log_combat("[key_name(mob_occupant)] ejected from [src] at [AREACOORD(src)] due to deconstruction.")
	..()

/obj/machinery/clonepod/proc/maim_clone(mob/living/carbon/human/cloned_human)
	if(!unattached_flesh)
		unattached_flesh = list()
	else
		for(var/fl in unattached_flesh)
			qdel(fl)
		unattached_flesh.Cut()

	//Yeah, clones start with very low health, not with random, because why would they start with random health
	// In addition to being cellularly damaged, they also have no limbs or internal organs.
	// Applying brainloss is done when the clone leaves the pod, so application of traumas can happen
	// based on the level of damage sustained.
	cloned_human.setCloneLoss(CLONE_INITIAL_DAMAGE)

	if(!HAS_TRAIT(cloned_human, TRAIT_NODISMEMBER))
		var/static/list/zones = list(
			BODY_ZONE_R_ARM,
			BODY_ZONE_L_ARM,
			BODY_ZONE_R_LEG,
			BODY_ZONE_L_LEG,
		)
		for(var/zone in zones)
			var/obj/item/bodypart/all_bodyparts = cloned_human.get_bodypart(zone)
			if(all_bodyparts)
				all_bodyparts.drop_limb()
				all_bodyparts.forceMove(src)
				unattached_flesh += all_bodyparts

	for(var/obj/item/organ/organ as anything in cloned_human.internal_organs)
		if(!istype(organ) || (organ.organ_flags & ORGAN_VITAL))
			continue
		organ.organ_flags |= ORGAN_FROZEN
		organ.Remove(cloned_human, special=TRUE)
		organ.forceMove(src)
		unattached_flesh += organ

	flesh_number = unattached_flesh.len

/obj/machinery/clonepod/mapped/Initialize()
	. = ..()
	beaker = new /obj/item/reagent_containers/cup/beaker/large(src)
	beaker.reagents.add_reagent(/datum/reagent/medicine/c2/synthflesh, 100)

#undef CLONE_INITIAL_DAMAGE
#undef SPEAK
#undef MINIMUM_HEAL_LEVEL
