package gghx;
import haxe.ds.Vector;
class Queue<T> {
    var data: Vector<T>;
    var i = 0;
    var len = 0;
    public var length(get, null): Int;
    public function get_length() {
        return len;
    }
    public function new(max_size:Int, def: () -> T) {
        data = new Vector<T>(max_size, def());
    }

    public function push(item: T) {
        if (len == data.length) {
            throw "Out of queue capacity";
        }
        var ni = (i + len) % data.length;
        len++;
        data[ni] = item;
    }
    public function pop(): Null<T> {
        if (len == 0) {
            return null;
        }
        var ret = data[i];
        data[i] = null;
        i = (i + 1) % data.length;
        len--;
        return ret;
    }
    public function front(): Null<T> {
        return if (len == 0) null else data[i];
    }
    public function iterator(): Iterator<T> {
        return new QueueIterator(data, i, i + len);
    }
}

class QueueIterator<T> {
    var data: Vector<T>;
    var i: Int;
    var j: Int;
    public function new(data: Vector<T>, i: Int, j: Int) {
        this.data = data;
        this.i = i;
        this.j = j % data.length;
    }
    public function hasNext(): Bool {
        return i != j;
    }
    public function next(): T {
        var res = data[i];
        i = (i + 1) % data.length;
        return res;
    }
}