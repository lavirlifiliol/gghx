package gghx;

import haxe.macro.Expr;

macro function log(extra:Array<Expr>) {
	#if gghx_log
	return macro trace($a{extra});
	#else
	return macro null;
	#end
}
