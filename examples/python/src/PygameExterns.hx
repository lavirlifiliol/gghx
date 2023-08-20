package;

import python.Exceptions.BlockingIOError;
import haxe.io.UInt16Array;
import gghx.GGHX.PlayerHandle;
import gghx.backend.Session;
import gghx.GGHX.GGError;
import python.NativeIterable;
import gghx.GGHX.Event;
import gghx.GGHX.Callbacks;
import gghx.GGHX.startSession;
import python.Syntax;
import python.Bytearray;
import haxe.io.UInt8Array;
import haxe.ds.Vector;
import python.Tuple.Tuple2;
import haxe.io.Bytes;
import gghx.GGHX.Networking;
import python.lib.socket.Address;

@:pythonImport("pygame")
extern class Pygame {
	static public extern function init():Dynamic;
}

@:pythonImport("pygame", "time")
extern class PygameTime {
	static public extern function Clock():Dynamic;
}

@:pythonImport("pygame", "display")
extern class PygameDisp {
	static public extern function set_mode(a:Tuple2<Int, Int>):Dynamic;
	static public extern function flip():Dynamic;
	static public extern function set_caption(c:String):Dynamic;
}

@:pythonImport("pygame", "event")
extern class PygameEvent {
	static public extern function get():NativeIterable<Dynamic>;
}

@:pythonImport("pygame", "draw")
extern class PygameDraw {
	static public extern function circle(s:Dynamic, c:Dynamic, center:Tuple2<Int, Int>, radius:Int):NativeIterable<Dynamic>;
}

@:pythonImport("pygame", "key")
extern class PygameKey {
	static public extern function get_pressed():Dynamic;
}
