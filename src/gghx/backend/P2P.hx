package gghx.backend;

import gghx.Sync.MAX_PREDICTION_FRAMES;
import gghx.network.DatagramMsg.ConnectStatus;
import gghx.network.DatagramProto;
import gghx.GGHX.Networking;
import gghx.GGHX.Callbacks;
import gghx.GGHX.Player;
import gghx.GGHX.PlayerHandle;
import haxe.io.Bytes;
import gghx.backend.Session.DisconnectFlags;
import gghx.GGHX.NetworkStats;

final RECOMMENDATION_INTERVAL = 240;
final DEFAULT_DISCONNECT_TIMEOUT = 5000;
final DEFAULT_DISCONNECT_NOTIFY_START = 750;

class P2P<Handle> extends Session {

    var callbacks: Callbacks;
	var poll: Poll<Handle>;
	var sync: Sync;
    var networking: Networking<Handle>;
	var endpoints: Array<DatagramProto<Handle>>;
	// TODO spectators
	var input_size: Int;

	var synchronizing: Bool;
	var num_players: Int;
	var next_recommend_sleep: Int;

	var next_spectator_frame: Int;
	var disconnect_timeout: Int;
	var disonnect_notify_start: Int;

	var local_connect_status: Array<ConnectStatus> = [];

	public function new(
		cb: Callbacks,
		gameName: String,
		num_players: Int,
		input_size: Int,
		networking: Networking<Handle>
		) {
		this.num_players = num_players;
		this.input_size = input_size;
		this.sync = new Sync(local_connect_status);
		this.disconnect_timeout = DEFAULT_DISCONNECT_TIMEOUT;
		this.disonnect_notify_start = DEFAULT_DISCONNECT_NOTIFY_START;
		this.callbacks = cb;
		this.synchronizing = true;
		this.next_recommend_sleep = 0;
		sync.init({
			num_players: num_players,
			input_size: input_size,
			num_prediction_frames: MAX_PREDICTION_FRAMES,
			callbacks: callbacks
		});

		this.networking = networking;

		for(i in 0...num_players) {
			local_connect_status.push(0);
			local_connect_status[i].frame = -1;
			endpoints.push(null);
		}

		callbacks.beginGame();
	}

	function addRemotePlayer(
		ip: String,
		port: Int,
		queue: Int
	) {
		synchronizing = true;
		endpoints[queue] = new DatagramProto(
			networking,
			poll,
			queue,
			ip,
			port,
			() -> local_connect_status[queue],
		);
		endpoints[queue].setDisconnectTimeout(disconnect_timeout);
		endpoints[queue].setDisconnectNotifyStart(disonnect_notify_start);
		endpoints[queue].synchronize();
	}
	// todo addSpectator

	// you left off here yesterday


	public function addPlayer(player:Player):PlayerHandle {
		throw new haxe.exceptions.NotImplementedException();
	}

	public function addLocalInput(player:PlayerHandle, values:Bytes) {}

	public function syncInput(values:Bytes):DisconnectFlags {
		throw new haxe.exceptions.NotImplementedException();
	}

	public function getNetworkStats(player:PlayerHandle):NetworkStats {
		throw new haxe.exceptions.NotImplementedException();
	}


}