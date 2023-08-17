package gghx.network;

import haxe.xml.Access;
import haxe.io.UInt8Array;
import haxe.io.Int32Array;
import haxe.ds.Vector;
import haxe.Int32;

abstract ConnectStatus(Int32) from Int32 {
    public function new(i: Int32) {
        this = i;
    }
    public static function from(disconnected: Bool, i: Int32) {
        return new ConnectStatus((i << 1) |  if (disconnected) 1 else 0);
    }
    public var frame(get, set): Int;
    public var disconnected(get, set): Bool;
    public inline function get_frame() {
        return this >> 1;
    }
    public inline function get_disconnected() {
        return (this & 1) != 0;
    }
    public inline function set_frame(fr: Int) {
        this = fr << 1 | (this & 1);
        return fr;
    }
    public inline function set_disconnected(bit: Bool) {
        this = (this & ~1) | if (bit) 1 else 0;
        return bit;
    }
    
}

//todo better serialization
enum MsgData {
    Invalid;
    SyncRequest(random_request: Int32, remote_magic: Int, remote_endpoint: Int);
    SyncReply(random_reply: Int32);
    QualityReport(frame_advantage: Int, ping: Int);
    QualityReply(pong: Int);
    Input(peer_connect_status: Int32Array, start_frame: Int32, local_status: ConnectStatus, num_bits: Int, input_size: Int, bits: UInt8Array);
    KeepAlive;
    InputAck(ack_frame: Int32);
}

@:structInit class Msg implements hxbit.Serializable {
    public var magic: Int;
    public var sequence_number: Int;
    public var data: MsgData;
}
