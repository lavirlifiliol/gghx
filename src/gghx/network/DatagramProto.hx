package gghx.network;

import gghx.network.DatagramMsg.MAX_COMPRESSED_BITS;
import haxe.io.UInt32Array;
import gghx.GGHX.NetworkStats;
import hxbit.Serializer;
import haxe.io.UInt8Array;
import haxe.io.Int32Array;
import haxe.io.Bytes;
import gghx.GameInput.MAX_BYTES;
import gghx.GameInput.MAX_PLAYERS;
import gghx.Assert.assert;
import haxe.io.BytesBuffer;
import gghx.network.DatagramMsg.MsgData;
import gghx.network.DatagramMsg.ConnectStatus;
import gghx.network.DatagramMsg.Msg;
import gghx.GGHX.NWStats;
import gghx.GGHX.Networking;
import gghx.Queue;
import gghx.GGHX.mod;
import gghx.Poll;

using gghx.BitHelpers.BytesExtender;

final UDP_HEADER_SIZE = 28; /* Size of IP + UDP headers */
final NUM_SYNC_PACKETS = 5;
final SYNC_RETRY_INTERVAL = 2000;
final SYNC_FIRST_RETRY_INTERVAL = 500;
final RUNNING_RETRY_INTERVAL = 200;
final KEEP_ALIVE_INTERVAL = 200;
final QUALITY_REPORT_INTERVAL = 1000;
final NETWORK_STATS_INTERVAL = 1000;
final UDP_SHUTDOWN_TIMER = 5000;
final MAX_SEQ_DISTANCE = (1 << 15);

@:structInit class Stats {
	public var ping:Int;
	public var remote_frame_advantage:Int;
	public var local_frame_advantage:Int;
	public var send_queue_len:Int;
	public var stats:NWStats;
}

enum Event {
	Unknown;
	Connected;
	Synchronizing(total:Int, count:Int);
	Synchronized;
	Input(input:GameInput);
	Disconnected;
	NetworkInterrupted(disconnect_timeout:Int);
	NetworkResumed;
}

private enum State {
	Syncing(roundtrips_remaining:Int, random:Int);
	// Synchronized; // unsued in GGPO afaict
	Running(last_quality_report_time:Int, last_network_stats_interval:Int, last_input_packet_recv_time:Int);
	Disconnected;
}

@:structInit private class QueueEntry<Handle> {
	public var queue_time:Int;
	public var dest_addr:Handle;
	public var msg:Msg;
}

@:structInit private class OOPacket<Handle> {
	public var send_time:Int;
	public var dest_addr:Handle;
	public var msg:Msg;
}

class DatagramProto<Handle> {
	var network:Datagram<Handle> = null;
	var remote:Handle;
	var magic_number:Int = 0;
	var queue:Int = -1;
	var remote_magic_number:Int = 0;
	var connected:Bool = false;
	var send_latency:Int;
	var oo_packet:OOPacket<Handle>;
	var oop_percent:Int;

	var send_queue:Queue<QueueEntry<Handle>> = new Queue(128, () -> null);

	// stats
	var round_trip_time:Int = 0;
	var packets_sent:Int = 0;
	var bytes_sent:Int = 0;
	var kbps_sent:Int;
	var stats_start_time:Int = 0;

	// state machine
	var local_connect_status:Array<ConnectStatus>;
	var peer_connect_status:Int32Array;
	var state:State = Disconnected;

	var local_frame_advantage:Int = 0;
	var remote_frame_advantage:Int = 0;

	var pending_output:Queue<GameInput> = new Queue(128, () -> new GameInput());
	var last_received_input:GameInput = new GameInput();
	var last_sent_input:GameInput = new GameInput();
	var last_acked_input:GameInput = new GameInput();
	var last_send_time:Int = 0;
	var last_recv_time:Int;
	var shutdown_timeout:Int = 0;
	var disconnect_event_set:Int;
	var disconnect_timeout:Int;
	var disconnect_notify_start:Int = 0;
	var disconnect_notify_sent:Bool = false;
	var disconnect_event_sent:Bool = false;

	var next_send_seq:Int = 0;
	var next_recv_seq:Int = 0;

	var timesync:TimeSync = new TimeSync();

	var event_queue:Queue<Event> = new Queue(64, () -> Event.Unknown);

	public function new(network:Datagram<Handle>, poll:Poll<Handle>, queue:Int, ip:String, port:Int, num_players:Int, connect_status:Array<ConnectStatus>) {
		// network is null for the local endpoint
		if (network != null) {
			this.network = network;
			this.remote = network.newRemote(ip, port);
			this.send_latency = network.network.send_latency;
			this.oop_percent = network.network.oop_percent;
		}
		this.local_connect_status = connect_status;
		this.queue = queue;

		var pcs:Array<ConnectStatus> = [];
		for (i in 0...num_players) {
			pcs.push(0);
			pcs[i].frame = -1;
		}
		peer_connect_status = Int32Array.fromArray(pcs.map((a) -> cast(a, Int)));

		do {
			magic_number = Std.int(Math.random() * (1 << 16));
		} while (magic_number == 0);
		oo_packet = {send_time: 0, msg: null, dest_addr: null};
		poll.registerLoop({
			onLoopPoll: (_) -> {
				this.onLoopPoll();
				return true;
			}
		}, []);
	}

	public function sendInput(input:GameInput) {
		if (network != null) {
			if (state.match(Running(_, _, _))) {
				timesync.advanceFrame(input, local_frame_advantage, remote_frame_advantage);
				pending_output.push(input);
			}
		}
		sendPendingInput();
	}

	function sendPendingInput() {
		var front = pending_output.front();
		var msg_bits = Bytes.alloc(MAX_COMPRESSED_BITS);
		var offset = 0;
		if (front != null) {
			var last = last_acked_input;
			assert(last.is_null() || last.frame + 1 == front.frame);
			for (current in pending_output) {
				if (current.bits.compare(last.bits) != 0) {
					trace('##diff ', current.bits.toHex(), 'vs', last.bits.toHex());
					for (i in 0...current.bits.length * 8) {
						if (last.value(i) != current.value(i)) {
							trace('  ##diff at $i', current.value(i), last.value(i), 'at $offset');
							offset = msg_bits.setBit(offset);
							offset = (if (current.value(i)) msg_bits.setBit else msg_bits.clearBit)(offset);
							offset = msg_bits.writeByte(i, offset);
						}
					}
					trace('##compressed to', msg_bits.sub(0, Math.ceil(offset / 8)).toHex());
				}
				offset = msg_bits.clearBit(offset);
				last = last_sent_input = current;
			}
		}
		// todo this should be local connect status
		var peer_connect_status_cp = Bytes.alloc(peer_connect_status.view.byteLength);
		peer_connect_status_cp.blit(0, peer_connect_status.view.buffer, 0, peer_connect_status_cp.length);
		var status = new ConnectStatus(0);
		status.disconnected = state.match(Disconnected);
		status.frame = last_received_input.frame; // ack frame
		var msg:MsgData = MsgData.Input(peer_connect_status_cp, if (front != null) front.frame else 0, status, offset, if (front != null) front.size else 0,
			msg_bits.sub(0, Std.int(offset / 8) + 1));
		assert(offset < MAX_COMPRESSED_BITS);
		sendMsg(msg);
	}

	public function sendInputAck() {
		assert(!last_acked_input.is_null());
		var msg = MsgData.InputAck(last_acked_input.frame);
		sendMsg(msg);
	}

	public function getEvent():Null<Event> {
		return event_queue.pop();
	}

	public function onLoopPoll() {
		if (network == null) {
			return;
		}
		var nowv = now();
		pumpSendQueue();
		switch (state) {
			case Syncing(roundtrips_remaining, random):
				{
					var next_interval = if (roundtrips_remaining == NUM_SYNC_PACKETS) SYNC_FIRST_RETRY_INTERVAL else SYNC_RETRY_INTERVAL;
					if (last_send_time != 0 && last_send_time + next_interval < nowv) {
						trace('No luck syncing after $next_interval ms... Re-queueing sync packet');
						sendSyncRequest();
					}
				}
			case Running(last_quality_report_time, last_network_stats_interval, last_input_packet_recv_time):
				{
					if (last_input_packet_recv_time == 0 || last_input_packet_recv_time + RUNNING_RETRY_INTERVAL < nowv) {
						trace('Haven\'t exchanged packets in a while (last received:${last_received_input.frame} last sent: ${last_sent_input.frame}), Resending');
						sendPendingInput();
						state = Running(last_quality_report_time, last_network_stats_interval, nowv);
					}
					if (last_quality_report_time == 0 || last_quality_report_time + QUALITY_REPORT_INTERVAL < nowv) {
						var msg:MsgData = QualityReport(local_frame_advantage, now());
						sendMsg(msg);
						state = Running(nowv, last_network_stats_interval, last_input_packet_recv_time);
					}
					if (last_network_stats_interval == 0 || last_network_stats_interval + NETWORK_STATS_INTERVAL < nowv) {
						updateNetworkStats();
						state = Running(last_quality_report_time, nowv, last_input_packet_recv_time);
					}
					if (last_send_time != 0 && last_send_time + KEEP_ALIVE_INTERVAL < nowv) {
						trace("Sending keep alive packet");
						sendMsg(MsgData.KeepAlive);
					}
					if (disconnect_timeout != 0
						&& disconnect_notify_start != 0
						&& !disconnect_notify_sent
						&& (last_recv_time + disconnect_notify_start < nowv)) {
						trace('Endpoint has stopped receiving packets for $disconnect_notify_start ms. Sending notification');
						queueEvent(Event.NetworkInterrupted(disconnect_timeout - disconnect_notify_start));
						disconnect_notify_sent = true;
					}
					if (disconnect_timeout != 0 && (last_recv_time + disconnect_timeout < nowv)) {
						if (!disconnect_event_sent) {
							trace('Endpoint has stopped receiving packets for $disconnect_timeout ms. Disconnecting');
							queueEvent(Event.Disconnected);
							disconnect_event_sent = true;
						}
					}
				}
			case Disconnected:
				if (shutdown_timeout < nowv) {
					trace("shutting down connection.");
					network = null;
					shutdown_timeout = 0;
				}
		}
	}

	public function disconnect():Void {
		state = Disconnected;
		shutdown_timeout = now() + UDP_SHUTDOWN_TIMER;
	}

	public function sendSyncRequest() {
		var random;
		switch (state) {
			case Syncing(v, _):
				state = Syncing(v, random = Std.int(Math.random() * 0xFFFF));
			default:
				assert(false);
				throw false;
		}
		sendMsg(SyncRequest(random, 0, 0)); // TODO figure out why these are zero/where they get set
	}

	public function sendMsg(msg_data:MsgData) {
		var msg:Msg = {
			magic: magic_number,
			sequence_number: next_send_seq++,
			data: msg_data
		};
		trace("send", msg);
		packets_sent++;
		last_send_time = now();
		bytes_sent += Serializer.save(msg).length; // TODO not this
		var qe:QueueEntry<Handle> = {
			queue_time: now(),
			dest_addr: remote,
			msg: msg
		};
		send_queue.push(qe);
		pumpSendQueue();
	}

	public function handlesMsg(msg:Msg, from:Handle) {
		if (network == null) {
			return false;
		}
		return network.handleEqual(from, remote);
	}

	public function onMsg(msg:Msg) {
		var seq = msg.sequence_number;
		if (!msg.data.match(SyncRequest(_, _, _)) && !msg.data.match(SyncReply(_))) {
			if (msg.magic != remote_magic_number) {
				trace("recv rejecting", msg);
				return;
			}

			var skipped = mod(seq - next_recv_seq, 1 << 16);
			if (skipped > MAX_SEQ_DISTANCE) {
				trace('dropping out of order packets (seq:$seq last seq:$next_recv_seq)');
				return;
			}
		}
		next_recv_seq = seq;
		trace("recv", msg);
		var handled = switch (msg.data) {
			case Invalid:
				onInvalid();
			case SyncRequest(random_request, remote_magic, remote_endpoint):
				onSyncRequest(msg, random_request, remote_magic, remote_endpoint);
			case SyncReply(random_reply):
				onSyncReply(msg, random_reply);
			case Input(peer_connect_status, start_frame, dc_and_ack_frame, num_bits, input_size, bits):
				onInput(msg, Int32Array.fromBytes(peer_connect_status), start_frame, dc_and_ack_frame.disconnected, dc_and_ack_frame.frame, num_bits,
					input_size, bits);
			case QualityReport(frame_advantage, ping):
				onQualityReport(msg, frame_advantage, ping);
			case KeepAlive:
				onKeepAlive(msg);
			case InputAck(ack_frame):
				onInputAck(msg, ack_frame);
			case QualityReply(pong):
				onQualityReply(msg, pong);
		};
		if (handled) {
			last_recv_time = now();
			if (disconnect_notify_sent && state.match(Running(_, _, _))) {
				queueEvent(Event.NetworkResumed);
				disconnect_notify_sent = false;
			}
		}
	}

	function updateNetworkStats() {
		var nowv = now();
		if (stats_start_time == 0) {
			stats_start_time = nowv;
		}

		var total_bytes_sent = bytes_sent + (UDP_HEADER_SIZE * packets_sent); // inaccurate if not udp
		var seconds = (nowv - stats_start_time) / 1000 + 0.0001;
		var bps = total_bytes_sent / seconds;
		var overhead = 100 * (UDP_HEADER_SIZE * packets_sent) / (bytes_sent + 0.0001);
		kbps_sent = Std.int(bps / 1024);
		trace("Network stats -- ", 'Bandwidth $kbps_sent KBps  ',
			'Packets sent $packets_sent (${1000 * packets_sent / (nowv - stats_start_time + 0.0001)} pps) ', 'KB sent: ${total_bytes_sent / 1024}');
	}

	function queueEvent(ev:Event) {
		trace('Queing event from $queue', ev);
		event_queue.push(ev);
	}

	public function synchronize() {
		if (network != null) {
			state = Syncing(NUM_SYNC_PACKETS, 0); // set later
			sendSyncRequest();
		}
	}

	public function getPeerConnectStatus(id:Int):ConnectStatus {
		return peer_connect_status[id];
	}

	public function isRunning() {
		return state.match(Running(_, _, _));
	}

	public function isInitialized() {
		return network != null;
	}

	public function isSynchronized() {
		return isRunning();
	}

	// TODO all the log functions

	function onInvalid():Bool {
		assert(false);
		return false;
	}

	function onSyncRequest(msg:Msg, random_request:Int, remote_magic:Int, remote_endpoint:Int):Bool {
		// the unusued arguments seem to be a constant 0
		if (remote_magic != 0 && msg.magic != remote_magic) {
			trace('Ignoring sync request from unknown endpoint (${msg.magic} != $remote_magic');
			return false;
		}
		sendMsg(SyncReply(random_request));
		return true;
	}

	function onSyncReply(msg:Msg, random_reply:Int) {
		switch (state) {
			case Syncing(roundtrips_remaining, random):
				{
					if (random_reply != random) {
						trace('sync reply $random != $random_reply. Keep looking');
						return false;
					}
					if (!connected) {
						queueEvent(Event.Connected);
						connected = true;
					}

					trace('checking sync state ($roundtrips_remaining round trips remaining)');
					state = Syncing(roundtrips_remaining - 1, random);
					if (roundtrips_remaining - 1 == 0) {
						trace("synchronized");
						queueEvent(Synchronized);
						state = Running(0, 0, 0);
						last_received_input = new GameInput();
						remote_magic_number = msg.magic;
					} else {
						queueEvent(Synchronizing(NUM_SYNC_PACKETS, NUM_SYNC_PACKETS - roundtrips_remaining - 1));
						sendSyncRequest();
					}
					return true;
				}
			default:
				{
					trace("ignoring SyncReply while not syncing");
					return msg.magic == remote_magic_number;
				}
		}
	}

	public function onInput(msg:Msg, remote_status:Int32Array, start_frame:Int, disconnected:Bool, ack_frame:Int, num_bits:Int, input_size:Int, bits:Bytes) {
		if (disconnected) {
			if (!state.match(Disconnected) && !disconnect_event_sent) {
				trace("Disconnecting endpoint on remote request");
				queueEvent(Disconnected);
				disconnect_event_sent = true;
			}
		} else {
			assert(remote_status.length == this.peer_connect_status.length);
			for (i in 0...peer_connect_status.length) {
				var cs = new ConnectStatus(remote_status[i]);
				var lcs = new ConnectStatus(peer_connect_status[i]);
				assert(cs.frame >= lcs.frame);
				lcs.disconnected = lcs.disconnected || cs.disconnected;
				lcs.frame = if (lcs.frame > cs.frame) lcs.frame else cs.frame;
				peer_connect_status.set(i, lcs);
			}
		}
		var last_received_frame = last_received_input.frame;
		if (num_bits > 0) {
			var offset = 0;
			var current_frame = start_frame;
			if (last_received_input.is_null()) {
				trace('starting at ${start_frame - 1}');
				last_received_input.frame = start_frame - 1;
			}
			last_received_input.size = input_size;
			while (offset < num_bits) {
				trace('asserting with $current_frame and ${last_received_input.frame}');
				assert(current_frame <= last_received_input.frame + 1);
				var use_inputs = current_frame == last_received_input.frame + 1;
				if (use_inputs) {
					trace('##parsing $num_bits bits from', bits.toHex(), 'started at $offset');
				}
				while (bits.readBit(offset++)) {
					var on = bits.readBit(offset++);
					var button = bits.readByte(offset);
					offset += 8;
					if (use_inputs) {
						trace('  ##diff', offset - 10, on, 'at', button);
						if (on) {
							last_received_input.set(button);
						} else {
							trace('##clear', button);
							last_received_input.clear(button);
						}
					}
				}
				assert(offset <= num_bits);
				if (use_inputs) {
					assert(current_frame == last_received_input.frame + 1);
					last_received_input.frame = current_frame;

					trace('##using', last_received_input.bits.toHex());

					var desc = last_received_input.desc();
					switch (state) {
						case Running(last_quality_report_time, last_network_stats_interval, last_input_packet_recv_time):
							state = Running(last_quality_report_time, last_network_stats_interval, now());
						default:
							assert(false);
					}
					trace('sending frame $current_frame to emu queue $queue ($desc)');
					queueEvent(Input(last_received_input.copy()));
				} else {
					trace('Skipping past frame: ($current_frame) current is ${last_received_input.frame}');
				}
				current_frame++;
			}
		}
		assert(last_received_input.frame >= last_received_frame);
		while (pending_output.length > 0 && pending_output.front().frame < ack_frame) {
			trace('Throwing away pending output frame ${pending_output.front().frame}');
			last_acked_input = pending_output.pop();
		}
		return true;
	}

	public function onInputAck(msg:Msg, ack_frame:Int) {
		while (pending_output.length > 0 && pending_output.front().frame < ack_frame) {
			trace('Throwing away pending output frame ${pending_output.front().frame}');
			last_acked_input = pending_output.pop();
		}

		return true;
	}

	public function onQualityReport(msg:Msg, frame_advantage:Int, ping:Int) {
		sendMsg(QualityReply(ping));

		remote_frame_advantage = frame_advantage;
		return true;
	}

	public function onQualityReply(msg:Msg, pong:Int) {
		round_trip_time = now() - pong;
		return true;
	}

	public function onKeepAlive(msg:Msg) {
		return true;
	}

	public function getNetworkStats():NetworkStats {
		return {
			network: {
				ping: round_trip_time,
				send_queue_len: pending_output.length,
				kbps_sent: kbps_sent,
				recv_queue_len: 0,
			},
			timesync: {
				remote_frames_behind: remote_frame_advantage,
				local_frames_behind: local_frame_advantage
			}
		}
	}

	public function setLocalFrameNumber(local_frame:Int) {
		var remote_frame = Std.int(last_received_input.frame + (round_trip_time * 60 / 1000));
		local_frame_advantage = remote_frame - local_frame;
	}

	public function recommendFrameDelay() {
		// todo config
		return timesync.recommendFrameWaitDuration(false);
	}

	public function setDisconnectTimeout(timeout:Int) {
		disconnect_timeout = timeout;
	}

	public function setDisconnectNotifyStart(timeout:Int) {
		disconnect_notify_start = timeout;
	}

	public function pumpSendQueue() {
		var entry = send_queue.front();
		while (entry != null) {
			if (send_latency > 0) {
				var jitter = (send_latency * 2 / 3) + (Std.int(Math.random() * send_latency) / 3);
				if (now() < entry.queue_time + jitter) {
					break;
				}
			}
			if (oop_percent > 0 && oo_packet.msg == null && Math.random() * 100 < oop_percent) {
				var delay = Std.int(Math.random() * (send_latency * 10 + 1000));
				trace('creating rogue oop (seq: ${entry.msg.sequence_number} delay: $delay)');
				oo_packet.send_time = now() + delay;
				oo_packet.msg = entry.msg;
				oo_packet.dest_addr = entry.dest_addr;
			} else {
				assert(entry.dest_addr != null);

				network.sendTo(Serializer.save(entry.msg), entry.dest_addr);
			}
			send_queue.pop();
			entry = send_queue.front();
		}
		if (oo_packet.msg != null && oo_packet.send_time < now()) {
			trace("sending rogue oop");
			network.sendTo(Serializer.save(oo_packet.msg), oo_packet.dest_addr);
			oo_packet.msg = null;
		}
	}

	public function clearSendQueue() {
		while (send_queue.front() != null) {
			send_queue.pop();
		}
	}

	// TODO: double check input exchanging, it is a bit weird;
}
