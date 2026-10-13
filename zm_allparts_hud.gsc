// ============================================================================
//  All Parts HUD + Origins-style multi-part carrying
//  BO2 Zombies (Plutonium T6)
//  Maps: Tranzit (zm_transit), Die Rise (zm_highrise), Buried (zm_buried)
//
//  1) PARTS PANEL (all 3 maps)
//     BO3-style parts panel under your score. Hidden by default.
//     HOLD TAB (this mod's install.bat binds it to "+switchseat", an input
//     that has no effect in Zombies) to show it, RELEASE to hide it.
//
//  2) CARRY MANY PARTS AT ONCE (Tranzit + Die Rise)
//     Every part type gets its own inventory slot, so you can sweep the map
//     and carry one of everything - Origins/BO3 style. A build table only
//     accepts a build once you are carrying the WHOLE remaining set of parts
//     for it; while you are missing some it just says "need more parts".
//     When you do hold USE with the full set, it builds every part in one go
//     and finishes the buildable. (Placing a partial set used to leave the
//     table half-built and unable to accept the last part.)
//     Parts still spawn at ONE random spot each game, exactly like vanilla.
//
//     Buried is left vanilla: its sloth AI (booze/candy/keys) natively uses
//     a separate slot, so there you still carry one table part + one sloth
//     item at a time.
//
//  3) PICKUP NOTIFICATION (all 3 maps)
//     The original game's little corner "part" icon is hidden. Instead, when
//     you pick a part up, a readout appears in the TOP-LEFT showing the
//     buildable's icon and how many of its parts you are carrying, e.g.
//     "[icon] 1/3 parts". It fades out a few seconds later.
//
//  4) FEEDBACK & COUNTERS (all 3 maps)
//     - A short white screen flash confirms each pickup. The game's own
//       "zmb_buildable_pickup" sound still plays on top of it.
//     - When a buildable's final part is placed, a green "<NAME> COMPLETE"
//       banner pops up just under the crosshair for a couple of seconds.
//     - The parts panel header now reads:
//           PARTS (carried)      built/total BUILT
//       so you can see your total carried parts and how many buildables are
//       finished without counting rows.
// ============================================================================

#include maps\mp\_utility;
#include common_scripts\utility;
#include maps\mp\gametypes_zm\_hud_util;
#include maps\mp\zombies\_zm_utility;

init()
{
    mapname = getDvar( "mapname" );

    if ( mapname != "zm_transit" && mapname != "zm_highrise" && mapname != "zm_buried" )
        return;

    level thread allparts_carry_setup();
    level thread allparts_hud_players_watch();
}

// ===========================================================================
// PART 1 - carry many parts at once (slot per part type)
// ===========================================================================

allparts_carry_setup()
{
    level endon( "game_ended" );

    if ( getDvar( "mapname" ) == "zm_buried" )
        return;

    while ( !isdefined( level.buildable_stubs ) || level.buildable_stubs.size < 1 )
        wait 0.25;

    allparts_assign_slots();
    allparts_patch_bench_prompts();
    allparts_patch_onuse();
    allparts_patch_deposit_all();

    // pieces are only created after this flag - make sure the new slots
    // actually reached the live pieces, no matter who won the race
    flag_wait( "start_zombie_round_logic" );
    wait 1;

    allparts_assign_slots();
    allparts_fix_live_piece_slots();
    allparts_patch_deposit_all();
}

// copy the slot of each part's template onto its live spawned pieces, so the
// pickup prompt and the carry slots see the new per-part slots even if the
// pieces were generated before the assignment above ran.
allparts_fix_live_piece_slots()
{
    foreach ( stub in level.buildable_stubs )
    {
        if ( isdefined( stub.piece ) && isdefined( stub.piece.piecespawn ) )
        {
            stub.piece.buildable_slot = stub.piece.piecespawn.buildable_slot;
            stub.piece.client_field_state = undefined; // no vanilla corner icon
        }

        if ( isdefined( stub.buildablezone ) && isdefined( stub.buildablezone.pieces ) )
        {
            foreach ( piece in stub.buildablezone.pieces )
            {
                if ( isdefined( piece.piecespawn ) )
                {
                    piece.buildable_slot = piece.piecespawn.buildable_slot;
                    piece.client_field_state = undefined; // no vanilla corner icon
                }
            }
        }
    }
}

// give every unique part type its own buildable_slot.
// structs shared between buildables (bus hatch, pap battery, keys) get one
// slot total, so they are counted once and work at every table that needs them.
allparts_assign_slots()
{
    if ( !isdefined( level.zombie_buildables ) )
        return;

    bps = [];

    foreach ( buildable in level.zombie_buildables )
    {
        if ( !isdefined( buildable.buildablepieces ) )
            continue;

        foreach ( bp in buildable.buildablepieces )
        {
            if ( isinarray( bps, bp ) )
                continue;

            bps[bps.size] = bp;
            bp.buildable_slot = bps.size - 1;
            // hide the vanilla corner "carried part" HUD icon: it is drawn by
            // the client from this state. Clearing it here means picking a part
            // never triggers the icon at all (only our parts panel shows).
            bp.client_field_state = undefined;
        }
    }

    foreach ( buildable in level.zombie_buildables )
    {
        if ( isdefined( buildable.buildablepieces ) && buildable.buildablepieces.size > 0 )
        {
            buildable.buildable_slot = buildable.buildablepieces[0].buildable_slot;
            buildable.allparts_default_slot = buildable.buildable_slot;
        }
    }
}

// wrap every build-table prompt: before the game decides what the bench can
// do, point the bench (and its zone) at the slot of the part the player is
// actually carrying, so the normal build code finds it.
allparts_patch_bench_prompts()
{
    foreach ( stub in level.buildable_stubs )
    {
        if ( isdefined( stub.piece ) )
            continue;

        if ( !isdefined( stub.buildablestruct ) )
            continue;

        if ( !isdefined( stub.prompt_and_visibility_func ) )
            continue;

        if ( isdefined( stub.allparts_prompt_patched ) )
            continue;

        stub.allparts_orig_prompt = stub.prompt_and_visibility_func;
        stub.prompt_and_visibility_func = ::allparts_bench_prompt;
        stub.allparts_prompt_patched = 1;
    }
}

allparts_bench_prompt( player )
{
    stub = self.stub;

    if ( isdefined( stub ) )
        allparts_shim_bench_slot( player, stub );

    return self [[ stub.allparts_orig_prompt ]]( player );
}

allparts_shim_bench_slot( player, stub )
{
    if ( !isdefined( stub.buildablestruct ) )
        return;

    zone = stub.buildablezone;
    pool = stub.buildable_pool;

    candidates = [];

    if ( isdefined( pool ) && !isdefined( stub.bound_to_buildable ) )
    {
        foreach ( pstub in pool.stubs )
        {
            if ( isdefined( pstub.bound_to_buildable ) )
                continue;

            if ( isdefined( pstub.buildablezone ) && isdefined( pstub.buildablezone.pieces ) )
                candidates[candidates.size] = pstub.buildablezone;
        }
    }
    else if ( isdefined( zone ) && isdefined( zone.pieces ) )
        candidates[candidates.size] = zone;

    if ( candidates.size < 1 )
        return;

    best = undefined;
    best_zone = undefined;
    first_carried = undefined;

    pieces = player maps\mp\zombies\_zm_buildables::player_get_buildable_pieces();

    foreach ( piece in pieces )
    {
        if ( !isdefined( piece ) )
            continue;

        if ( !isdefined( first_carried ) )
            first_carried = piece;

        found_building = false;

        foreach ( cand in candidates )
        {
            if ( !cand maps\mp\zombies\_zm_buildables::buildable_has_piece( piece ) )
                continue;

            if ( cand maps\mp\zombies\_zm_buildables::buildable_is_piece_building( piece ) )
            {
                best = piece;
                best_zone = cand;
                found_building = true;
                break;
            }

            if ( !cand maps\mp\zombies\_zm_buildables::buildable_is_piece_built( piece ) && !isdefined( best ) )
            {
                best = piece;
                best_zone = cand;
            }
        }

        if ( found_building )
            break;
    }

    if ( isdefined( best ) )
    {
        // Origins-style rule: a table only accepts a build when you are
        // carrying the WHOLE set of parts that are still missing for it.
        // While you are missing some, point the table at a part you do not
        // have yet, so the game shows "need more parts" and refuses to build
        // (this also avoids leaving a buildable half-built, which used to
        // wedge the table so the last part could not be placed).
        if ( allparts_zone_ready( player, best_zone ) )
        {
            allparts_apply_slot( best_zone, best.buildable_slot );
            stub.buildablestruct.buildable_slot = best.buildable_slot;
        }
        else
        {
            miss = allparts_first_missing_slot( player, best_zone );
            allparts_apply_slot( best_zone, miss );

            if ( isdefined( miss ) )
                stub.buildablestruct.buildable_slot = miss;
        }
    }
    else if ( isdefined( first_carried ) )
    {
        allparts_apply_slot( candidates[0], first_carried.buildable_slot );
    }
    else
    {
        foreach ( cand in candidates )
        {
            need = allparts_first_needed_slot( cand );

            if ( isdefined( need ) )
            {
                allparts_apply_slot( cand, need );
                break;
            }
        }
    }
}

allparts_apply_slot( zone, slot )
{
    if ( !isdefined( zone ) || !isdefined( slot ) )
        return;

    zone.buildable_slot = slot;

    if ( isdefined( zone.stub ) && isdefined( zone.stub.buildablestruct ) )
        zone.stub.buildablestruct.buildable_slot = slot;
}

allparts_first_needed_slot( zone )
{
    foreach ( piece in zone.pieces )
    {
        if ( !isdefined( piece ) )
            continue;

        if ( isdefined( piece.built ) && piece.built )
            continue;

        if ( isdefined( piece.building ) && piece.building )
            continue;

        if ( isdefined( piece.buildable_slot ) )
            return piece.buildable_slot;

        if ( isdefined( piece.piecespawn ) && isdefined( piece.piecespawn.buildable_slot ) )
            return piece.piecespawn.buildable_slot;
    }

    return undefined;
}

// true only when the player is carrying every part of this buildable that is
// not already built (so it can be finished in one go). Shared/team-built
// pieces are ignored - they are already marked built on the zone.
allparts_zone_ready( player, zone )
{
    if ( !isdefined( zone ) || !isdefined( zone.pieces ) )
        return false;

    carried = player maps\mp\zombies\_zm_buildables::player_get_buildable_pieces();

    for ( i = 0; i < zone.pieces.size; i++ )
    {
        piece = zone.pieces[i];

        if ( !isdefined( piece ) )
            continue;

        if ( isdefined( piece.built ) && piece.built )
            continue;

        found = false;

        foreach ( c in carried )
        {
            if ( isdefined( c ) && c.modelname == piece.modelname && c.buildablename == piece.buildablename )
                found = true;
        }

        if ( !found )
            return false;
    }

    return true;
}

// slot of the first not-yet-built part this player is NOT carrying (used to
// park the table on a part we lack, which makes the game show "need more
// parts" and block the build until the whole set is collected).
allparts_first_missing_slot( player, zone )
{
    if ( !isdefined( zone ) || !isdefined( zone.pieces ) )
        return undefined;

    carried = player maps\mp\zombies\_zm_buildables::player_get_buildable_pieces();

    for ( i = 0; i < zone.pieces.size; i++ )
    {
        piece = zone.pieces[i];

        if ( !isdefined( piece ) )
            continue;

        if ( isdefined( piece.built ) && piece.built )
            continue;

        found = false;

        foreach ( c in carried )
        {
            if ( isdefined( c ) && c.modelname == piece.modelname && c.buildablename == piece.buildablename )
                found = true;
        }

        if ( !found )
            return piece.buildable_slot;
    }

    return undefined;
}

// these map callbacks read the carried part from slot 0 directly - repoint
// them at the shimmed bench slot so they show the right model part
allparts_patch_onuse()
{
    if ( !isdefined( level.zombie_buildables ) )
        return;

    // patch only once - capturing the map's callback twice would make us end
    // up calling ourselves
    if ( isdefined( level.allparts_onuse_patched ) )
        return;

    level.allparts_onuse_patched = 1;

    mapname = getDvar( "mapname" );

    if ( mapname == "zm_transit" )
    {
        if ( isdefined( level.zombie_buildables["powerswitch"] ) )
            level.zombie_buildables["powerswitch"].onuseplantobject = ::allparts_onuse_powerswitch;

        if ( isdefined( level.zombie_buildables["turbine"] ) )
        {
            // remember the map's own callback (it plays Tranzit's turbine
            // voice line). Storing it as a pointer lets us call it dynamically
            // later, so the script has no hard reference to a Tranzit-only
            // function - that reference used to make Die Rise / Buried fail to
            // load with "Unresolved external".
            level.zombie_buildables["turbine"].allparts_orig_onuseplantobject = level.zombie_buildables["turbine"].onuseplantobject;
            level.zombie_buildables["turbine"].onuseplantobject = ::allparts_onuse_turbine;
        }
    }
    else if ( mapname == "zm_highrise" )
    {
        if ( isdefined( level.zombie_buildables["slipgun_zm"] ) )
            level.zombie_buildables["slipgun_zm"].onuseplantobject = ::allparts_onuse_slipgun;
    }
}

allparts_onuse_powerswitch( player )
{
    piece = player maps\mp\zombies\_zm_buildables::player_get_buildable_piece( self.buildablezone.buildable_slot );

    if ( !isdefined( piece ) )
        return;

    switch ( piece.modelname )
    {
        case "p6_zm_buildable_pswitch_hand":
            ent = getent( "powerswitch_p6_zm_buildable_pswitch_hand", "targetname" );

            if ( isdefined( ent ) )
                ent show();

            break;
        case "p6_zm_buildable_pswitch_body":
            panel = getent( "powerswitch_p6_zm_buildable_pswitch_body", "targetname" );

            if ( isdefined( panel ) )
                panel show();

            break;
        case "p6_zm_buildable_pswitch_lever":
            ent = getent( "powerswitch_p6_zm_buildable_pswitch_lever", "targetname" );

            if ( isdefined( ent ) )
                ent show();

            break;
    }
}

allparts_onuse_turbine( player )
{
    buildable = self.buildablezone;

    if ( !isdefined( buildable ) )
        return;

    // run the map's own callback first (plays Tranzit's turbine voice line).
    // Called through a stored pointer so no Tranzit-only symbol is referenced.
    if ( isdefined( self.buildablestruct ) && isdefined( self.buildablestruct.allparts_orig_onuseplantobject ) )
        self [[ self.buildablestruct.allparts_orig_onuseplantobject ]]( player );

    // then re-point the visible model part at the piece actually being placed
    // (the map's callback reads carry slot 0 directly, which is wrong now that
    // we can carry many parts at once)
    piece = player maps\mp\zombies\_zm_buildables::player_get_buildable_piece( buildable.buildable_slot );
    first_part = "tag_part_03";
    second_part = "tag_part_02";

    for ( i = 0; i < buildable.pieces.size; i++ )
    {
        if ( buildable.pieces[i].part_name == first_part )
        {
            if ( isdefined( buildable.pieces[i].built ) && buildable.pieces[i].built || isdefined( piece ) && piece.part_name == first_part )
            {
                buildable.stub.model showpart( second_part );
                continue;
            }

            buildable.stub.model hidepart( second_part );
        }
    }
}

allparts_onuse_slipgun( player )
{
    buildable = self.buildablezone;
    piece = player maps\mp\zombies\_zm_buildables::player_get_buildable_piece( buildable.buildable_slot );
    first_part = "TAG_COOKER";
    second_part = "TAG_BASE";

    for ( i = 0; i < buildable.pieces.size; i++ )
    {
        if ( buildable.pieces[i].part_name == first_part )
        {
            if ( isdefined( buildable.pieces[i].built ) && buildable.pieces[i].built || isdefined( piece ) && piece.part_name == first_part )
            {
                buildable.stub.model showpart( second_part );
                continue;
            }

            buildable.stub.model hidepart( second_part );
        }
    }
}

// when a build table's hold completes, deposit EVERY part of that buildable
// the player is carrying in one go (Origins / BO3 style) instead of only the
// single part the table's slot happens to point at. The table's own onuse
// callback still runs first, so map-specific effects are untouched.
allparts_patch_deposit_all()
{
    foreach ( stub in level.buildable_stubs )
    {
        if ( isdefined( stub.piece ) )
            continue;

        if ( !isdefined( stub.buildablezone ) )
            continue;

        if ( !isdefined( stub.onuse ) )
            continue;

        if ( isdefined( stub.allparts_onuse_patched ) && stub.allparts_onuse_patched )
            continue;

        stub.allparts_orig_onuse = stub.onuse;
        stub.onuse = ::allparts_bench_use_all;
        stub.allparts_onuse_patched = 1;
    }
}

allparts_bench_use_all( player )
{
    stub = self;

    if ( isdefined( stub ) && isdefined( stub.allparts_orig_onuse ) )
        self [[ stub.allparts_orig_onuse ]]( player );

    if ( !isdefined( stub ) || !isdefined( stub.buildablezone ) )
        return;

    zone = stub.buildablezone;

    if ( !isdefined( zone.pieces ) )
        return;

    // safety net: never place a partial set - only build with the full set.
    // If the table's prompt was stale, the vanilla code right after this call
    // would place the single slot part; parking the slot on a part we do NOT
    // carry makes it skip that, so a partial set can never be placed.
    if ( !allparts_zone_ready( player, zone ) )
    {
        miss = allparts_first_missing_slot( player, zone );

        if ( isdefined( miss ) )
        {
            zone.buildable_slot = miss;

            if ( isdefined( stub.buildablestruct ) )
                stub.buildablestruct.buildable_slot = miss;
        }

        return;
    }

    all = player maps\mp\zombies\_zm_buildables::player_get_buildable_pieces();
    pieces = [];

    foreach ( piece in all )
    {
        if ( !isdefined( piece ) )
            continue;

        if ( zone maps\mp\zombies\_zm_buildables::buildable_has_piece( piece ) )
            pieces[pieces.size] = piece;
    }

    if ( pieces.size < 1 )
        return;

    // player_build() accepts an array of parts and builds them all at once,
    // showing every model part and finishing the buildable when complete.
    prompt = player maps\mp\zombies\_zm_buildables::player_build( zone, pieces );
    stub.hint_string = prompt;
}

// ===========================================================================
// PART 2 - BO3 style parts panel under the score
// ===========================================================================

allparts_hud_players_watch()
{
    level endon( "game_ended" );

    players = get_players();

    foreach ( player in players )
    {
        if ( isdefined( player ) )
            player thread allparts_hud_player();
    }

    while ( true )
    {
        level waittill( "connected", player );
        player thread allparts_hud_player();
    }
}

allparts_hud_player()
{
    self endon( "disconnect" );

    if ( isdefined( self.parts_hud_watched ) )
        return;

    self.parts_hud_watched = 1;
    self.parts_hud_visible = 0;

    self waittill( "spawned_player" );

    while ( !isdefined( level.buildable_stubs ) || level.buildable_stubs.size < 1 )
        wait 0.5;

    hud = allparts_hud_build();

    self thread allparts_hide_carry_icon_think();
    self thread allparts_pickup_watch();
    self thread allparts_complete_watch( hud );
    self thread allparts_hud_refresh( hud );
    allparts_hud_update( hud );
}

// ===========================================================================
// Hide the ORIGINAL game's "carried part" icon (the little shader that pops
// into a corner when you pick a part up). The client draws it from the
// buildable client field(s); we keep those fields cleared so only this mod's
// parts panel is shown. This does NOT touch the actual carried part data, so
// building at the workbenches still works exactly the same.
// ===========================================================================
allparts_hide_carry_icon_think()
{
    self endon( "disconnect" );

    while ( true )
    {
        allparts_clear_carry_icon();

        // a part is only held for a moment between the pickup and this loop,
        // so clear often enough that the icon can never sit on screen
        wait 0.1;
    }
}

allparts_clear_carry_icon()
{
    if ( isdefined( level.buildable_slot_count ) && isdefined( level.buildable_clientfields ) )
    {
        for ( i = 0; i < level.buildable_slot_count; i++ )
            allparts_clear_clientfield( self, level.buildable_clientfields[i] );
    }
    else
    {
        allparts_clear_clientfield( self, "buildable" );
    }
}

allparts_clear_clientfield( player, field_name )
{
    if ( !isdefined( field_name ) )
        return;

    // unconditionally push 0: the vanilla game sets this field on pickup and
    // that is what draws the corner icon. (setclientfieldtoplayer is used by
    // the game itself, so it is safe on every map we support.)
    player setclientfieldtoplayer( field_name, 0 );
}

// ===========================================================================
// Pickup notification (all 3 maps)
// The vanilla corner "part" icon is kept hidden; this replaces it with a
// bottom-left readout: the picked part's icon plus how many parts of that
// buildable you are carrying, e.g. "1/3 parts". It pops up on pickup and
// fades out a few seconds later.
// ===========================================================================
allparts_pickup_watch()
{
    self endon( "disconnect" );

    while ( !isdefined( level.buildable_stubs ) || level.buildable_stubs.size < 1 )
        wait 0.5;

    hud = allparts_pickup_hud_build();
    self.allparts_pickup_hud = hud;

    self.allparts_pickup_seen = [];
    hud.timer = 0;

    while ( true )
    {
        allparts_pickup_check( hud );

        if ( hud.timer > 0 )
        {
            hud.timer -= 0.1;

            if ( hud.timer <= 0 )
                allparts_pickup_hud_hide( hud );
        }

        wait 0.1;
    }
}

allparts_pickup_hud_build()
{
    hud = spawnstruct();

    // icon of the BUILDABLE (same icon whichever of its parts you grab)
    icon = self createicon( "white", 40, 40 );
    icon setpoint( "TOP LEFT", "TOP LEFT", 24, 44 );
    icon.horzalign = "left";
    icon.vertalign = "top";
    icon.alpha = 0;
    hud.icon = icon;

    // how many of that buildable's parts you carry (e.g. "1/3 parts"),
    // drawn just to the right of the icon.
    // "small" is the game's own small-HUD font (the one it uses for loadout
    // attribute text), so scale 1 is already tiny. Nudge it from the console
    // if wanted:  allparts_pickup_scale 1.2
    scale = getdvarfloat( "allparts_pickup_scale" );

    if ( scale <= 0 )
        scale = 1.0;

    count = self createfontstring( "small", scale );
    count setpoint( "TOP LEFT", "TOP LEFT", 74, 56 );
    count.horzalign = "left";
    count.vertalign = "top";
    count.alpha = 0;
    hud.count = count;
    hud.scale = scale;

    // short white screen flash played on every pickup (fullscreen overlay)
    flash = self createicon( "white", 640, 480 );
    flash.horzalign = "fullscreen";
    flash.vertalign = "fullscreen";
    flash.foreground = 1;
    flash.color = ( 1, 1, 1 );
    flash.alpha = 0;
    hud.flash = flash;

    return hud;
}

allparts_pickup_check( hud )
{
    carried = self maps\mp\zombies\_zm_buildables::player_get_buildable_pieces();

    now = [];

    foreach ( piece in carried )
    {
        if ( isdefined( piece ) )
            now[now.size] = piece;
    }

    foreach ( piece in now )
    {
        if ( !isinarray( self.allparts_pickup_seen, piece.modelname ) )
            allparts_pickup_show( hud, piece );
    }

    seen = [];

    foreach ( piece in now )
        seen[seen.size] = piece.modelname;

    self.allparts_pickup_seen = seen;
}

allparts_pickup_show( hud, piece )
{
    buildablename = piece.buildablename;

    // live size tuning: if the console dvar is set (or changed), rebuild the
    // text element so the new size definitely takes effect on the next pickup
    scale = getdvarfloat( "allparts_pickup_scale" );

    if ( scale > 0 && ( !isdefined( hud.scale ) || scale != hud.scale ) )
    {
        hud.count destroyelem();
        count = self createfontstring( "small", scale );
        count setpoint( "TOP LEFT", "TOP LEFT", 74, 56 );
        count.horzalign = "left";
        count.vertalign = "top";
        count.alpha = 0;
        hud.count = count;
        hud.scale = scale;
    }

    total = 0;
    have = 0;

    buildable = undefined;

    if ( isdefined( buildablename ) && isdefined( level.zombie_buildables ) )
        buildable = level.zombie_buildables[buildablename];

    if ( isdefined( buildable ) && isdefined( buildable.buildablepieces ) )
    {
        total = buildable.buildablepieces.size;

        carried = self maps\mp\zombies\_zm_buildables::player_get_buildable_pieces();

        foreach ( bp in buildable.buildablepieces )
        {
            foreach ( cp in carried )
            {
                if ( isdefined( cp ) && isdefined( bp.modelname ) && cp.modelname == bp.modelname )
                {
                    have++;
                    break;
                }
            }
        }
    }

    if ( total < 1 )
        total = 1;

    hud.icon setshader( allparts_buildable_icon( buildablename, piece ), 40, 40 );

    // green once you are carrying the whole set (ready to build that table)
    if ( have >= total )
        hud.count.color = ( 0.35, 1, 0.35 );
    else
        hud.count.color = ( 1, 1, 1 );

    hud.count settext( have + "/" + total + " parts" );

    hud.icon fadeovertime( 0.1 );
    hud.icon.alpha = 1;
    hud.count fadeovertime( 0.1 );
    hud.count.alpha = 1;

    // quick confirmation flash (bright, then fade straight back out)
    hud.flash.alpha = 0.22;
    hud.flash fadeovertime( 0.3 );
    hud.flash.alpha = 0;

    hud.timer = 5.0;
}

allparts_pickup_hud_hide( hud )
{
    hud.icon fadeovertime( 0.6 );
    hud.icon.alpha = 0;
    hud.count fadeovertime( 0.6 );
    hud.count.alpha = 0;
    hud.timer = 0;
}

// one representative icon for a whole buildable (its first part with a shader),
// so the readout always shows the same "turbine"-style icon, not the specific
// part you happened to grab.
allparts_buildable_icon( buildablename, piece )
{
    if ( isdefined( buildablename ) && isdefined( level.zombie_buildables ) )
    {
        buildable = level.zombie_buildables[buildablename];

        if ( isdefined( buildable ) && isdefined( buildable.buildablepieces ) )
        {
            foreach ( bp in buildable.buildablepieces )
            {
                if ( isdefined( bp ) && isdefined( bp.hud_icon ) )
                    return bp.hud_icon;
            }
        }
    }

    if ( isdefined( piece ) && isdefined( piece.hud_icon ) )
        return piece.hud_icon;

    return "white";
}

allparts_hud_build()
{
    hud = spawnstruct();
    hud.rows = [];

    y = 66;

    header = self createfontstring( "default", 1.2 );
    header setpoint( "TOPCENTER", "TOPCENTER", 0, y );
    header settext( "PARTS" );
    header.alpha = 0;
    hud.header = header;

    y += 22;

    seen = [];

    foreach ( stub in level.buildable_stubs )
    {
        equip = stub.equipname;

        if ( !isdefined( equip ) || isinarray( seen, equip ) )
            continue;

        seen[seen.size] = equip;

        buildable = level.zombie_buildables[equip];

        if ( !isdefined( buildable ) || !isdefined( buildable.buildablepieces ) || buildable.buildablepieces.size < 1 )
            continue;

        row = spawnstruct();

        label = self createfontstring( "default", 1.0 );
        label setpoint( "TOPCENTER", "TOPCENTER", -110, y );
        label settext( allparts_pretty_name( equip ) );
        label.alpha = 0;
        row.label = label;

        count = self createfontstring( "default", 1.0 );
        count setpoint( "TOPCENTER", "TOPCENTER", 12, y );
        count settext( "0/" + buildable.buildablepieces.size );
        count.alpha = 0;
        row.count = count;

        row.bps = [];
        row.icons = [];

        ix = 52;

        foreach ( bp in buildable.buildablepieces )
        {
            if ( isdefined( bp.hud_icon ) )
            {
                icon = self createicon( bp.hud_icon, 12, 12 );
                icon setpoint( "TOPCENTER", "TOPCENTER", ix, y + 2 );
                icon.alpha = 0;
                row.icons[row.icons.size] = icon;
                row.bps[row.bps.size] = bp;
                ix += 15;
            }
        }

        row.zone = stub.buildablezone;
        row.equip = equip;

        hud.rows[hud.rows.size] = row;
        y += 17;
    }

    return hud;
}

allparts_hud_refresh( hud )
{
    self endon( "disconnect" );

    last_visible = -1;
    refresh_timer = 0;

    while ( true )
    {
        // TAB is bound to "+switchseat" (see README / install.bat): a held-key
        // input [changeseatbuttonpressed()] that has no gameplay effect in ZM.
        // held = panel shown, released = panel hidden.
        visible = 0;

        if ( self changeseatbuttonpressed() )
            visible = 1;

        if ( visible != last_visible )
        {
            self.parts_hud_visible = visible;
            allparts_hud_update( hud );
            last_visible = visible;
            refresh_timer = 0;
        }
        else if ( visible )
        {
            refresh_timer += 0.1;

            if ( refresh_timer >= 0.5 )
            {
                allparts_hud_update( hud );
                refresh_timer = 0;
            }
        }

        wait 0.1;
    }
}

allparts_hud_update( hud )
{
    visible = self.parts_hud_visible;

    held = [];

    if ( isdefined( self.current_buildable_pieces ) )
    {
        foreach ( piece in self.current_buildable_pieces )
        {
            if ( isdefined( piece ) )
                held[held.size] = piece;
        }
    }

    built_count = 0;

    foreach ( row in hud.rows )
    {
        n = 0;
        total = row.bps.size;

        for ( i = 0; i < row.bps.size; i++ )
        {
            has = false;

            foreach ( piece in held )
            {
                if ( isdefined( piece.modelname ) && piece.modelname == row.bps[i].modelname )
                {
                    has = true;
                    break;
                }
            }

            if ( has )
                n++;

            if ( visible )
            {
                if ( has )
                    row.icons[i].alpha = 1;
                else
                    row.icons[i].alpha = 0.25;
            }
            else
                row.icons[i].alpha = 0;
        }

        built = allparts_row_built( row );

        if ( built )
            built_count++;

        if ( visible )
        {
            if ( built )
            {
                // once built, keep showing the full set (e.g. "3/3") in green,
                // even though the parts have left your inventory, and fill
                // every part icon so a finished buildable reads complete
                row.count settext( total + "/" + total );
                row.label.color = ( 0.3, 1, 0.3 );
                row.count.color = ( 0.3, 1, 0.3 );

                for ( j = 0; j < row.icons.size; j++ )
                    row.icons[j].alpha = 1;
            }
            else
            {
                row.count settext( n + "/" + total );
                row.label.color = ( 1, 1, 1 );
                row.count.color = ( 1, 1, 1 );
            }

            row.label.alpha = 0.9;
            row.count.alpha = 0.9;
        }
        else
        {
            row.label.alpha = 0;
            row.count.alpha = 0;
        }
    }

    // header counters: total carried parts + finished buildables
    hud.header settext( "PARTS (" + held.size + ")    " + built_count + "/" + hud.rows.size + " BUILT" );

    if ( visible )
        hud.header.alpha = 0.9;
    else
        hud.header.alpha = 0;
}

// true only when every piece of this buildable's zone has been built.
allparts_row_built( row )
{
    if ( !isdefined( row.zone ) || !isdefined( row.zone.pieces ) || row.zone.pieces.size < 1 )
        return false;

    foreach ( piece in row.zone.pieces )
    {
        if ( !isdefined( piece ) || !isdefined( piece.built ) || !piece.built )
            return false;
    }

    return true;
}

// ===========================================================================
// Buildable-complete banner (all 3 maps)
// Watches each buildable's pieces; the moment one that was not finished
// becomes fully built, a green "<NAME> COMPLETE" banner pops up under the
// crosshair. The game's own "zmb_buildable_complete" sound still plays.
// ===========================================================================
allparts_complete_watch( hud )
{
    self endon( "disconnect" );

    was_built = [];

    for ( i = 0; i < hud.rows.size; i++ )
        was_built[was_built.size] = allparts_row_built( hud.rows[i] );

    while ( true )
    {
        for ( i = 0; i < hud.rows.size; i++ )
        {
            now = allparts_row_built( hud.rows[i] );

            if ( now && !was_built[i] )
                self thread allparts_banner_show( hud.rows[i] );

            was_built[i] = now;
        }

        wait 0.25;
    }
}

allparts_banner_show( row )
{
    self endon( "disconnect" );

    name = "Buildable";

    if ( isdefined( row.equip ) )
        name = allparts_pretty_name( row.equip );

    shader = "white";

    if ( isdefined( row.bps ) )
    {
        foreach ( bp in row.bps )
        {
            if ( isdefined( bp ) && isdefined( bp.hud_icon ) )
            {
                shader = bp.hud_icon;
                break;
            }
        }
    }

    icon = self createicon( shader, 36, 36 );
    icon setpoint( "CENTER", "CENTER", 0, -104 );
    icon.alpha = 0;

    text = self createfontstring( "default", 1.5 );
    text setpoint( "CENTER", "CENTER", 0, -72 );
    text settext( name + " COMPLETE" );
    text.color = ( 0.4, 1, 0.4 );
    text.alpha = 0;

    icon fadeovertime( 0.15 );
    icon.alpha = 1;
    text fadeovertime( 0.15 );
    text.alpha = 1;

    wait 2.2;

    icon fadeovertime( 0.6 );
    icon.alpha = 0;
    text fadeovertime( 0.6 );
    text.alpha = 0;

    wait 0.7;

    icon destroy();
    text destroy();
}

allparts_pretty_name( name )
{
    names = [];

    names["turbine"] = "Turbine";
    names["riotshield_zm"] = "Zombie Shield";
    names["turret"] = "Turret";
    names["electric_trap"] = "Elec. Trap";
    names["jetgun_zm"] = "Jet Gun";
    names["pap"] = "Pack-a-Punch";
    names["powerswitch"] = "Pwr Switch";
    names["cattlecatcher"] = "Bus Plow";
    names["bushatch"] = "Bus Hatch";
    names["dinerhatch"] = "Diner Hatch";
    names["busladder"] = "Bus Ladder";
    names["sq_common"] = "Side Quest";
    names["springpad_zm"] = "Trample Steam";
    names["slipgun_zm"] = "Sliquifier";
    names["keys_zm"] = "Bunker Key";
    names["ekeys_zm"] = "Elevator Key";
    names["subwoofer_zm"] = "Subwoofer";
    names["headchopper_zm"] = "Head Chopper";
    names["booze"] = "Booze";
    names["candy"] = "Candy";
    names["chalk"] = "Chalk";
    names["buried_sq_oillamp"] = "Oil Lamp";
    names["buried_sq_bt_m_tower"] = "Tower M";
    names["buried_sq_bt_r_tower"] = "Tower R";
    names["buried_sq_tpo_switch"] = "Time Switch";
    names["buried_sq_ghost_lamp"] = "Ghost Lamp";

    if ( isdefined( names[name] ) )
        return names[name];

    return name;
}
