# A port of GGPO to haxe

GGHX is mostly 1:1 port of [GGPO](https://github.com/pond3r/ggpo), A P2P rollback netcode library designed for fighting games, to Haxe. Still heavily WIP, but it should be usable if you willing to deal 
with some bugs and breaking changes - it still is probably less work than starting from scratch. The sole dependency is hxbit

Just like GGPO, GGHX shares the same limitations.
- The game can only start once all players have joined, the initial state must be consistent between all players without any, communication.
- Since this is a P2P library, you will need some form of UDP hole punching or a forwarding server for non-local multiplayer.
- There is no interpolation done, so you need low ping to have a good experience (dropped inputs at ~280ms ping by default).

GGHX also has further limitation due to me not implementing these features yet.
- Only 2 players (needs PollNPlayers in P2P.hx)
- Spectators do not work (`// TODO spectators`)
- No SyncTest (needs SyncTestBackend)
- no meaningful Encapsulation

Unlike GGPO, this library does not use a C struct for serialization, and does not implement low-level networking, meaning it should be fully cross-platform. (did not test)
Since low-level networking features are left to the user, the library should work on most haxe targets.

## Basic usage:

You need the following capabilities for the library to work.
- Copy your game state into a haxe.io.Bytes object.
- Recall that game state from the same Bytes object. (Eventually this could just become a need to create a copy in any shape)
- Run your games simulation frame-by-frame without affecting your rendering, all within the time of a single frame. (by default up to 8 times per frame)
- Ideally run your game simulation at 60UPS - it is hardcoded in at [least one place in GGPO](https://github.com/pond3r/ggpo/blob/master/src/lib/ggpo/network/udp_proto.cpp#L683), possibly more.
- A non-blocking way to send datagrams over IP (generally UDP, websockets should also be possible, will test in the future)
- A way to pack your inputs into a Bytes object - there is a BitHelpers module in gghx which may be of use.

From a code perspective, you need to implement two interfaces:
  - `Networking`
    - See [PyNetworking](https://github.com/lavirlifiliol/gghx/blob/master/examples/python/src/PyNetworking.hx)
  - `Callbacks`
    - See the [GGPO dev guide](https://github.com/pond3r/ggpo/blob/master/doc/DeveloperGuide.md) for an explanation of each callback

and call the following public functions at appropriate times, once again, see the dev guide and the example. (TODO more comments in the example)

It is possible to enable logging via -D gghx_log - this creates a large number of logs (expect hundreds of MB for a short testing run). It can however help with debugging the library.

### Mapping from GGPO public API to GGHX public API

| GGPO API | GGHX API | note |
|----------|----------|------|
| GGPOSessionCallbacks | Callbacks | Using an interface rather than function pointers | 
| GGPOSession | Session | |
| ggponet_start_session | startSession | also needs the Networking object |
| ggpo_close_session | TODO | |
| ggpo_add_player | Session.addPlayer | |
| ggpo_add_local_input | Session.addLocalInput | |
| ggpo_synchronize_inputs | Sesssion.syncInput | rather than disconnect flags, if you get null instead of bytes, that means the player disconnected - GGPO would pass you all 0 in the input |
| ggpo_advance_frame | Session.incrementFrame | |
| ggpo_idle | Session.doPoll | The timeout argument is mostly ignored, will be removed in the future |