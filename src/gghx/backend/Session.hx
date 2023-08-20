package gghx.backend;

import gghx.GGHX.GGError;
import haxe.ds.Vector;
import haxe.io.Bytes;
import gghx.GGHX.Player;
import gghx.GGHX.PlayerHandle;
import gghx.GGHX.NetworkStats;

abstract class Session {
	public function doPoll(timeout:Int):Void {}

	public abstract function addPlayer(player:Player):PlayerHandle;

	public abstract function addLocalInput(player:PlayerHandle, values:Bytes):Void; // todo check if Bytes is right

	public abstract function syncInput():Vector<Null<Bytes>>;

	public function incrementFrame():Void {}

	public function chat(text:String):Void {}

	public function disconnectPlayer(player:PlayerHandle):Void {}

	public abstract function getNetworkStats(player:PlayerHandle):NetworkStats;

	public function log(...args:String):Void {
		trace("GGHX:", args);
	}

	public function setFrameDelay(player:PlayerHandle, delay:Int):Void {
		throw new GGError(UNSUPPORTED);
	}

	public function setDisconnectTimeout(timeout:Int):Void {
		throw new GGError(UNSUPPORTED);
	}

	public function setDisconnectNotifyStart(timeout:Int):Void {
		throw new GGError(UNSUPPORTED);
	}
}

abstract DisconnectFlags(Int) from Int to Int {}
