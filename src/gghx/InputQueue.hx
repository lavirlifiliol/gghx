package gghx;

import gghx.Assert.assert;
import haxe.io.Bytes;
import haxe.ds.Vector;

final INPUT_QUEUE_LENGTH = 128;

inline function prev_frame(offset) {
	return if (offset == 0) INPUT_QUEUE_LENGTH - 1 else offset - 1;
}

class InputQueue {
	var id:Int = -1;
	var head:Int = 0;
	var tail:Int = 0;
	var length:Int = 0;
	var first_frame:Bool = true;

	var last_user_added_frame:Int = -1;
	var last_added_frame:Int = -1;
	var first_incorrect_frame:Int = -1;
	var last_frame_requested:Int = -1;

	var frame_delay:Int = 0;

	var inputs:Vector<GameInput> = new Vector(INPUT_QUEUE_LENGTH, null);
	var prediction:GameInput = new GameInput();

	public function new(id:Int, input_size:Int) {
		prediction.init(-1, Bytes.ofString(""));
		prediction.size = input_size;
		for (i in 0...inputs.length) {
			inputs[i] = new GameInput();
			inputs[i].size = input_size;
		}
	}

	public function getLastConfirmedFrame():Int {
		trace('returning last confirmed frame $last_added_frame.');
		return last_added_frame;
	}

	public function getFirstIncorrectFrame():Int {
		return first_incorrect_frame;
	}

	public function discardConfirmedFrames(frame:Int) {
		assert(frame >= 0);
		if (last_frame_requested != -1) {
			frame = if (frame < last_frame_requested) frame else last_frame_requested;
		}

		trace("", 'Discarding confirmed frames up to $frame (last added $last_added_frame length:$length [head:$head tail:$tail])');
		if (frame >= last_added_frame) {
			tail = head;
		} else {
			var offset = frame - inputs[tail].frame + 1;
			trace('difference of $offset frames');
			assert(offset >= 0);
			tail = (tail + offset) % INPUT_QUEUE_LENGTH;
			length -= offset;
		}

		trace('after discarding, new tail is $tail (frame:${inputs[tail].frame})');
		assert(length > 0);
	}

	public function resetPrediction(frame:Int) {
		assert(first_incorrect_frame == -1 || frame <= first_incorrect_frame);
		trace('resetting all prediction errors back to frame $frame');
		prediction.frame = -1;
		first_incorrect_frame = -1;
		last_frame_requested = -1;
	}

	public function getConfirmedInput(requested_frame:Int):Null<GameInput> {
		assert(first_incorrect_frame == -1 || requested_frame < first_incorrect_frame);
		var offset = requested_frame % INPUT_QUEUE_LENGTH;
		if (inputs[offset].frame != requested_frame) {
			return null;
		}

		return inputs[offset].copy();
	}

	public function getInput(requested_frame:Int):GetInputOut {
		trace('requesting input frame:$requested_frame');
		assert(first_incorrect_frame == -1);

		last_frame_requested = requested_frame;

		assert(requested_frame >= inputs[tail].frame);

		if (prediction.frame == -1) {
			var offset = requested_frame - inputs[tail].frame;
			if (offset < length) {
				offset = (offset + tail) % INPUT_QUEUE_LENGTH;
				assert(inputs[offset].frame == requested_frame);
				var input = inputs[offset];
				trace('returning confirmed frame number ${input.frame}');
				return {isConfirmed: true, input: input.copy()};
			}

			if (requested_frame == 0) {
				trace('basing prediction on nothing, your client wants frame 0');
				prediction.erase();
			} else if (last_added_frame == -1) {
				trace('basing prediction on nothing, we have no frames yet');
				prediction.erase();
			} else {
				trace('basic new prediction on previous frame (queue entry:${prev_frame(head)} frame:${inputs[prev_frame(head)].frame})');
				prediction = inputs[prev_frame(head)].copy();
			}
			prediction.frame++;
		}

		assert(prediction.frame >= 0);
		var res = new GameInput();
		res.init(requested_frame, prediction.bits.sub(0, prediction.size));
		trace('returning prediction frame number ${res.frame} (${prediction.frame})');
		return {isConfirmed: false, input: res};
	}

	public function addInput(input:GameInput) {
		trace('adding input frame number ${input.frame} to queue, last $last_user_added_frame');

		assert(last_user_added_frame == -1 || input.frame == last_user_added_frame + 1);
		last_user_added_frame = input.frame;
		var new_frame = advanceQueueHead(input.frame);
		if (new_frame != -1) {
			addDelayedInputToQueue(input, new_frame);
		}

		input.frame = new_frame;
	}

	public function addDelayedInputToQueue(input:GameInput, frame:Int) {
		trace('adding delayed input frame $frame to queue, last $last_added_frame');

		assert(input.size == prediction.size);
		assert(last_added_frame == -1 || frame == last_added_frame + 1);
		assert(frame == 0 || inputs[prev_frame(head)].frame == frame - 1);

		inputs[head] = new GameInput();
		inputs[head].init(frame, input.bits.sub(0, input.size));
		trace('added input at ${head} with frame:$frame');
		head = (head + 1) % INPUT_QUEUE_LENGTH;
		length++;
		first_frame = false;

		last_added_frame = frame;

		if (prediction.frame != -1) {
			assert(frame == prediction.frame);
			// we've been predicting
			if (first_incorrect_frame == -1 && !prediction.equal(input, true)) {
				trace('frame $frame does not match prediction');
				first_incorrect_frame = frame;
			}

			if (prediction.frame == last_frame_requested && first_incorrect_frame == -1) {
				trace('prediction correct! dumping out of prediction mode');
				prediction.frame = -1;
			} else {
				prediction.frame++;
			}
		}
		assert(length <= INPUT_QUEUE_LENGTH);
	}

	public function advanceQueueHead(frame:Int):Int {
		trace('advancing queue head to frame $frame', '');
		trace('  head at $head, prev at ${prev_frame(head)}, framenum there at ${inputs[prev_frame(head)].frame}');
		var expected_frame = first_frame ? 0 : (inputs[prev_frame(head)].frame + 1);

		frame += frame_delay;
		if (expected_frame > frame) {
			trace('dropping input frame $frame (expected next frame $expected_frame)');
			return -1;
		}
		while (expected_frame < frame) {
			trace('padding frame $expected_frame to account for change in frame delay');
			var inp = inputs[prev_frame(head)];
			addDelayedInputToQueue(inp, expected_frame);
			expected_frame++;
		}
		assert(frame == 0 || frame == inputs[prev_frame(head)].frame + 1);
		return frame;
	}

	public function setFrameDelay(delay:Int) {
		this.frame_delay = delay;
	}

	public function getLength() {
		return this.length;
	}

	// todo log
}

@:structInit class GetInputOut {
	public var isConfirmed:Bool;
	public var input:GameInput;
}
