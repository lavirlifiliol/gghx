package gghx;

import haxe.Exception;

function assert(v:Bool) {
	if (!v) {
		throw new Exception("assertion failed");
	}
}
