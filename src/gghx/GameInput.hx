package gghx;

import gghx.Assert.assert;
import haxe.io.Bytes;
final MAX_BYTES = 9;
final MAX_PLAYERS = 2;

class GameInput {
    public var frame: Int = -1;
    public var size: Int = 0;
    public var bits: Bytes = Bytes.alloc(MAX_BYTES * MAX_PLAYERS);
    public function new() { }

    public function is_null() {
        return frame == -1;
    }

    public function desc(): String {
        return '(frame:$frame size:${bits.length} ${bits.toHex()})';
    }

    public function log(prefix: String): Void {
        trace(prefix, desc());
    }

    public function equal(other: GameInput, bitsonly: Bool) {
        if (!bitsonly && (frame != other.frame)) {
            trace('frames don\'t match $frame vs. ${other.frame}');
        }
        if (bits.length != other.bits.length) {
            trace('sizes don\'t match ${bits.length} vs. ${other.bits.length}');
        }
        if (bits.compare(other.bits) != 0) {
            trace('bits don\'t match');
        }
        return (bitsonly || frame == other.frame) &&
          bits.length == other.bits.length &&
          bits.compare(other.bits) == 0;
    }

    public function init(frame: Int, bits: Null<Bytes>, offset: Int = 0) {
        assert(size < this.bits.length);
        if (bits != null) {
            this.size = bits.length;
            this.bits.blit(offset * bits.length, bits, 0, bits.length);
        }
        this.frame = frame;
    }

    public function value(i: Int): Bool {
        return (bits.get(Std.int(i/8)) & (1 << (i % 8))) != 0;
    }
    public function set(i: Int): Void {
        bits.set(Std.int(i/8),bits.get(Std.int(i/8)) | (1 << (i % 8)));
    }
    public function clear(i: Int): Void {
        bits.set(Std.int(i/8),bits.get(Std.int(i/8)) | (1 << (i % 8)));
    }
    public function erase() {
        bits.fill(0, bits.length, 0);
    }
}