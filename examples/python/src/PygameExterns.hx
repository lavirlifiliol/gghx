package;

import python.NativeIterable;
import python.Tuple.Tuple2;

@:pythonImport("pygame")
extern class Pygame {
	static extern var QUIT: Int;
	static extern var K_w: Int;
	static public extern function init():Dynamic;
}

@:pythonImport("pygame", "Color")
extern class PygameColor {
	extern function new(r: Int, g: Int, b: Int);
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

extern class PGEvent {
	extern var type: Int;
}

@:pythonImport("pygame", "event")
extern class PygameEvent {
	static public extern function get():NativeIterable<PGEvent>;
}

@:pythonImport("pygame", "draw")
extern class PygameDraw {
	static public extern function circle(s:Dynamic, c:Dynamic, center:Tuple2<Int, Int>, radius:Int):NativeIterable<Dynamic>;
}

@:pythonImport("pygame", "key")
extern class PygameKey {
	static public extern function get_pressed():Dynamic;
}
