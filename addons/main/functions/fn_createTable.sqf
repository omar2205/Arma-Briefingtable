/*
 * Author: Seb, with optimisations by Leopard20
 * 
 * This function creates a minified representation of a marker area on a table, both given as arguments. It
 *
 * Arguments:
 * 0: Table on which to create the minified representaiton. If a minified representation already exists, it will be cleared before starting. <OBJECT>
 * 1: AREA marker string representation (i.e "marker_0") <STRING>
 * 2: Optional  <NUMBER> (default: 20) - Terrain resolution (x*y resolution of terrain cubes). Setting this too high will be VERY laggy.
 * 4: Optional  <NUMBER> (default: 1) - Scale multiplier. 3 = map is 3x the size of the table. Useful for spanning multiple tables.
 * 4: Optional <BOOL> (default: true). Use terrain. If false then the map will be entirely flat. Just like the earth ;)
 * 5: Optional <BOOL> (default: true) - Create environment sounds tirgger:
 *                                      Create a trigger that disables envionmental sounds when the current unit comes near, and puts it back to its original state when the player leaves.
 *                                      This is because all the bushes that appear on the table will still play cricket sounds, buildings will play air conditoner hums etc.
 * Return Value:
 * NONE
 *
 * Example:
 *   TABLE OBJECT INIT:
 *      [this, "marker_0", 20, 1, true, true] call sebs_briefing_table_fnc_createTable;
 *
 *   SCRIPT CALL (Multiplayer & Join in progress COMPATIBLE): 
 *      [table, "marker_0", 20, 1, true, true] remoteExec ["sebs_briefing_table_fnc_createTable", 0, table];
 *
 *  NEVER EVER EVER REMOTEXEC FROM OBJECT INIT!
 *
 * Public: [No]
 */
if !(hasInterface) exitWith {};
params [
    "_table",
    "_marker",
    ["_terrainResolution", 20],
    ["_scaleMultiplier", 1],
    ["_useTerrainHeight", true],
    ["_createTrigger", true]
];

if (isNil "_table" || {isNull _table || {_marker == "" || {_temp = createMarkerLocal [_marker, [0,0,0]]; deleteMarker _temp; _temp != ""}}}) exitWith {};

_table enableSimulation false;

/* DEBUG
sebs_briefing_table_fnc_clearTable = {
    params ["_table"];
    private _tableObjects = _table getVariable ["sebs_briefing_table_tableObjects", []];
    {deleteVehicle _x} forEach _tableObjects;
    _table setVariable ["sebs_briefing_table_tableObjects", []];
};
*/

_table call sebs_briefing_table_fnc_clearTable;
_tableObjects = [];

private _bbr = 2 boundingBoxReal _table;
private _p1 = _bbr#0;
private _p2 = _bbr#1;
private _tableWidth = abs ((_p2#0) - (_p1#0));
private _tableLength = abs ((_p2#1) - (_p1#1));
private _tableHeight = abs ((_p2#2) - (_p1#2));

private _markerDir = markerDir _marker;
private _markerPos = getMarkerPos _marker;
private _markerSize = getMarkerSize _marker;
private _maxSize = _markerSize#0 max _markerSize#1; // longest edge of marker
_marker setMarkerSize [_maxSize, _maxSize]; // Marker must be square

private _tableDir = getDir _table;
private _tableSize = ((_tableWidth min _tableLength) / 2) * _scaleMultiplier * 0.9;    // Gets shortest edge of table. Why do I have to divide by 2???????????????
private _scale = _tableSize/_maxSize; // fit longest edge of marker on table

private _squareDist = sqrt (2*_maxSize*_maxSize);
private _objects = (nearestTerrainObjects [_markerPos, [],  _squareDist, false, true]) inAreaArray _marker; // Terrian objects
_objects append ((_markerPos nearObjects ["Static", _squareDist]) inAreaArray _marker); // Will pick up custom placed objects, but contains duplicates from above
_objects = _objects arrayIntersect _objects; // removes duplicates

private _dummy = "Land_HelipadEmpty_F" createVehicleLocal _markerPos;
_markerPos set [2, (0 max getTerrainHeightASL _markerPos) + 1];
_dummy enableSimulation false;
_dummy setPosASL _markerPos;
_dummy setDir _markerDir;

private _zOffset = if (_useTerrainHeight) then {
    private _minHeight = 100000;
    {
        _minHeight = _minHeight min (getPosASL _x)#2;
    } forEach _objects;
    (getPosASL _dummy#2) - _minHeight
} else {
    0
};
private _vectorDiff = [0, 0, _tableHeight/2 + (_zOffset * _scale) + 0.05]; // neatly fit all the stuff on the top of the table

{
    private _model = (getModelInfo _x)#1;
    if (_model != "" && {(((boundingBoxReal  _x)#2) * _scale * getObjectScale _x ) > 0.005}) then {
        isNil {
            private _relCentre = _dummy worldToModel (ASLtoAGL getPosWorld _x);
            private _relVectDir = _dummy vectorWorldToModel (vectorDir _x);
            private _relVectUp = _dummy vectorWorldToModel (vectorUp _x);
            private _tableObj = createSimpleObject [_model, [0, 0, 0], true];
            private _scaledPos = _relCentre vectorMultiply _scale;
            private _newPos = if (_useTerrainHeight) then {(_table modelToWorldWorld (_scaledPos vectorAdd _vectorDiff))}
            else
            {_table modelToWorldWorld (_scaledPos vectorAdd _vectorDiff)}; 
            _tableObj setPosWorld _newPos;
            _tableObj setVectorDirAndUp [_table vectorModelToWorld _relVectDir, _table vectorModelToWorld _relVectUp];
            _tableObj setObjectScale _scale * getObjectScale _x;
            _tableObjects pushBack _tableObj;
        };
    };
} forEach _objects;

private _step = 2/_terrainResolution;
for "_posX" from -1 to 1 step _step do {
    for "_posY" from -1 to 1 step _step do {
        isNil {
            private _tablePos = [_posX*_tableSize, _posY*_tableSize, 0];
            private _worldPos = (_dummy modelToWorld (_tablePos vectorMultiply 1/_scale)); // divide by scale to scale back up
            private _road = roadAt (_worldPos select [0,2]);
            private _texture = if (!isNull _road) then {getRoadInfo _road select 3} else {surfaceTexture _worldPos};
            private _normal = vectorUp _table;
            private _cubeSize = _step * _tableSize;
            if (_useTerrainHeight) then {
                private _normals = [];
                private _averageStep = _step/2;
                // Sample normals over cube area:
                for "_normalX" from -2*_averageStep to 2*_averageStep step _averageStep do {
                    for "_normalY" from -2*_averageStep to 2*_averageStep step _averageStep do {
                        private _checkPos = _worldPos vectorAdd [_normalX, _normalY];
                        _normals pushBack (surfaceNormal _checkPos);
                    };
                };
                {
                    _normal = _normal vectorAdd _x;
                } forEach _normals;
                // You don't need to average the normals for the normal to look good.
                // _normal = _normal vectorMultiply 1/count _normals;
                // I have no idea why.
                _normal = [_normal, _tableDir -_markerDir, 2] call BIS_fnc_rotateVector3D; // Not sure why I have to do this.
                private _cos = abs (vectorUp _table vectorCos _normal);
                private _dynamicSize = 1.1/_cos; // scale cubes based on angle
                _cubeSize = _cubeSize * _dynamicSize; // 
                _tablePos set [2, -(_worldPos#2 * _scale + _cubeSize/(2*_cos) + 0.5)]; // Z flip from worldpos. wtf?.
            } else {
                _tablePos set [2, -0.5 - _cubeSize/2]
            };
            private _groundObject = createSimpleObject ["Land_VR_Shape_01_cube_1m_F", [0,0,0], true];
            _groundObject enableSimulation false;
            _groundObject setPosASL (_table modelToWorldWorld (_tablePos vectorAdd _vectorDiff));
            _groundObject setVectorDirAndUp [vectorDir _table, vectorUp _table];
            _groundObject setVectorUp _normal;
            for "_selection" from 0 to 6 do {
                _groundObject setObjectMaterial [_selection, "\a3\data_f\default.rvmat"];
                _groundObject setObjectTexture [_selection, _texture];
            };
            _groundObject setObjectScale _cubeSize;
            _tableObjects pushBack _groundObject;
        };
    };
};

_table setVariable ["sebs_briefing_table_tableObjects", _tableObjects];
deleteVehicle _dummy;

if (_createTrigger) then {
    _trg = createTrigger ["EmptyDetector", getPos _table, false];
    _trg setTriggerArea [_tableSize + 15, _tableSize + 15, getDir _table, true];
    if (isNil {sebs_briefing_table_originalEnv}) then {
        sebs_briefing_table_originalEnv = environmentEnabled 
    };
    _trg setTriggerActivation ["NONE", "PRESENT", true];
    _trg setTriggerStatements [
        "player inArea thisTrigger",
        "enableEnvironment false",
        "enableEnvironment sebs_briefing_table_originalEnv"
        ];
    _trg setTriggerInterval 1;
    _tableObjects pushBack _trg;
};

if !(_table getVariable ["seb_briefing_table_hasDeletedEH", false]) then {
    _table addEventHandler ["Deleted", {
        _table call sebs_briefing_table_fnc_clearTable;
    }];
    _table setVariable ["seb_briefing_table_hasDeletedEH", true];
};