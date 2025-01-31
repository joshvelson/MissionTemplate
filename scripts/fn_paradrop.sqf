#include "..\script_component.hpp"
/*
 * Author: Josh Vee, Jonpas, Veteran29
 * An all-purpose paradrop function.
 * Call from vehicle waypoint with (isServer) check.
 * 
 * The vehicle will set move waypoints on two points of a circle surrounding 
 * a marker and initiate the drop at the fist waypoint.  Can be called multiple
 * times for different groups loaded on the same vehicle, but optimally
 * used either for single group on helicopter or multiple groups on planes.
 *
 * It inserts waypoints in front of the one in which it is called
 * therefore it can be used with multiple waypoints without issue.
 *
 * Known behavior: 
 * 1. Locked planes/helicopters result in no drops.
 * 2. Planes/helicopters in combatMode "COMBAT" have altitude overrides.
 * 3. Drop distribution ultimately depends on AI pathing, and AI is stupid.
 * 4. Function is designed to be called synchronously with craft reaching the
 * WP from which it is called; if it is held up, then the drop WPs will not
 * reflect the current azimuth.  If synchronizing WPs, recommend you sync WPs
 * BEFORE the one that calls this function to avoid weird behavior, especially
 * if the drop marker is close by.
 *
 * Optional Arguments: Drop Mode
 * For convenience, this function has the following pre-set modes for drops:
 * 0: Modern combat drop, 150m, parachutes deploy at 140m.
 * 1: Dangerous combat drop, 105m, parachutes deploy at 80m. 
 * 2: Training drop, 250m, parachutes deploy at 140m.
 * 3: HALO drop, 4.5km, parachutes deploy at 900m.
 * 4: Civilian drop, 3km, parachutes deploy at 900m. 
 * For custom drops, drop altitude, drop zone length, deployment altitude can be set
 * by providing an array of those values, in meters.
 * 
 * Note that for HALO or Civilian drops, most maps are not big enough to get to
 * sufficient altitude and it is recommended to have several waypoints steadily
 * increasing flyInHeight before using it.  Also, don't try with helicopters.
 *
 * Optional Arguments: Reset Height
 * For drop purposes flyInHeight is set during the run.  If the transport is to be
 * otherwise used after the run, set this to <true> in order to resume normal behavior
 *
 * Optional Arguments: Disable Waypoint 2
 * Occasionally, AI behavior can be wonky especially when drop WPs are around airports.
 * This will cause them to veer off from their drop direction and attempt to land. 
 * Disabling WP 2 stops this behavior from occurring on the second waypoint.
 * If it occurs on the first, I recommend changing the DZ area, the drop length,
 * or the approach direction. 
 *
 * Arguments
 * 0: Pilot Group <GROUP>
 * 1: Drop Groups <ARRAY>
 * 2: Drop Target <MARKER>
 * 3: Drop Mode <ARRAY> or <NUMBER> (default: 0)
 * 4: Reset Height <BOOL> (default: false) 
 * 5: Disable Waypoint 2 <BOOL> (default: false)
 *
 * Return Value:
 * None
 *
 * Examples:
 * [pilot_group, [airborne_1], "drop_marker"] call TAC_Scripts_fnc_paradrop;
 * [pilot_group, [airborne_1,airborne_2], "drop_marker"] call TAC_Scripts_fnc_paradrop;
 * [pilot_group, [airborne_1], "drop_marker", 1] call TAC_Scripts_fnc_paradrop;
 * [pilot_group, [airborne_1], "drop_marker", 0, false, false] call TAC_Scripts_fnc_paradrop;
 * [pilot_group, [airborne_1], "drop_marker", [200,1000,150]] call TAC_Scripts_fnc_paradrop;
 */

#define DROP_MODES [[150, 1000, 140], [105, 1000, 80], [250, 1000, 140] ,[4500, 1000, 900], [3000, 1000, 900]]

params ["_pilotGroup", "_dropGroups", "_loc", ["_dropMode", 0], ["_resetHeight", false], ["_disableWP2", false]];

if (_loc isEqualTo "") exitWith {ERROR("Paradrop given invalid marker!")};

// make sure you delete these 2 lines later below in the script (and this comment too)! I just moved them here as early exit is better, and we have a use for it early here now
private _vehicle = vehicle (leader _pilotGroup);
if (isNull _vehicle) exitWith {ERROR("Paradrop pilot group not in vehicle!")};

private _origDropGroupsCount = count _dropGroups;
_dropGroups = _dropGroups select {_vehicle != vehicle (leader _x)};
if (count _dropGroups < _origDropGroupsCount) then {
    WARNING_1("Paradrop %1 drop group(s) skipped because they are not in the same vehicle as pilot group!",_origDropGroupsCount - count _dropGroup)
};
private _dropData = [];
// first process dropMode
if (_dropMode isEqualType 0) then {
    if (_dropMode < 0 || {_dropMode > 4}) then {
        ERROR_1("Paradrop mode %1 invalid - defaulting to 0!",_dropMode);
        _dropMode = 0;
    };
    _dropData = DROP_MODES select _dropMode;
} else {
    if (_dropMode isEqualType [] && {count _dropMode == 3}) then {
        _dropData = _dropMode;
    };
};

_dropData params ["_dropHeight", "_dropLength", "_chuteHeight"];

private _vehicle = vehicle (leader _pilotGroup);
if (isNull _vehicle) exitWith {ERROR("Paradrop pilot group not in vehicle!")};

private _origHeight = (getPosATL _vehicle) select 2;
_vehicle flyInHeight _dropHeight; // set forced flying height
if (_resetHeight) then {
    [{
        params ["_vehicle"];
        (fullCrew [_vehicle,"cargo"]) isEqualTo []
    }, {
        params ["_vehicle", "_origHeight"];
        _vehicle flyInHeight _origHeight;
    }, [_vehicle, _origHeight]] call CBA_fnc_waitUntilAndExecute;
};

// Use addWayPoint for the group piloting the vehicle to add the drop waypoints
private _dropRunOrigin = getPosATL _vehicle;

// Obtain a random location within drop target
// Between current position and drop target, find angle
private _dropTarget = [_loc, true] call CBA_fnc_randPosArea;

if (_dropTarget isEqualTo []) exitWith {ERROR_1("Paradrop target for marker '%1' not found!",_loc)};

private _fnc_dzLocs = {
    params ["_dropTarget", "_dropRunOrigin", "_dropLength"];
    // getDir gives the azimuth, which differs in convention from trig
    // in two ways: (1) azimuth has zero origin at North and
    // (2) advances clockwise rather than counterclockwise
    // To convert, use a conditional function:    
    private _azimuth = _dropRunOrigin getDir _dropTarget;
    private _theta = switch (floor _azimuth/90) do {
        case 0: {90-_azimuth;};
        default {450-_azimuth;};
    };
    // For a known drop point and known radius with trig angle _theta,
    // and radius r given by _dropLength/2,
    // then coordinates in the xy-plane relative to _dropTarget are:
    // +/- r*cos _theta for x (Northing) and +/- r*sin _theta for x (Easting)

    private _yDiff = (sin _theta) * _dropLength/2;
    private _xDiff = (cos _theta) * _dropLength/2;
    // set all coordinates based on DZ points in xy-plane; z coord does not matter
    // double lengths on second DZ coordinate to ensure straight line flight
    _dropTarget params ["_dropTargetX", "_dropTargetY"];
    [
        [_dropTargetX + _xDiff, _dropTargetY + _yDiff, _dropHeight],
        [_dropTargetX - _xDiff, _dropTargetY - _yDiff, _dropHeight]
    ];
};

private _dropZoneLocs = [_dropTarget, _dropRunOrigin, _dropLength] call _fnc_dzLocs;
private _minDistance = _dropRunOrigin distance (_dropZoneLocs select 1);

// Error handling for when calling waypoint is within distance _dropLength
if (_minDistance < _dropLength) then {
    WARNING_1("Paradrop vehicle '%1' too close to DZ!",_vehicle);
}; 

private _dp = _pilotGroup addWaypoint [_dropZoneLocs select 1, -1,currentWaypoint _pilotGroup + 1, ""];
if (!_disableWP2) then {
    private _de = _pilotGroup addWaypoint [_dropZoneLocs select 0, -1, currentWaypoint _pilotGroup + 2, ""];
};

// Add the paradrop operation. To store variables, adds info to vehicle name space that can be referenced later
_vehicle setVariable [QGVAR(paradropGroups), _dropGroups];
_vehicle setVariable [QGVAR(paradropChuteHeight), _chuteHeight];

// Note - moveOut instantly pushes them out of vehicle without playing animation
// this emulates a static line drop dropping very quickly, but needs to be spaced
// it also means that you need to spawn in a parachute otherwise they freefall to their deaths
// currently this is set for a drop interval of 1/2 second, allowing AI to keep cohesion
// but not collide into each other

// Other notes:
// Vehicles are unassigned and allowGetIn is set to false to prevent the paratroopers from
// running back to a landed plane or helicopter to get back in again.
// Velocity adjustment occurs to differentiate helicopters from planes to alter jump intervals

private _fnc_dropParas = {
    private _vehicle = vehicle this; 
    private _chuteHeight = _vehicle getVariable [QGVAR(paradropChuteHeight), []];
    private _paraGroups = _vehicle getVariable [QGVAR(paradropGroups), []];
    // Waypoint statements execute globally, ignore any groups not local and exit if none local
    _paraGroups = _paraGroups select {local (leader _x)};
    if (_paraGroups isEqualTo []) exitWith {};

    // Deal with units from here on
    private _dropUnits = _paraGroups apply {units _x};
    _dropUnits = flatten _dropUnits;

    private _chuteHeight = _vehicle getVariable [QGVAR(paradropChuteHeight), []];
    private _jumpFreq = [0.5, 0.7] select (speed _vehicle < 250);

    {
        (units _x) allowGetIn false;

        private _jumpDelay = _forEachIndex * _jumpFreq;
        [{
            params ["_man"];

            unassignVehicle _man;
            moveOut _man;

            [{
                params ["_man", "_chuteHeight", "_vehicle"];
                (getPosATL _man) select 2 <= _chuteHeight && {_man distance _vehicle >= 15}
            }, {
                params ["_man", "_chuteHeight"];

                private _manPos = getPosATL _man;
                private _chute = createVehicle ["Steerable_Parachute_F", _manPos, [], 0, "FLY"];

                _man moveInDriver _chute;
            }, _this] call CBA_fnc_waitUntilAndExecute;
        }, [_x, _chuteHeight, _vehicle], _jumpDelay] call CBA_fnc_waitAndExecute;
    } forEach _dropUnits;
};

_dp setWaypointStatements ["true", toString _fnc_dropParas];

