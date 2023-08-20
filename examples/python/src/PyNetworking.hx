package;

import python.Exceptions.BlockingIOError;
import python.Syntax;
import python.Bytearray;
import haxe.io.UInt8Array;
import python.Tuple.Tuple2;
import haxe.io.Bytes;
import gghx.GGHX.Networking;
import python.lib.socket.Address;

@:pythonImport("socket", "error")
extern class SocketError {
	public extern var err:Int;
}

@:pythonImport("socket", "socket")
extern class Socket {
	public extern function new(a:Dynamic, b:Dynamic);
	public extern function sendto(data:python.Bytes, addr:Address):Dynamic;
	public extern function recvfrom(bufsize:Int):Tuple2<python.Bytes, Address>;
	public extern function bind(a:Address):Dynamic;
	public extern function setblocking(a:Bool):Dynamic;
}

class PyNetworking implements Networking<Address> {
	public var send_latency = 50;
	public var oop_percent = 0;

	var sock:Socket = null;

	public function new(port:Int) {
		sock = new Socket(python.lib.Socket.AF_INET, python.lib.Socket.SOCK_DGRAM);
		sock.bind(Tuple2.make("0.0.0.0", port));
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
			// todo cleaner conversion
			return {data: Bytes.ofHex(Syntax.callField(pb, "hex")), from: res._2};
		} catch (e:BlockingIOError) {
			return null;
		} catch (e:SocketError) {
			return null;
		}
	}

	public function poll(handles:Array<Address>, timeout:Int):Null<Int> {
		throw new haxe.exceptions.NotImplementedException();
	}
}
