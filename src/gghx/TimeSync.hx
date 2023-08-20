package gghx;

import haxe.ds.Vector;
import haxe.io.Int32Array;

final FRAME_WINDOW_SIZE = 40;
final MIN_UNIQUE_FRAMES = 10;
final MIN_FRAME_ADVANTAGE = 3;
final MAX_FRAME_ADVANTAGE = 9;

class TimeSync {
	var local:Vector<Int> = new Vector(FRAME_WINDOW_SIZE, 0);
	var remote:Vector<Int> = new Vector(FRAME_WINDOW_SIZE, 0);
	var last_inputs:Vector<GameInput> = new Vector(MIN_UNIQUE_FRAMES, null);
	var next_prediction:Int = FRAME_WINDOW_SIZE * 3;

	public function new() {}

	public function advanceFrame(input:GameInput, advantage:Int, radvantage:Int) {
		last_inputs[input.frame % last_inputs.length] = input;
		local[input.frame % remote.length] = advantage;
		remote[input.frame % local.length] = radvantage;
	}

	public function recommendFrameWaitDuration(require_idle_input:Bool):Int {
		var i:Int;
		var sum:Int = 0;
		for (i in local) {
			sum += i;
		}
		var advantage:Float = sum / local.length;
		sum = 0;
		for (i in remote) {
			sum += i;
		}
		var radvantage:Float = sum / remote.length;
		static var count = 0;
		count++;

		var sleep_frames = Math.ceil((radvantage - advantage) / 2);
		trace("iteration ", count, ": sleep frames is", sleep_frames);

		if (sleep_frames < MIN_FRAME_ADVANTAGE) {
			return 0;
		}

		if (require_idle_input) {
			for (i in 1...last_inputs.length) {
				if (!last_inputs[i].equal(last_inputs[0], true)) {
					trace("iteration ", count, ": reject due to input at position ", i);
					return 0;
				}
			}
		}
		return if (sleep_frames < MAX_FRAME_ADVANTAGE) sleep_frames else MAX_FRAME_ADVANTAGE;
	}
}
