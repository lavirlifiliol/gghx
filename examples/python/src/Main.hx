package;

import python.Tuple.Tuple4;
import python.Tuple.Tuple3;
import haxe.io.UInt16Array;
import gghx.GGHX.PlayerHandle;
import gghx.backend.Session;
import gghx.GGHX.GGError;
import gghx.GGHX.Event;
import gghx.GGHX.Callbacks;
import gghx.GGHX.startSession;
import python.Syntax;
import haxe.ds.Vector;
import python.Tuple.Tuple2;
import haxe.io.Bytes;
import PyNetworking;
import PygameExterns;

class PyCallbacks implements Callbacks {
	var main:Main;

	public function new(main:Main) {
		this.main = main;
	}

	public function beginGame() {
		trace('ev begin');
	}

	public function saveGameState(frame:Int):{checksum:Int, state:Bytes} {
		var state = Bytes.alloc(4);
		state.setUInt16(0, main.state[0]);
		state.setUInt16(2, main.state[1]);
		return {checksum: main.state[0], state: state};
	}

	public function loadGameState(state:Bytes) {
		main.state = UInt16Array.fromBytes(state);
	}

	public function logGameState(filename:String, game:Bytes) {
		throw 'not used';
	}

	public function advanceFrame() {
		trace('used new callback');
		main.stepSim(main.sess.syncInput());
	}

	public function onEvent(ev:Event) {
		trace(ev);
	}
}

class Main {
	public var state:UInt16Array;
	public var otherIdx = 0;

	var player:PlayerHandle;

	public var sess:Session;

	public function new() {
		this.state = new UInt16Array(2);
	}

	function usage() {
		Sys.stderr().writeString('Usage: ./${Sys.programPath} <player number> <local port> <remote ip> <remote port>\n');
		Sys.exit(0);
	}

	function parse_args():Tuple4<Int, Int, String, Int> {
		var args = Sys.args();
		if (args.length != 4) {
			usage();
		}
		var player_number = Std.parseInt(args[0]);
		if (player_number != 1 && player_number != 2) {
			Sys.stderr().writeString("player number must be one or two");
			usage();
		}
		var local_port = Std.parseInt(args[1]);
		var remote_ip = args[2];
		var remote_port = Std.parseInt(args[3]);
		return Tuple4.make(player_number, local_port, remote_ip, remote_port);
	}

	function play() {
		var args = parse_args();
		sess = startSession(new PyCallbacks(this), "example", 2, new PyNetworking(args._2), 1);
		player = sess.addPlayer({num: args._1, type: LOCAL});
		sess.addPlayer({num: 3 - args._1, type: REMOTE(args._3, args._4)});
		var running = true;
		Pygame.init();
		var clock = PygameTime.Clock();
		var s = PygameDisp.set_mode(Tuple2.make(480, 480));
		while (running) {
			for (ev in PygameEvent.get().toHaxeIterable()) {
				if (Syntax.field(ev, 'type') == Syntax.field(Pygame, 'QUIT')) {
					running = false;
				}
			}

			sess.doPoll(1); // the timeout is just ignored lul
			runFrame();

			drawFrame(s);
			PygameDisp.flip();
			clock.tick(60);
			PygameDisp.set_caption(Std.string(clock.get_fps()));
		}
	}

	function drawFrame(s:Dynamic) {
		s.fill("blue");
		for (i in 0...2) {
			var shere = state.get(i);
			var color:Dynamic;
			if (shere > 255) { // input was null
				color = "purple";
			} else {
				color = Syntax.callField(Pygame, "Color", shere, shere, shere);
			}
			PygameDraw.circle(s, color, Tuple2.make(100 + 200 * i, shere + 100), 50);
		}
	}

	public function stepSim(inp:Vector<Null<Bytes>>) {
		trace('**got inputs', inp.map((e) -> e.toHex()));
		for (i in 0...2) {
			if (inp.get(i) == null) {
				this.state[i] = 512;
			} else if (inp.get(i).get(0) > 0) {
				if (this.state[i] < 254) {
					this.state[i] += 2;
				}
			} else {
				if (this.state[i] > 5 && this.state[i] < 256) {
					this.state[i] -= 4;
				}
			}
		}

		sess.incrementFrame();
	}

	function runFrame() {
		var input:Bytes = Bytes.alloc(1);
		if (Syntax.arrayAccess(PygameKey.get_pressed(), 119)) {
			input.set(0, 1);
		} else {
			input.set(0, 0);
		}
		try {
			sess.addLocalInput(player, input);
			var inputs = sess.syncInput();
			stepSim(inputs);
		} catch (e:gghx.GGError) {
			trace('@@', e.error);
		}
	}

	static public function main() {
		new Main().play();
	}
}
