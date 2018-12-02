SISO
====

Entity Component System architecture with networking support (for haxe).

 * Simple API
 * Simple source
 * API support for shared code betwen client & server
 * Automatic & fine-grained serialization of components via [PODStream](https://github.com/Dvergar/PODStream)
 * Avoids magic !
 * Entity changes as events so that every system gets notified correctly
 * ~~YAML entities & components definition~~ _On Hold for now._

(Iteration from old [ECS-Networking-Haxe](https://github.com/Dvergar/ECS-Networking-Haxe))
 
Check out [the sample](https://github.com/Dvergar/SISO/tree/master/sample-openfl) for a quick overview of the architecture. The library assumes you are in a client/server architecture where the server is authoritative.
 
Components updates are always made from server to clients (not the opposite) and only at your demand. Messages are the only type of network events that can go both ways. In a game w/ this framework, communications should sum up to the client sending a list of pressed keys and/or events and the server dispatching everything else.
 
I'm not comfortable in advertising SISO until i spend enough time using the library; in any case if you plan to fiddle with it don't hesitate to submit tickets.

**Limitations**

* Based on my network library [Anette](https://github.com/Dvergar/Anette) which is actually broken on the server websocket/JS target, SISO is inheriting the same issue
* 32 components max, 32 systems max (will patch when reaching the limit myself :))
