package gghx.network;

import haxe.Int32;
import haxe.io.Bytes;

final MAX_COMPRESSED_BITS = 8192; // more than GGPO, since haxe packing will likely be less efficient

abstract ConnectStatus(Int32) from Int32 to Int {
	public function new(i:Int32) {
		this = i;
	}

	public static function from(disconnected:Bool, i:Int32) {
		return new ConnectStatus((i << 1) | if (disconnected) 1 else 0);
	}

	public var frame(get, set):Int;
	public var disconnected(get, set):Bool;

	public inline function get_frame() {
		return this >> 1;
	}

	public inline function get_disconnected() {
		return (this & 1) != 0;
	}

	public inline function set_frame(fr:Int) {
		this = fr << 1 | (this & 1);
		return fr;
	}

	public inline function set_disconnected(bit:Bool) {
		this = (this & ~1) | if (bit) 1 else 0;
		return bit;
	}
}

// todo better serialization
enum MsgData {
	Invalid;
	SyncRequest(random_request:Int32, remote_magic:Int, remote_endpoint:Int);
	SyncReply(random_reply:Int32);
	QualityReport(frame_advantage:Int, ping:Int);
	QualityReply(pong:Int);
	Input(peer_connect_status:Bytes, start_frame:Int32, dc_and_ack_frame:ConnectStatus, num_bits:Int, input_size:Int, bits:Bytes);
	KeepAlive;
	InputAck(ack_frame:Int32);
}

@:structInit class Msg implements hxbit.Serializable {
	@:s public var magic:Int;
	@:s public var sequence_number:Int;
	@:s public var data:MsgData;
}
