package gghx;

import gghx.Assert.assert;
import gghx.network.DatagramMsg.ConnectStatus;
import haxe.ds.Vector;
import haxe.io.Bytes;
import gghx.GGHX.Callbacks;

final MAX_PREDICTION_FRAMES = 8;

@:structInit class Config {
	public var callbacks:Callbacks;
	public var num_prediction_frames:Int;
	public var num_players:Int;
	public var input_size:Int;
}

enum SyncEvent {
	ConfirmedInput(input:GameInput);
}

@:structInit class SavedFrame {
	public var buf:Bytes;
	public var frame:Int;
	public var checksum:Int;
}

@:structInit class SavedState {
	public var frames:Vector<SavedFrame> = new Vector(MAX_PREDICTION_FRAMES + 2, null);
	public var head:Int;
}

class Sync {
	var callbacks:Callbacks;
	var saved_state:SavedState = {head: 0};
	var config:Config;

	var rollingback:Bool;
	var last_confirmed_frame:Int = 0;
	var framecount:Int = 0;
	var max_prediction_frames:Int = 0;

	var input_queues:Array<InputQueue> = [];

	var event_queue:Queue<SyncEvent> = new Queue(32, () -> null);
	var local_connect_status:Array<ConnectStatus>;

	public function new(connect_status:Array<ConnectStatus>) {
		this.local_connect_status = connect_status;
	}

	public function init(config:Config) {
		this.config = config;
		this.callbacks = config.callbacks;
		this.framecount = 0;
		this.rollingback = false;
		this.max_prediction_frames = config.num_prediction_frames;
		createQueues(config);
	}

	public function inRollback() {
		return rollingback;
	}

	public function getFrameCount() {
		return framecount;
	}

	public function setLastConfirmedFrame(frame:Int) {
		last_confirmed_frame = frame;
		if (last_confirmed_frame > 0) {
			for (i in 0...config.num_players) {
				input_queues[i].discardConfirmedFrames(frame - 1);
			}
		}
	}

	public function addLocalInput(queue:Int, input:GameInput):Bool {
		var frames_behind = framecount - last_confirmed_frame;
		if (framecount >= max_prediction_frames && frames_behind >= max_prediction_frames) {
			trace("rejecting input from emulator, ", "reached emulation barrier");
			return false;
		}
		if (framecount == 0) {
			saveCurrentFrame();
		}

		trace('sending undelayed local frame $framecount to queue $queue');
		input.frame = framecount;
		input_queues[queue].addInput(input);
		return true;
	}

	public function addRemoteInput(queue:Int, input:GameInput) {
		input_queues[queue].addInput(input);
	}

	public function getConfirmedInputs(frame:Int):Vector<Null<Bytes>> {
		var res = new Vector(config.num_players);
		for (i in 0...config.num_players) {
			if (local_connect_status[i].disconnected && frame > local_connect_status[i].frame) {
				res.set(i, null);
			} else {
				var input = input_queues[i].getInput(frame).input;
				res.set(i, input.bits.sub(0, input.size));
			}
		}
		return res;
	}

	public function synchronizeInputs():Vector<Null<Bytes>> {
		var res = new Vector(config.num_players);
		for (i in 0...config.num_players) {
			if (local_connect_status[i].disconnected && framecount > local_connect_status[i].frame) {
				res.set(i, null);
			} else {
				var input = input_queues[i].getInput(framecount).input;
				res.set(i, input.bits.sub(0, input.size));
			}
		}
		return res;
	}

	public function checkSimulation(timeout:Int) {
		// ??? unused timeout
		var seek_to = checkSimulationConsistency();
		if (seek_to >= 0) {
			adjustSimulation(seek_to);
		}
	}

	public function incrementFrame() {
		framecount++;
		saveCurrentFrame();
	}

	public function adjustSimulation(seek_to:Int) {
		var framecount = this.framecount;
		var count = framecount - seek_to;
		trace('Catching up', '');
		rollingback = true;
		loadFrame(seek_to);
		assert(this.framecount == seek_to);

		resetPrediction(this.framecount);
		for (_ in 0...count) {
			callbacks.advanceFrame();
		}
		assert(this.framecount == framecount);
		rollingback = false;
		trace("-------");
	}

	public function loadFrame(frame:Int) {
		if (frame == framecount) {
			trace("skipping, NOP");
			return;
		}

		saved_state.head = findSavedFrameIndex(frame);
		var state = saved_state.frames[saved_state.head]; // unlike C++, this does not copy
		trace('loading frame info ${state.frame} (size:${state.buf.length} chs:${state.checksum})');
		callbacks.loadGameState(state.buf);

		framecount = state.frame;
		saved_state.head = (saved_state.head + 1) % saved_state.frames.length;
	}

	public function saveCurrentFrame() {
		var res = callbacks.saveGameState(framecount);
		saved_state.frames.set(saved_state.head, {buf: res.state, frame: framecount, checksum: res.checksum});
		var state = saved_state.frames.get(saved_state.head);
		trace('=== Saved frame info ${state.frame} (size:${state.buf.length} checksum${state.checksum})');

		saved_state.head = (saved_state.head + 1) % saved_state.frames.length;
	}

	public function getLastSavedState() {
		var i = saved_state.head - 1;
		if (i < 0) {
			i = saved_state.frames.length - 1;
		}
		return saved_state.frames[i];
	}

	public function findSavedFrameIndex(frame:Int):Int {
		for (i in 0...saved_state.frames.length) {
			if (saved_state.frames[i] != null && saved_state.frames[i].frame == frame) {
				return i;
			}
		}
		assert(false);
		throw false;
	}

	public function createQueues(config:Config) {
		input_queues = new Array();
		for (i in 0...config.num_players) {
			input_queues.push(new InputQueue(i, config.input_size));
		}
		return true;
	}

	function checkSimulationConsistency():Int { // -1 means no adjustment
		var first_incorrect = -1;
		for (i in 0...config.num_players) {
			var incorrect = input_queues[i].getFirstIncorrectFrame();
			trace('considering incorrect frame $incorrect reported by queue $i');
			if (incorrect != -1 && (first_incorrect == -1 || incorrect < first_incorrect)) {
				first_incorrect = incorrect;
			}
		}

		if (first_incorrect == -1) {
			trace('prediction ok, proceeding');
			return -1;
		}
		return first_incorrect;
	}

	public function setFrameDelay(queue:Int, delay:Int) {
		input_queues[queue].setFrameDelay(delay);
	}

	public function resetPrediction(frame_number:Int) {
		for (q in input_queues) {
			q.resetPrediction(frame_number);
		}
	}

	// unused, queue is never pushed to
	public function getEvent():Null<SyncEvent> {
		return event_queue.pop();
	}

	static public function main() {
		trace('hi');
	}
}
