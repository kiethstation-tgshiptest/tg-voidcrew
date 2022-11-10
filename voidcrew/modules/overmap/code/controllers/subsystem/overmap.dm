/*
voidcrew TODO:
	SSovermap originally fired to apply the planet effects but these would be way better off just using signals



*/

#define MAX_OVERMAP_EVENT_CLUSTERS 8
#define MAX_OVERMAP_EVENTS 70
#define MAX_OVERMAP_PLACEMENT_ATTEMPTS 20
#define MAX_OVERMAP_PLANETS_TO_SPAWN 5

SUBSYSTEM_DEF(overmap)
	name = "Overmap"
	wait = 10
	init_order = INIT_ORDER_OVERMAP
	flags = SS_NO_FIRE
	runlevels = RUNLEVEL_SETUP | RUNLEVEL_GAME

	/// Centre of the overmap
	var/turf/overmap_centre
	/// Map of tiles at each radius around the sun
	var/list/list/radius_tiles = list()
	/// List of all events
	var/list/events = list()

	///List of all simulated ships
	var/list/simulated_ships = list()

/datum/controller/subsystem/overmap/Initialize(start_timeofday)
	create_map()
	setup_sun()
	setup_dangers()
	setup_planets()

	return ..()

/datum/controller/subsystem/overmap/proc/create_map()
	// creates the overmap area and sets it up
	var/area/overmap/overmap_area = new
	overmap_area.setup("Overmap")

	// locates the area we want the overmap to be
	var/turf/top_left = locate(OVERMAP_LEFT_SIDE_COORD, OVERMAP_NORTH_SIDE_COORD, OVERMAP_Z_LEVEL)
	var/turf/bottom_right = locate(OVERMAP_RIGHT_SIDE_COORD, OVERMAP_SOUTH_SIDE_COORD, OVERMAP_Z_LEVEL)
	var/list/overmap_turfs = block(top_left, bottom_right)
	for (var/turf/overmap_turf as anything in overmap_turfs)
		if (overmap_turf.x == OVERMAP_LEFT_SIDE_COORD || overmap_turf.x == OVERMAP_RIGHT_SIDE_COORD || overmap_turf.y == OVERMAP_NORTH_SIDE_COORD || overmap_turf.y == OVERMAP_SOUTH_SIDE_COORD)
			overmap_turf.ChangeTurf(/turf/closed/overmap_edge)
		else
			overmap_turf.ChangeTurf(/turf/open/overmap)
		var/area/old_area = get_area(overmap_turf)
		old_area.turfs_to_uncontain += overmap_turf
		overmap_area.contents += overmap_turf
		overmap_area.contained_turfs += overmap_turf
	overmap_area.reg_in_areas_in_z()
	// not actually the centre but close enough
	overmap_centre = get_turf(locate((OVERMAP_LEFT_SIDE_COORD + ((OVERMAP_SIZE - 1) / 2)) - 1, (OVERMAP_SOUTH_SIDE_COORD + ((OVERMAP_SIZE - 1) / 2)) - 1, OVERMAP_Z_LEVEL))

/datum/controller/subsystem/overmap/proc/setup_sun()
	var/turf/open/overmap/centre_tile = overmap_centre
	if(!istype(centre_tile))
		can_fire = FALSE
		message_admins("Overmap failed to generate the map, this is a critical error.")
		CRASH("Overmap did not generate correctly!")

	var/obj/structure/overmap/star/big/star_to_spawn = pick(/obj/structure/overmap/star/big, /obj/structure/overmap/star/big/binary)
	star_to_spawn = new

	star_to_spawn.forceMove(centre_tile)
	new /obj/effect/landmark/observer_start(centre_tile)

	var/list/unsorted_turfs = get_area_turfs(/area/overmap, target_z = OVERMAP_Z_LEVEL)
	var/max_ring = 0
	for (var/turf/turf in unsorted_turfs)
		// the overmap is a square, so we can just use the x and y values to determine the actual ring
		// 2 2 2 2 2
		// 2 1 1 1 2
		// 2 1 X 1 2
		// 2 1 1 1 2
		// 2 2 2 2 2
		var/ring_x = turf.x - overmap_centre.x
		var/ring_y = turf.y - overmap_centre.y
		var/ring = max(abs(ring_x), abs(ring_y))
		if (ring == 0)
			continue
		if (ring > max_ring)
			for (var/i in 1 to ring - max_ring)
				radius_tiles += list(list())
			max_ring = ring
		LAZYADDASSOC(radius_tiles, ring, turf)

/datum/controller/subsystem/overmap/proc/get_unused_overmap_square(thing_not_to_have = /obj/structure/overmap, tries = MAX_OVERMAP_PLACEMENT_ATTEMPTS, force = FALSE)
	var/turf/turf_to_return
	for (var/_ in 1 to tries)
		turf_to_return = pick(block(locate(OVERMAP_LEFT_SIDE_COORD + 1, OVERMAP_SOUTH_SIDE_COORD + 1, OVERMAP_Z_LEVEL), locate(OVERMAP_RIGHT_SIDE_COORD - 1, OVERMAP_NORTH_SIDE_COORD - 1, OVERMAP_Z_LEVEL))) // todo : see if this is expensive
		if (locate(thing_not_to_have) in turf_to_return)
			continue
		return turf_to_return
	if (!force)
		turf_to_return = null
	return turf_to_return

/datum/controller/subsystem/overmap/proc/get_unused_overmap_square_in_radius(radius, thing_not_to_have = /obj/structure/overmap, tries = MAX_OVERMAP_PLACEMENT_ATTEMPTS, force = FALSE)
	if (!radius)
		radius = rand(2, length(radius_tiles) / 2)

	var/turf/turf_to_return
	for (var/_ in 1 to tries)
		turf_to_return = pick(radius_tiles[radius])
		if (locate(thing_not_to_have) in turf_to_return)
			continue
		return turf_to_return

	if (!force)
		turf_to_return = null
	return turf_to_return


/datum/controller/subsystem/overmap/proc/setup_dangers()
	var/list/orbits = list()
	for (var/i in 2 to LAZYLEN(radius_tiles))
		orbits += "[i]"

	for (var/_ in 1 to MAX_OVERMAP_EVENT_CLUSTERS)
		if (MAX_OVERMAP_EVENTS <= LAZYLEN(events))
			return
		if (LAZYLEN(orbits) == 0 || !orbits)
			break // can't fit anymore in
		var/selected_orbit = text2num(pick(orbits))

		var/turf/turf_for_event = get_unused_overmap_square_in_radius(selected_orbit)
		if (!turf_for_event || !istype(turf_for_event))
			orbits -= "[selected_orbit]" // this one is full
			continue
		var/event_type = pick_weight(GLOB.overmap_event_pick_list)
		var/obj/structure/overmap/event/event_to_spawn = new event_type(turf_for_event)
		for (var/turf/turf_to_spawn as anything in radius_tiles[selected_orbit])
			if (locate(/obj/structure/overmap) in turf_to_spawn)
				continue
			if (!prob(event_to_spawn.spread_chance))
				continue
			new event_type(turf_to_spawn)

/datum/controller/subsystem/overmap/proc/setup_planets()
	var/list/orbits = list()
	for (var/i in 2 to LAZYLEN(radius_tiles))
		orbits += "[i]"

	for (var/_ in 1 to MAX_OVERMAP_PLANETS_TO_SPAWN)
		if (LAZYLEN(orbits) == 0 || !orbits)
			break // can't fit anymore in
		var/selected_orbit = text2num(pick(orbits))

		var/turf/turf_for_planet = get_unused_overmap_square_in_radius(selected_orbit)
		if (!turf_for_planet || !istype(turf_for_planet))
			orbits -= "[selected_orbit]" // this one is full
			continue
		var/planet_type = pick(subtypesof(/datum/overmap/planet))
		var/obj/structure/overmap/planet/planet_to_spawn = new
		planet_to_spawn.planet = planet_type
		planet_to_spawn.forceMove(turf_for_planet)

		// Transfer all of the data from the planet datum onto the planet object
		var/datum/overmap/planet/planet_info = new planet_to_spawn.planet
		planet_to_spawn.name = planet_info.name
		planet_to_spawn.desc = planet_info.desc
		planet_to_spawn.icon_state = planet_info.icon_state
		planet_to_spawn.color = planet_info.color
		qdel(planet_info)

/datum/controller/subsystem/overmap/proc/get_containing_ship(area/source)
	if(!source)
		return

	if(!isarea(source))
		source = get_area(source)

	for(var/obj/structure/overmap/ship/ship as anything in simulated_ships)
		var/obj/docking_port/mobile/ship_shuttle = ship.shuttle
		for(var/area/shuttle_area as anything in ship_shuttle?.shuttle_areas)
			if(shuttle_area == source)
				return ship

// TODO - MULTI-Z VLEVELS
/datum/controller/subsystem/overmap/proc/calculate_turf_above(turf/T)
	return

// TODO - MULTI-Z VLEVELS
/datum/controller/subsystem/overmap/proc/calculate_turf_below(turf/T)
	return
