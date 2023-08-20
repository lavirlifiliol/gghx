package gghx;

import haxe.Timer;
import gghx.GGHX.Networking;
import haxe.ds.Vector;

final MAX_HANDLES:Int = 64;

@:structInit class PollSink {
	public var onHandlePoll:(a:Any) -> Bool = (_ -> true);
	public var onMsgPoll:(a:Any) -> Bool = (_ -> true);
	public var onPeriodicPoll:(a:Any, t:Int) -> Bool = ((_, _) -> true);
	public var onLoopPoll:(a:Any) -> Bool = (_ -> true);
}

@:structInit
class PollSinkCB {
	public var poll_sink:PollSink;
	public var cookie:Any;
}

@:structInit
class PollPeriodicSinkCB extends PollSinkCB {
	public var interval:Int;
	public var last_fired:Int;
}

class Poll<Handle> {
	var msg_sinks:Array<PollSinkCB> = [];
	var loop_sinks:Array<PollSinkCB> = [];
	var periodic_sinks:Array<PollPeriodicSinkCB> = [];
	var handles:Array<Handle> = [];
	var handle_count:Int = 0;
	var handle_sinks:Array<PollSinkCB> = [];
	var start_time:Int = 0;
	var nw:Networking<Handle>;

	public function new(nw:Networking<Handle>) {
		this.nw = nw;
	}

	public function registerHandle(sink:PollSink, h:Handle, cookie:Any) {
		handles.push(h);
		var p:PollSinkCB = {poll_sink: sink, cookie: cookie}
		handle_sinks.push(p);
	}

	public function registerMsgLoop(sink:PollSink, cookie:Any) {
		msg_sinks.push({poll_sink: sink, cookie: cookie});
	}

	public function registerLoop(sink:PollSink, cookie:Any) {
		loop_sinks.push({poll_sink: sink, cookie: cookie});
	}

	public function registerPeriodic(sink:PollSink, interval:Int, cookie:Any) {
		periodic_sinks.push({
			poll_sink: sink,
			interval: interval,
			cookie: cookie,
			last_fired: 0
		});
	}

	public function run() {
		while (pump(100)) {
			continue;
		}
	}

	public function pump(timeout:Int):Bool {
		var finished:Bool = false;

		if (start_time == 0) {
			start_time = now();
		}
		var elapsed:Int = now() - start_time;
		var maxwait = computeWaitTime(elapsed);
		if (maxwait != -1) {
			timeout = if (timeout < maxwait) timeout else maxwait;
		}
		if (handles.length > 0) {
			var res = nw.poll(handles, timeout);
			if (res != null) {
				finished = !handle_sinks[res].poll_sink.onHandlePoll(handle_sinks[res].cookie) || finished;
			}
		}
		for (sink in msg_sinks) {
			finished = !sink.poll_sink.onMsgPoll(sink.cookie) || finished;
		}
		for (cb in periodic_sinks) {
			if (cb.interval + cb.last_fired <= elapsed) {
				cb.last_fired = Std.int(elapsed / cb.interval) * cb.interval;
				finished = !cb.poll_sink.onPeriodicPoll(cb.cookie, cb.last_fired) || finished;
			}
		}

		for (sink in loop_sinks) {
			finished = !sink.poll_sink.onLoopPoll(sink.cookie) || finished;
		}

		return finished;
	}

	private function computeWaitTime(elapsed:Int):Int {
		var res:Int = -1;
		var n = periodic_sinks.length;
		if (n > 0) {
			for (cb in periodic_sinks) {
				var timeout = (cb.interval + cb.last_fired) - elapsed;
				if (res == -1 || timeout < res) {
					res = if (timeout < 0) 0 else timeout;
				}
			}
		}
		return res;
	}
}

function now():Int {
	return Std.int(Timer.stamp() * 1000);
}
