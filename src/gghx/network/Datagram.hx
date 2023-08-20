package gghx.network;

import hxbit.Serializer;
import gghx.Assert.assert;
import haxe.io.Bytes;
import gghx.GGHX.Networking;
import gghx.Poll.Poll;
import gghx.network.DatagramMsg.Msg;

class Datagram<Handle> {
	public var network:Networking<Handle>;

	var cb:(Msg, Handle) -> Void;
	var poll:Poll<Handle>;

	public function new() {}

	public function newRemote(ip:String, port:Int):Handle {
		return network.newRemote(ip, port);
	}

	public function handleEqual(left:Handle, right:Handle) {
		return network.handleEqual(left, right);
	}

	public function init(network:Networking<Handle>, onMsg:(Msg, Handle) -> Void, poll:Poll<Handle>) {
		cb = onMsg;
		this.network = network;
		this.poll = poll;
		poll.registerLoop({onLoopPoll: (_) -> {
			this.onLoopPoll();
			return true;
		}}, 0);
	}

	public function sendTo(data:Bytes, to:Handle) {
		assert(network != null);
		network.send(data, to);
	}

	public function onLoopPoll() {
		while (true) {
			var data = network.recv();
			if (data != null) {
				trace('received len:${data.data.length} from ${data.from}');
				this.cb(Serializer.load(data.data, Msg), data.from);
			} else {
				break;
			}
		}
	}
}
