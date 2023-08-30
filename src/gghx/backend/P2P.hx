package gghx.backend;

import gghx.network.DatagramMsg.Msg;
import haxe.ds.Vector;
import gghx.GGHX.GGError;
import gghx.Assert.assert;
import gghx.Sync.MAX_PREDICTION_FRAMES;
import gghx.network.DatagramMsg.ConnectStatus;
import gghx.network.DatagramProto;
import gghx.GGHX.Networking;
import gghx.GGHX.Callbacks;
import gghx.GGHX.Player;
import gghx.GGHX.PlayerHandle;
import gghx.network.Datagram;
import haxe.io.Bytes;
import gghx.GGHX.NetworkStats;

final RECOMMENDATION_INTERVAL = 240;
final DEFAULT_DISCONNECT_TIMEOUT = 5000;
final DEFAULT_DISCONNECT_NOTIFY_START = 750;

class P2P<Handle> extends Session {
	var callbacks:Callbacks;
	var poll:Poll<Handle>;
	var sync:Sync;
	var networking:Datagram<Handle>;
	var endpoints:Array<DatagramProto<Handle>> = [];
	// TODO spectators
	var input_size:Int;

	var synchronizing:Bool;
	var num_players:Int;
	var next_recommend_sleep:Int;

	var next_spectator_frame:Int;
	var disconnect_timeout:Int;
	var disonnect_notify_start:Int;

	var local_connect_status:Array<ConnectStatus> = [];

	public function new(cb:Callbacks, game_name:String, num_players:Int, input_size:Int, networking:Networking<Handle>) {
		this.num_players = num_players;
		this.input_size = input_size;
		this.sync = new Sync(local_connect_status);
		this.disconnect_timeout = DEFAULT_DISCONNECT_TIMEOUT;
		this.disonnect_notify_start = DEFAULT_DISCONNECT_NOTIFY_START;
		this.callbacks = cb;
		this.synchronizing = true;
		this.next_recommend_sleep = 0;
		this.poll = new Poll(networking);
		sync.init({
			num_players: num_players,
			input_size: input_size,
			num_prediction_frames: MAX_PREDICTION_FRAMES,
			callbacks: callbacks
		});

		this.networking = new Datagram();
		this.networking.init(networking, (msg, handle) -> this.onMsg(handle, msg), poll);

		for (i in 0...num_players) {
			local_connect_status.push(new ConnectStatus(0));
			local_connect_status[i].frame = -1;
			endpoints.push(null);
		}

		callbacks.beginGame();
	}

	function addRemotePlayer(ip:String, port:Int, queue:Int) {
		synchronizing = true;
		endpoints[queue] = new DatagramProto(networking, poll, queue, ip, port, num_players, local_connect_status);
		endpoints[queue].setDisconnectTimeout(disconnect_timeout);
		endpoints[queue].setDisconnectNotifyStart(disonnect_notify_start);
		endpoints[queue].synchronize();
	}

	// todo addSpectator

	override function doPoll(timeout:Int) {
		if (!sync.inRollback()) {
			poll.pump(0);
			pollDatagramProtocolEvents();
			if (!synchronizing) {
				sync.checkSimulation(timeout);
				var current_frame = sync.getFrameCount();
				for (i in endpoints) {
					i.setLocalFrameNumber(current_frame);
				}

				var total_min_confirmed:Int = if (num_players <= 2) poll2Players(current_frame) else pollNPlayers(current_frame);
				Log.log('last confirmed frame in p2p backend is $total_min_confirmed');
				if (total_min_confirmed >= 0) {
					// todo spectactors
				}
				Log.log('setting confirmed frame in sync to $total_min_confirmed');
				sync.setLastConfirmedFrame(total_min_confirmed);

				if (current_frame > next_recommend_sleep) {
					var interval = 0;
					for (i in endpoints) {
						var linterval = i.recommendFrameDelay();
						interval = if (interval < linterval) linterval else interval;
					}

					if (interval > 0) {
						callbacks.onEvent(TIMESYNC(interval));
						next_recommend_sleep = current_frame + RECOMMENDATION_INTERVAL;
					}
				}
				if (timeout > 0) {
					// lie
				}
			}
		}
	}

	public function poll2Players(current_frame:Int):Int {
		var one = 1;
		var total_min_confirmed = one << 31;
		for (i in 0...num_players) {
			var queue_connected = true;
			if (endpoints[i].isRunning()) {
				queue_connected = !endpoints[i].getPeerConnectStatus(i).disconnected;
			}

			if (!local_connect_status[i].disconnected) {
				var last_frame = local_connect_status[i].frame;
				total_min_confirmed = if (total_min_confirmed < last_frame) total_min_confirmed else last_frame;
			}

			Log.log(' local endp: connected = ${!local_connect_status[i].disconnected}, last_received: ${local_connect_status[i].frame}, total_min_confirmed: ${total_min_confirmed}');
			if (!queue_connected && !local_connect_status[i].disconnected) {
				Log.log('disconnecting i $i by remote request');
				disconnectPlayerQueue(i, total_min_confirmed);
			}

			Log.log('total_min_confirmed = $total_min_confirmed');
		}
		return total_min_confirmed;
	}

	public function pollNPlayers(current_frame:Int):Int {
		throw new GGError(UNSUPPORTED);
		// TODO
	}

	public function addPlayer(player:Player):PlayerHandle {
		var queue = player.num - 1;
		if (player.num < 1 || player.num > num_players) {
			throw new GGError(PLAYER_OUT_OF_RANGE);
		}

		var res = queueToPlayerHandle(queue);

		switch (player.type) {
			case REMOTE(ip, port):
				addRemotePlayer(ip, port, queue);
			default:
				endpoints[queue] = new DatagramProto(null, poll, queue, null, null, 0, null);
		}

		return res;
	}

	public function addLocalInput(player:PlayerHandle, values:Bytes) {
		var input = new GameInput();
		if (sync.inRollback()) {
			throw new GGError(IN_ROLLBACK);
		}

		if (synchronizing) {
			throw new GGError(NOT_SYNCHRONIZED);
		}

		var queue = playerHandleToQueue(player);
		input.init(-1, values);

		if (!sync.addLocalInput(queue, input)) {
			throw new GGError(PREDICTION_THRESHOLD);
		}

		if (input.frame != -1) {
			Log.log('setting local connect status for local queue $queue to ${input.frame}');
			local_connect_status[queue].frame = input.frame;

			for (i in 0...num_players) {
				if (endpoints[i].isInitialized()) {
					endpoints[i].sendInput(input);
				}
			}
		}
	}

	public function syncInput():Vector<Null<Bytes>> {
		if (synchronizing) {
			throw new GGError(NOT_SYNCHRONIZED);
		}
		return sync.synchronizeInputs();
	}

	public override function incrementFrame() {
		Log.log('!!!!!!!!!!!!!!!!!!!End of frame (${sync.getFrameCount()})');
		sync.incrementFrame();
		doPoll(0);
		pollSyncEvents();
	}

	public function pollSyncEvents() {
		assert(sync.getEvent() == null); // no sync events used in GGPO
	}

	public function pollDatagramProtocolEvents() {
		for (i in 0...num_players) {
			var evt;
			while ((evt = endpoints[i].getEvent()) != null) {
				onDatagramProtocolPeerEvent(evt, i);
			}
			// todo spectators
		}
	}

	public function onDatagramProtocolPeerEvent(evt:Event, queue:Int) {
		onDatagramProtocolEvent(evt, queueToPlayerHandle(queue));
		switch (evt) {
			case Input(input):
				Log.log('handling input in $queue', input);
				var current_remote_frame = local_connect_status[queue].frame;
				var new_remote_frame = input.frame;
				Log.log('from:$current_remote_frame to $new_remote_frame');
				assert(current_remote_frame == -1 || new_remote_frame == (current_remote_frame + 1));

				var copy = new GameInput();
				copy.init(input.frame, input.bits.sub(0, input.size));
				sync.addRemoteInput(queue, copy);
				Log.log('setting remote connect status for queue $queue to ${input.frame}');
				local_connect_status[queue].frame = input.frame;
			case Disconnected:
				disconnectPlayer(queueToPlayerHandle(queue));
			default:
				// do nothing
		}
	}

	// todo spectator

	public function onDatagramProtocolEvent(evt:Event, handle:PlayerHandle) {
		switch (evt) {
			case Connected:
				callbacks.onEvent(CONNECTED_TO_PEER(handle));
			case Synchronizing(total, count):
				callbacks.onEvent(SYNCHRONIZING_WITH_PEER(handle, count, total));
			case Synchronized:
				callbacks.onEvent(SYNCHRONIZED_WITH_PEER(handle));
				checkInitialSync();
			case NetworkInterrupted(disconnect_timeout):
				callbacks.onEvent(CONNECTION_INTERRUPTED(handle, disconnect_timeout));
			case NetworkResumed:
				callbacks.onEvent(CONNECTION_RESUMED(handle));
			default:
				// do nothing
		}
	}

	public override function disconnectPlayer(player:PlayerHandle) {
		var queue = playerHandleToQueue(player);
		if (local_connect_status[queue].disconnected) {
			throw new GGError(PLAYER_DISCONNECTED);
		}

		if (!endpoints[queue].isInitialized()) {
			// assume this is the local player
			var current_frame = sync.getFrameCount();
			Log.log('disconnecting local player $queue at frame ${local_connect_status[queue].frame} by user request');

			for (i in 0...num_players) {
				if (endpoints[i].isInitialized()) {
					disconnectPlayerQueue(i, current_frame);
				}
			}
		} else {
			Log.log('disconnecting queue $queue at frame ${local_connect_status[queue].frame} by user request');
			disconnectPlayerQueue(queue, local_connect_status[queue].frame);
		}
	}

	public function disconnectPlayerQueue(queue:Int, syncto:Int) {
		var framecount = sync.getFrameCount();
		endpoints[queue].disconnect();

		Log.log('Changing queue $queue local connect status for last frame from ${local_connect_status[queue].frame} to $syncto on disconnect request (current: $framecount)');

		local_connect_status[queue].disconnected = true;
		local_connect_status[queue].frame = syncto;

		if (syncto < framecount) {
			Log.log('adjusting simulation to account for disconnect by $queue @$syncto');
			sync.adjustSimulation(syncto);
			Log.log('finished adjusting simulation');
		}

		callbacks.onEvent(DISCONNECTED_FROM_PEER(queueToPlayerHandle(queue)));
		checkInitialSync();
	}

	public function getNetworkStats(player:PlayerHandle):NetworkStats {
		var queue = playerHandleToQueue(player);

		return endpoints[queue].getNetworkStats();
	}

	public override function setFrameDelay(player:PlayerHandle, delay:Int) {
		sync.setFrameDelay(playerHandleToQueue(player), delay);
	}

	public override function setDisconnectTimeout(timeout:Int) {
		disconnect_timeout = timeout;
		for (ep in endpoints) {
			if (ep.isInitialized()) {
				ep.setDisconnectTimeout(timeout);
			}
		}
	}

	public override function setDisconnectNotifyStart(timeout:Int) {
		disonnect_notify_start = timeout;
		for (ep in endpoints) {
			if (ep.isInitialized()) {
				ep.setDisconnectNotifyStart(timeout);
			}
		}
	}

	function playerHandleToQueue(player:PlayerHandle):Int {
		var offset = player - 1;
		if (offset < 0 || offset >= num_players) {
			throw new GGError(INVALID_PLAYER_HANDLE);
		}
		return offset;
	}

	function onMsg(from:Handle, msg:Msg) {
		for (i in 0...num_players) {
			if (endpoints[i].handlesMsg(msg, from)) {
				endpoints[i].onMsg(msg);
			}
		}
		// todo spectators
	}

	function checkInitialSync() {
		if (synchronizing) {
			// check if we are synchronized
			for (i in 0...num_players) {
				if (endpoints[i].isInitialized() && !endpoints[i].isSynchronized() && !local_connect_status[i].disconnected) {
					return;
				}
			}
			// todo spectators
			callbacks.onEvent(RUNNING);
			synchronizing = false;
		}
	}

	public function queueToPlayerHandle(queue:Int):PlayerHandle {
		return queue + 1;
	}
}
