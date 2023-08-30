package gghx;

import gghx.backend.P2P;
import haxe.io.Bytes;
import gghx.backend.Session;

enum NetworkSide {
	LOCAL;
	REMOTE(ip:String, port:Int);
}

class GGError extends haxe.Exception {
	public var error:Error;

	public function new(error:Error) {
		super(this.error.message());
		this.error = error;
	}
}

enum abstract Error(Int) { // rather than return error codes, most functions will throw GGError
	var OK = 0;
	var SUCCESS = 0;
	var GENERAL_FAILURE = -1;
	var INVALID_SESSION = 1;
	var INVALID_PLAYER_HANDLE = 2;
	var PLAYER_OUT_OF_RANGE = 3;
	var PREDICTION_THRESHOLD = 4;
	var UNSUPPORTED = 5;
	var NOT_SYNCHRONIZED = 6;
	var IN_ROLLBACK = 7;
	var INPUT_DROPPED = 8;
	var PLAYER_DISCONNECTED = 9;
	var TOO_MANY_SPECTATORS = 10;
	var INVALID_REQUEST = 11;

	public function message():String {
		return Std.string(this);
	}
}

abstract PlayerHandle(Int) from Int to Int {}

enum Event {
	CONNECTED_TO_PEER(player:PlayerHandle);
	SYNCHRONIZING_WITH_PEER(player:PlayerHandle, count:Int, total:Int);
	SYNCHRONIZED_WITH_PEER(player:PlayerHandle);
	RUNNING;
	DISCONNECTED_FROM_PEER(player:PlayerHandle);
	TIMESYNC(frames_ahead:Int);
	CONNECTION_INTERRUPTED(player:PlayerHandle, disconnect_timeout:Int);
	CONNECTION_RESUMED(player:PlayerHandle);
}

interface Callbacks {
	public function beginGame():Void;
	public function saveGameState(frame:Int):{checksum:Int, state:Bytes};
	public function loadGameState(state:Bytes):Void;
	public function logGameState(filename:String, game:Bytes):Void;
	public function advanceFrame():Void;
	public function onEvent(ev:Event):Void;
}

@:structInit class Player {
	public var num:Int;
	public var type:NetworkSide;
	// todo spectators
}

@:structInit class NetworkStats {
	public var network:{
		send_queue_len:Int,
		recv_queue_len:Int,
		ping:Int,
		kbps_sent:Int,
	}
	public var timesync:{
		local_frames_behind:Int,
		remote_frames_behind:Int,
	}
}

@:structInit class NWStats {
	var sent:Int;
	var recv:Int;
	var kbps:Int;
}

// one Networking instance is one "socket"
interface Networking<Handle> {
	var send_latency:Int; // artificial latency in ms, artificial ping (rtt) = 2*latency
	var oop_percent:Int; // artificial packet loss in percent
	function handleEqual(one:Handle, two:Handle):Bool;
	function newRemote(ip:String, port:Int):Handle;
	function send(data:Bytes, to:Handle):Void;
	function recv():Null<{data:Bytes, from:Handle}>;
	function poll(handles:Array<Handle>, timeout:Int):Null<Int>; // todo figure out, not used in ggpo itself
}

// main.cpp
function mod(a:Int, b:Int) {
	var res = a % b;
	if (res < 0) {
		return res + b;
	}
	return res;
}

function startSession<Handle>(cb:Callbacks, game_name:String, num_players:Int, networking:Networking<Handle>, input_size:Int):Session {
	return new P2P(cb, game_name, num_players, input_size, networking);
}

// todo spectating
