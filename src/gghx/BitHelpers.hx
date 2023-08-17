package gghx;

import gghx.Assert.assert;
import haxe.io.Bytes;


class BytesExtender {
    static public function setBit(bytes: Bytes, offset: Int): Int {
        bytes.set(Std.int(offset / 8), bytes.get(Std.int(offset / 8)) | (1 << (offset % 8)));
        return offset + 1;
    }
    static public function clearBit(bytes: Bytes, offset: Int): Int {
        bytes.set(Std.int(offset / 8), bytes.get(Std.int(offset / 8)) & ~(1 << (offset % 8)));
        return offset + 1;
    }
    static public function writeByte(bytes: Bytes, byte: Int, offset: Int): Int {
        assert(0 <= byte && byte <= 255);
        for (i in 0...8) {
            offset = (if ((byte & (1 << i)) != 0) setBit else clearBit)(bytes, offset);
        }
        return offset;
    }
    static public function readBit(bytes: Bytes, offset: Int): Bool {
        return 0 != (bytes.get(Std.int(offset / 8)) & (1 << (offset % 8)));
    }
    static public function readByte(bytes: Bytes, offset: Int): Int {
        var res = 0;
        for (i in 0...8) {
            res |= (if (readBit(bytes, offset + i)) 1 else 0) << i;
        }
        return res;
    }
}