OSIS
====

Entity Component System architecture with networking support (for haxe).

Iteration from [ECS-Networking-Haxe](https://github.com/Dvergar/ECS-Networking-Haxe) with:

 * simpler code: less macros, less files, less layers
 * automatic & fine-grained serialization of components
 * more constraints on the system use (but might also morph into more flexible `entitySets`)
 * entity changes as events so that every system gets notified
 * YAML entities & components definition
