#include "..\script_component.hpp"
/*
 * Author: Jonpas
 * Sets up signal jamming based on active jammers.
 * Call from init.sqf
 *
 * Modify cases below depending on your amount of jammers and wanted effects.
 * Jamming effect will be applied on top of ACRE's signal calculation, taking terrain, distance etc. into account.
 * Refer to https://acre2.idi-systems.com/wiki/frameworks/custom-signal-processing for details.
 *
 * Arguments:
 * 0: Jammer objects <ARRAY>
 * 1: Signal degradation parameters <ARRAY> (default: [[0.0, ...], [0, ...]])
 *   0: Strength reduction (0.0 to 1.0, higher reduction degrades signal) <NUMBER>
 *   1: Decibel reduction (0 to 110 reduction is typically heard, higher reduction is not) <NUMBER>
 *
 * Return Value:
 * None
 *
 * Examples:
 * [[jammer1, jammer2]] call TAC_Scripts_fnc_jam
 * [[jammer1, jammer2], [[0.1, 0.5], [20, 60]]] call TAC_Scripts_fnc_jam
 */

params [["_jammers", [], [[]]], ["_degradation", [], [[]]]];
private _countJammers = count _jammers;
_degradation params [
    ["_strengthReduction", [], [0], [0, _countJammers]],
    ["_decibelReduction", [], [0], [0, _countJammers]]
];

// Make global for PFH/EH use
GVAR(activeJammers) = _jammers;

// Remove jammer objects on destruction
private _jammerClasses = _jammers arrayIntersect _jammers; // remove duplicates
{
    [_x, "Killed", { // executed locally
        params ["_object"];
        GVAR(activeJammers) = GVAR(activeJammers) - [_object];
        publicVariable QGVAR(activeJammers);
    }] call CBA_fnc_addClassEventHandler;
} forEach _jammerClasses;

// Register custom signal function
[{
    // ACRE signal processing
    private _coreSignal = _this call ACREFUNC(sys_signal,getSignalCore);
    _coreSignal params ["_f", "_mW", "_receiverClass", "_transmitterClass"];

    // Modify if any active jammers
    private _activeJammers = count GVAR(activeJammers);
    if (_activeJammers > 0) then {
        _maxSignal = _maxSignal - (_strengthReduction select (_activeJammers - 1));
        _Px = _Px - (_decibelReduction select (_activeJammers - 1));
    };

    // return final values
    [_Px, _maxSignal]
}] call ACREFUNC(api,setCustomSignalFunc);
