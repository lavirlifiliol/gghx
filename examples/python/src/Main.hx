package;

import gghx.Queue;
import gghx.GGHX.PlayerHandle;
import gghx.backend.Session;
import gghx.GGHX.GGError;
import python.NativeIterable;
import haxe.io.Int32Array;
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

@:pythonImport("socket", "socket")
extern class Socket {
    public extern function new(a: Dynamic, b: Dynamic);
    public extern function sendto(data: python.Bytes, addr: Address): Dynamic;
    public extern function recvfrom(bufsize: Int): Tuple2<python.Bytes, Address>;
    public extern function bind(a: Address): Dynamic;
    public extern function setblocking(a: Bool): Dynamic;
}

@:pythonImport("pygame")
extern class Pygame {
    static public extern function init(): Dynamic;
}

@:pythonImport("pygame", "time")
extern class PygameTime {
    static public extern function Clock(): Dynamic;
}

@:pythonImport("pygame", "display")
extern class PygameDisp {
    static public extern function set_mode(a: Tuple2<Int, Int>): Dynamic;
    static public extern function flip(): Dynamic;
}

@:pythonImport("pygame", "event")
extern class PygameEvent {
    static public extern function get(): NativeIterable<Dynamic>;
}

@:pythonImport("pygame", "key")
extern class PygameKey {
    static public extern function get_pressed(): Dynamic;
}

class PyNetworking implements Networking<Address> {
    var sock: Socket = null;
    public function new(port: Int) {
        sock = new Socket(python.lib.Socket.AF_INET, python.lib.Socket.SOCK_DGRAM);
        sock.bind(Tuple2.make("127.0.0.1", port));
        sock.setblocking(false);
    }
	public function handleEqual(one:Address, two:Address):Bool {
		return one == two;
	}

	public function newRemote(ip:String, port:Int):Address {
        return Tuple2.make(ip, port);
	}

	public function send(data:Bytes, to:Address) {
        var d = new Bytearray();
        for (b in UInt8Array.fromBytes(data)) {
            d.append(b);
        }
        var bytes = Syntax.call(python.Bytes, [d]);
        sock.sendto(bytes, to);
    }

	public function recv():Null<{data:Bytes, from:Address}> {
        try {
            var res = sock.recvfrom(4096);
            var pb = res._1;
            
            return {data:Bytes.ofHex(Syntax.callField(pb,"hex")), from:res._2};
        } catch(e) {
            // TODO catch exact error
            return null;
        }
	}

	public function poll(handles:Array<Address>, timeout:Int):Null<Int> {
		throw new haxe.exceptions.NotImplementedException();
	}
}

class PyCallbacks implements Callbacks {
    var main: Main;
    public function new(main: Main) {
        this.main = main;
    }

	public function beginGame() {
        trace('ev begin');
    }

	public function saveGameState(frame:Int):{checksum:Int, state:Bytes} {
        var state = Bytes.alloc(4);
        state.setInt32(0, main.state);
        return {checksum: main.state, state: state};
	}

	public function loadGameState(state:Bytes) {
        trace('load', state.toHex());
        main.state = Int32Array.fromBytes(state).get(0);
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
    public var state: Int;
    public var otherIdx = 0;
    var player: PlayerHandle;
    public var sess: Session;
    public function new() {
        this.state = 0;
    }
    function play() {
        var p1 = Sys.args().length == 1;
        sess = startSession(
            new PyCallbacks(this),
            "test",
            2,
            new PyNetworking(if (p1) 8080 else 8081),
            1
        );
        if (p1) {
            player = sess.addPlayer({num: 1, type: LOCAL});
            otherIdx = 1;
            sess.addPlayer({num: 2, type: REMOTE("127.0.0.1", 8081)});
        } else {
            player = sess.addPlayer({num: 2, type: LOCAL});
            otherIdx = 0;
            sess.addPlayer({num: 1, type: REMOTE("127.0.0.1", 8080)});
        }
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
        }
    }
    function drawFrame(s: Dynamic) {
        s.fill(Syntax.callField(Pygame, 'Color', state, state, state));
        if (this.state == -1) {
            s.fill('red');
        }
    }
    public function stepSim(inp: Vector<Null<Bytes>>) {
        if (inp.get(0) == null) {
            this.state = -1;
        }
        if (inp.get(0).get(0) > 0 ) {
            if (this.state < 255) {
                trace('up $state');
                this.state++;
            }
        } else {
            if (this.state > 4 && this.state < 256) {
                trace('down $state');
                this.state -= 4;
            }
        }

        sess.incrementFrame();
    }
    function runFrame() {
        var input: Bytes = Bytes.alloc(1);
        if (Syntax.arrayAccess(PygameKey.get_pressed(), 119)) {
            input.set(0, 1);
        } else {
            input.set(0, 0);
        }
        try {
            sess.addLocalInput(player, input);
            var inputs = sess.syncInput();
            stepSim(inputs);
        } catch (e: gghx.GGError) {
            //trace('!!!!!!!!!!!!!!!!!!!!', e.error);
        } 
    }
    static public function main() {
        new Main().play();
    }
}