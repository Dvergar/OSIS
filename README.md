OSIS
====

Entity Component System architecture with networking support (for haxe).

Iteration from [ECS-Networking-Haxe](https://github.com/Dvergar/ECS-Networking-Haxe) with:

 * Simpler code: less macros, less files, less layers
 * Simple API
 * API support for shared code betwen client & server
 * Automatic & fine-grained serialization of components via [PODStream](https://github.com/Dvergar/PODStream)
 * More constraints on the system use (but might also morph into more flexibles `entitySets`)
 * Entity changes as events so that every system gets notified correctly
 * ~~YAML entities & components definition~~ _On Hold for now since it breaks with neko._
 
Check out [the sample](https://github.com/Dvergar/OSIS/tree/master/sample-openfl) for a quick overview of the architecture. The library assumes you are in a client/server architecture where the server is authoritative.
 
Components updates are always made from server to clients (not the opposite). Messages are the only type of network events that can go both ways. In a game, communications should sum up to the client sending a list of pressed keys and the server dispatching everything else.
 
I'm not comfortable in advertising OSIS until i spent enough time with the library, actually using it; in any case if you plan to fiddle with it don't hesitate to submit tickets.

**Limitations**

* Based on my network library [Anette](https://github.com/Dvergar/Anette) which is actually broken on the server websocket/JS target, OSIS is inheriting the same issue
* 32 components max, 32 systems max (will patch when reaching the limit myself :))
