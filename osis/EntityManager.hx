package osis;

import haxe.ds.IntMap;
import haxe.ds.Vector;
import haxe.Int64;
import haxe.io.BytesOutput;
import anette.Time;
import anette.Protocol;
import anette.Server;
import anette.Client;

using EntityManager.ArrayEntityExtender;
using EntityManager.BitSets;
using EntityManager.ComponentTypeExtender;
using EntityManager.EntityExtender;

/**
	Returned by event handler as the source of the event.
	It's basically used as an identifier and will probably used with :

	* `EntityManager.bindEntity`
	* `EntityManager.getBoundEntity`
**/
typedef Connection = anette.Connection;

@:dox(hide)
typedef ListSet<T> = Array<T>;

@:dox(hide)
class Entities {
	var store = new Map<Int, Entity>();

	public var reverse = new Map<Entity, Int>();

	public function new() {}

	public function set(entityId:Int, entity:Entity) {
		store.set(entityId, entity);
		reverse.set(entity, entityId);
	}

	public function get(entityId:Int)
		return store.get(entityId);

	public function remove(entityId:Int) {
		reverse.remove(store.get(entityId));
		store.remove(entityId);
	}

	public function iterator()
		return store.iterator();
}

@:dox(hide)
class Connections {
	var store = new Map<Entity, Connection>();

	public var reverse = new Map<Connection, Entity>();

	public function new() {}

	public function set(entity:Entity, connection:Connection) {
		store.set(entity, connection);
		reverse.set(connection, entity);
	}

	public function get(entity:Entity)
		return store.get(entity);

	public function remove(entity:Entity) {
		reverse.remove(store.get(entity));
		store.remove(entity);
	}

	public function iterator()
		return store.iterator();
}

@:dox(hide)
class ArrayEntityExtender {
	static public function has(arr:ListSet<Entity>, newItem:Entity):Bool {
		for (item in arr)
			if (item == newItem)
				return true;
		return false;
	}

	static public function set(arr:Array<Entity>, newItem:Entity):Bool {
		for (item in arr)
			if (item == newItem)
				return false;
		arr.push(newItem);
		return true;
	}
}

/**
	Helpers for entity manipulation,
	this is actually used like this :

	* `entity.add(CPosition);` *shortcut for* `entityManager.addComponent(entity, CPosition);`
	* `entity.remove(CDrawable)` *shortcut for* `entityManager.removeComponent(entity, CDrawable);`
	* `entity.destroy()` *shortcut for* `entityManager.destroyEntity(entity);`

	More on static extensions (https://haxe.org/manual/lf-static-extension.html)
**/
class EntityExtender {
	@:dox(hide) static public var em:EntityManager;

	static public inline function add<T:Component>(entity:Entity, component:T):T {
		em.addComponent(entity, component);
		return component;
	}

	static public inline function remove<T:Class<Component>>(entity:Entity, componentType:T) {
		em.removeComponent(entity, componentType);
	}

	static public inline function destroy(entity:Entity) {
		em.destroyEntity(entity);
	}
}

// NOT SUPER FOUND OF THIS

@:dox(hide)
class ComponentTypeExtender {
	static public function get__id<T:Component>(componentType:Class<T>):Int
		return (untyped componentType).__id;

	static public function get__sid<T:Component>(componentType:Class<T>):Int
		return (untyped componentType).__sid;
}

/**
	Interface for your components.

	usage :
	```
	class CPosition implements Component
	{
		@Short public var x:Int;
		@Short public var y:Int;

		public function new() {}
	}
	```

	Available network types are : `@Short`, `@Int`, `@Float`, `@Bool`, `@Byte`, `@String`.
	Variables will be serialized appropriately under the hood.

	More infos on (https://github.com/Dvergar/PODStream)
**/
#if !macro
@:autoBuild(osis.CustomNetworkTypes.build())
#end
interface Component {
	public var _sid:Int;
	public var _id:Int;
	@:dox(hide) public function unserialize(bi:haxe.io.BytesInput):Void;
	@:dox(hide) public function serialize(bo:haxe.io.BytesOutput):Void;
}

/**
	Interface for your messages.

	usage :
	```
	class MessageInput implements Message
	{
		@Short public var x:Int;
		@Short public var y:Int;
		@Bool public var left:Bool;
		@Bool public var right:Bool;
		@Bool public var up:Bool;
		@Bool public var down:Bool;

		public function new() {}
	}
	```

	Available network types are : `@Short`, `@Int`, `@Float`, `@Bool`, `@Byte`, `@String`.
	Variables will be serialized appropriately under the hood.

	More infos on (https://github.com/Dvergar/PODStream)
**/
#if !macro
@:autoBuild(osis.CustomNetworkTypes.build())
#end
interface Message {
	public var _sid:Int;
	public var _id:Int;
	@:dox(hide) public function unserialize(bi:haxe.io.BytesInput):Void;
	@:dox(hide) public function serialize(bo:haxe.io.BytesOutput):Void;
}

@:dox(hide)
class BitSets {
	inline public static function value(index:Int):Int64
		return Int64.shl(Int64.ofInt(1), index);

	inline public static function remove(bits:Int64, mask:Int):Int64
		return bits & ~value(mask);

	inline public static function add(bits:Int64, mask:Int):Int64
		return bits | value(mask);

	inline public static function xor(bits:Int64, mask:Int64):Int64
		return bits ^ mask;

	inline public static function contains(bits:Int64, mask:Int):Bool
		return bits & value(mask) != 0;

	inline public static function containsBitSet(bits:Int64, mask:Int64):Bool
		return (bits & mask) == bits;
}

@:dox(hide)
enum abstract CONSTANTS(Int) to Int {
	var MAX_COMPONENTS = 64;
}

class Entity {
	public var id:Int;

	static var ids:Int = 0;

	@:dox(hide) public var code:Int64 = 0;
	@:dox(hide) public var components:Vector<Component> = new Vector(MAX_COMPONENTS);
	@:dox(hide) public var remComponents:Vector<Bool> = new Vector(MAX_COMPONENTS);
	@:dox(hide) public var registeredSetsCode:Int64 = 0;

	// NET
	@:dox(hide) public var templateId:Int;

	/**
		Creates an entity.

		An entity is nothing but a holder for components.
	**/
	public function new() {
		this.id = ids++;
		for (i in 0...MAX_COMPONENTS)
			remComponents[i] = false;
	}

	/**
		Returns entity component.
	**/
	public function get<T:Component>(componentType:Class<T>):T {
		var comp:T = cast components[componentType.get__id()];
		if (comp == null)
			throw "Entity " + id + " doesn't have component " + componentType;
		return comp;
	}

	/**
		Tells if entity has this specific component.
	**/
	public function has<T:Component>(componentType:Class<T>):Bool {
		var comp:T = cast components[componentType.get__id()];
		if (comp == null)
			return false;
		return !remComponents[componentType.get__id()];
	}

	public function toString() {
		var entityString = "Entity : " + id;

		for (comp in components) {
			if (comp == null)
				continue;
			var className = Type.getClassName(Type.getClass(comp));
			entityString += " <" + className + ">";
		}

		return entityString;
	}
}

class System {
	public var em:EntityManager;
	public var net:NetEntityManager;

	/**
		Creates a system.

		A system is where all the logic goes.
		Systems acts on components via `Entityset`
	**/
	public function new() {}

	/**
		Called after initialization from the EntityManager.
		To be overridden.
	**/
	public function init() {}

	/**
		Where all your checks goes.
		To be overridden.
	**/
	public function loop() {}
}

/**
	Get an entity set via `EntityManager.getEntitySet`.
**/
class EntitySet {
	@:dox(hide) public var _id:Int;

	@:dox(hide) static var ids:Int = 0;

	@:dox(hide) public var code:Int64 = 0;

	var em:EntityManager;

	/**
		Container of all entities.
	**/
	public var entities:ListSet<Entity> = new ListSet();

	@:dox(hide) public var _adds:ListSet<Entity> = new ListSet();
	@:dox(hide) public var _changes:ListSet<Entity> = new ListSet();
	@:dox(hide) public var _removes:ListSet<Entity> = new ListSet();

	/**
		Container of all added entities.
	**/
	public var adds:ListSet<Entity> = new ListSet();

	/**
		Container of all changed entities.
	**/
	public var changes:ListSet<Entity> = new ListSet();

	/**
		Container of all removed entities.
	**/
	public var removes:ListSet<Entity> = new ListSet();

	@:dox(hide)
	public function new(em:EntityManager, componentTypeList:Array<Class<Component>>) {
		this._id = ids++;
		this.em = em;

		// SET ENTITYSET SIGNATURE VIA BITS
		for (componentType in componentTypeList)
			code = code.add(componentType.get__id());
	}

	/**
		Updates all the containers for adds/changes/removes.
		Needed for up to date manipulation via `markChanged`
	**/
	public function applyChanges() {
		for (e in _adds)
			entities.set(e);
		for (e in _removes)
			entities.remove(e);

		adds = _adds;
		changes = _changes;
		removes = _removes;

		_adds = new ListSet();
		_changes = new ListSet();
		_removes = new ListSet();
	}

	/**
		Notify the `EntityManager` that you modified a specific component.
		Will dispatch events to all the other systems.

		*Only local, won't dispatch through the network.*
	**/
	public function markChanged<T:Component>(entity:Entity, component:T) {
		em.markChanged(entity, component, this);
	}
}

@:dox(hide) class Template {
	public static var ids:Int = 0;

	public var id:Int;
	public var name:String;
	public var func:Void->Entity;
	public var code:Int64 = 0;

	public function new(name:String, func:Void->Entity) {
		this.id = Template.ids++;
		this.name = name;
		this.func = func;
	}
}

@:dox(hide) class TemplateStore {
	public var byName:Map<String, Template> = new Map();
	public var byId:Array<Template> = new Array();

	public function new() {}

	public function add(name:String, func:Void->Entity) {
		var template = new Template(name, func);
		byName.set(name, template);
		byId[template.id] = template;

		// GET TEMPLATE CODE (used for network deltas)
		var entity:Entity = func();
		template.code = entity.code;
		entity.destroy();
	}

	public function getByName(name:String) {
		var template = byName.get(name);
		if (template == null)
			throw 'Template $name doesn\'t exists';
		return template;
	}

	public function getById(id:Int)
		return byId[id];
}

@:dox(hide) typedef ComponentDestroyData = {entity:Entity, componentId:Int};

class EntityManager {
	var systems:Array<System> = new Array();
	var entitySets:Array<EntitySet> = new Array();
	var componentsToDestroy:Array<ComponentDestroyData> = new Array();

	@:dox(hide) public var templateStore:TemplateStore = new TemplateStore();
	@:dox(hide) public var net:NetEntityManager;

	public function new() {
		EntityExtender.em = this;
		this.net = new NetEntityManager(this);
	}

	/**
		Returns an `EntitySet` of components specified by `componentTypeList`.

		Example : `var itemsEntitySet = getEntitySet([CItem, CPosition])`
	**/
	public function getEntitySet(componentTypeList:Array<Class<Component>>):EntitySet {
		var entitySet = new EntitySet(this, componentTypeList);
		entitySets.push(entitySet);
		return entitySet;
	}

	/**
		If `name` is specified, returns a template `Entity`.
		A template entity is a composition of components and is added
		via `EntityManager.addTemplate`.

		If `name` isn't specified, returns an `Entity` as a mere holder and without any component.
	**/
	public function createEntity(?name:String):Entity {
		// TEMPLATE ENTITY
		if (name != null)
			return templateStore.getByName(name).func();

		return new Entity();
	}

	/**
		Adds a template of name `name`, which is built and returned
		by a function `func`.
	**/
	public function addTemplate(name:String, func:Void->Entity)
		templateStore.add(name, func);

	/**
		Destroys an entity, **change is not immediate !** the event is dispatched
		only at next loop.

		Each system should be able to process every entity change before its destruction.
		Don't assume that systems are running in order (even though it might be necessary in some
		corner cases such as keeping determinism).
	**/
	public function destroyEntity(entity:Entity) {
		for (component in entity.components)
			if (component != null)
				_removeComponentInstance(entity, component);

		if (net.entities.get(entity.id) == entity)
			net.entities.remove(entity.id);
	}

	public function addComponent<T:Component>(entity:Entity, component:T):T {
		entity.components[component._id] = component;
		entity.code = entity.code.add(component._id);

		for (entitySet in entitySets) {
			if (entitySet.code.containsBitSet(entity.code)) {
				var idCode = Int64.ofInt(0).add(entitySet._id);

				// SKIP IF addComponent is called from that very entitySet...
				if (idCode.containsBitSet(entity.registeredSetsCode))
					continue;

				entitySet._adds.set(entity);
				entity.registeredSetsCode = entity.registeredSetsCode.add(entitySet._id);
			}
		}

		return component;
	}

	@:allow(osis.NetEntityManager)
	inline function _removeComponentInstance<T:Component>(entity:Entity, component:T) {
		_removeComponent(entity, component._id);
	}

	public function removeComponent<T:Class<Component>>(entity:Entity, componentType:T) {
		_removeComponent(entity, componentType.get__id());
	}

	inline function _removeComponent(entity:Entity, componentId:Int) {
		entity.code = entity.code.remove(componentId);

		for (entitySet in entitySets) {
			if (!entitySet.code.containsBitSet(entity.code)) {
				var idCode = Int64.ofInt(0).add(entitySet._id);
				if (!idCode.containsBitSet(entity.registeredSetsCode))
					continue;

				entitySet._removes.set(entity);
				// entitySet._changes.remove(entity);
				entity.registeredSetsCode = entity.registeredSetsCode.remove(entitySet._id);
			}
		}

		entity.remComponents[componentId] = true;
		componentsToDestroy.push({entity: entity, componentId: componentId});
	}

	public function getComponent<T:Component>(entity:Entity, componentType:Class<T>):T {
		return entity.get(componentType);
	}

	/**
		Adds a system to the `EntityManager`.
	**/
	public function addSystem<T:System>(system:T) {
		system.em = this;
		system.net = this.net;
		system.init();
		systems.push(system);

		return system;
	}

	/**
		Updates each `System` (`System.loop` call) and should be called from your game loop.
	**/
	public function processAllSystems() {
		for (system in systems)
			system.loop();

		for (_ in componentsToDestroy) {
			_.entity.components[_.componentId] = null;
			_.entity.remComponents[_.componentId] = false;
		}

		componentsToDestroy = new Array();
	}

	// FIXED UPDATE
	public var skipTicks:Float = 1 / 60;
	public var maxFrameSkip:Int = 100;

	/**
		Rate at which network data is processed.
	**/
	public var netfps:Int = 30;

	// INIT
	var loops:Int = 0;
	var nextGameTick:Float = Time.now();
	var lastNetTick:Float = Time.now();

	public function fixedUpdate(func:Void->Void) {
		if ((Time.now() - lastNetTick) > (1 / netfps)) {
			net.pump();
			lastNetTick = Time.now();
		}

		loops = 0;
		while (Time.now() > nextGameTick && loops < maxFrameSkip) {
			func();
			nextGameTick += skipTicks;
			loops++;
		}

		if (loops > maxFrameSkip)
			throw "out of fixed timestep";
	}

	/**
		Notify the `EntityManager` that you modified a specific component.
		Will dispatch events to all the other systems.

		Won't dispatch through the network (use `NetEntityManager.markChanged` for that).

		if `entitySet` is specified, will not notify that very `EntitySet`.
		Prevents circular notification.
	**/
	public function markChanged<T:Component>(entity:Entity, component:T, ?filterEntitySet:EntitySet) {
		for (entitySet in entitySets)
			if (entity.registeredSetsCode.contains(entitySet._id))
				if (entitySet.code.contains(component._id)) {
					if (entitySet == filterEntitySet)
						continue;
					entitySet._changes.set(entity);
				}
	}

	// NET HELPERS

	#if client
	/**
		Connect to ip `address` on port `port` and returns an `NetEntityManager`.
	**/
	public function connect(address:String, port:Int):NetEntityManager {
		net.connect(address, port);
		return net;
	}
	#end

	#if server
	/**
		Listen to ip `address` on port `port` and returns an `NetEntityManager`.
	**/
	public function listen(address:String, port:Int):NetEntityManager {
		net.listen(address, port);
		return net;
	}
	#end

	static function main() {
		trace("Haxe is great!");
	}
}

@:dox(hide)
class Net {
	public var onConnection:Connection->Void;
	public var onDisconnection:Connection->Void;

	#if server
	public var socket:Server;

	@:allow(osis.EntityManager)
	function listen(address:String, port:Int) {
		socket = new Server(address, port);
		socket.protocol = new Prefixed();
		socket.onData = onData;
		socket.onConnection = _onConnection;
		socket.onDisconnection = _onDisconnection;
		return socket;
	}
	#elseif client
	public var socket:Client;

	@:allow(osis.EntityManager)
	function connect(address:String, port:Int) {
		socket = new Client();
		socket.protocol = new Prefixed();
		socket.onData = onData;
		socket.onConnection = _onConnection;
		socket.onDisconnection = _onDisconnection;
		socket.connect(address, port);
	}
	#end

	function _onConnection(connection:Connection) {
		if (onConnection == null)
			trace("Client connected: you should probably bind" + "the onConnection function");
		else
			onConnection(connection);
	}

	function _onDisconnection(connection:Connection) {
		if (onDisconnection == null)
			trace("Client disconnected: you should probably bind" + " the onDisconnection function");
		else
			onDisconnection(connection);
	}

	function onData(connection:Connection) {
		// OVERRIDDEN BY NETENTITYMANAGER
	}
}

@:dox(hide)
class EventContainer {
	public var message:Message;
	public var func:Message->Connection->Void;

	public function new() {}
}

@:dox(hide)
enum abstract NETWORK_ORDER(Int) from Int to Int {
	var CREATE_ENTITY;
	var CREATE_TEMPLATE_ENTITY;
	var ADD_COMPONENT;
	var UPDATE_COMPONENT;
	var REMOVE_COMPONENT;
	var DESTROY_ENTITY;
	var EVENT;
}

/**
	Available via `EntityManager.listen` on server or `EntityManager.connect` on client.

	`NetEntityManager` is basically mirroring `EntityManager` but each call
	will be done locally AND through the network.
**/
class NetEntityManager extends Net {
	var em:EntityManager;
	var serializableTypes:Vector<Class<Component>> = new Vector(MAX_COMPONENTS); // SERIALIZED SPECIFIC IDS
	var allTypes:Vector<Class<Component>> = new Vector(MAX_COMPONENTS); // ALL COMPONENTS IDS
	var eventListeners:IntMap<EventContainer> = new IntMap();

	@:dox(hide) public var entities = new Entities(); // MAPS SERVER>CLIENT IDS

	@:dox(hide) public static var instance:NetEntityManager; // USED BY CUSTOMNETWORKTYPES FOR ENTITY (MEH)

	@:dox(hide)
	public function new(em:EntityManager) {
		instance = this;
		this.em = em;

		// RESOLVE COMPONENT TYPES FROM STRING (MACRO)
		var serializables = podstream.SerializerMacro.getSerialized();

		// COMPONENTS AND NET SERIALIZABLE COMPONENTS
		var numComponents = 0;
		var numNetComponents = 0;
		for (serializable in serializables) {
			if (serializable == null)
				continue; // Shouldn't be in the array in the first place !??
			var componentType:Class<Component> = cast Type.resolveClass(serializable);

			// NETWORKED COMPONENTS
			var componentNetId = componentType.get__sid();
			if (componentNetId != -1) {
				numNetComponents++;
				serializableTypes[componentNetId] = componentType;
			}

			// ALL COMPONENTS
			numComponents++;
			var componentId = componentType.get__id();
			allTypes[componentId] = componentType;
		}

		trace("Components total : " + numComponents + "/" + MAX_COMPONENTS);
		trace("Net components total : " + numNetComponents + "/" + MAX_COMPONENTS);
	}

	//////////////// SERVER //////////////
	#if server
	@:dox(hide) public var connections:Connections = new Connections();

	/**
		Links `connection` to `entity`.
		The linked `entity` will be destroyed on disconnection.
	**/
	public function bindEntity(connection:Connection, entity:Entity)
		connections.set(entity, connection);

	/**
		Get `entity` registered via `bindEntity`.
	**/
	public function getBoundEntity(connection:Connection)
		return connections.reverse.get(connection);

	/**
		Create an entity of template `name` locally AND on the network.
	**/
	public function createEntity(name:String):Entity
		return sendFactoryEntity(name, em.createEntity(name));

	function sendFactoryEntity(name:String, entity:Entity):Entity {
		// trace("sendEntity " + name); // DEBUG
		entity.templateId = em.templateStore.getByName(name).id;

		// SEND
		for (connection in socket.connections) {
			sendCreate(connection.output, entity);
			sendDeltas(connection, entity);
		}

		entities.set(entity.id, entity);

		return entity;
	}

	// public function sendEntity(entity:Entity):Entity
	// {
	//     for(connection in socket.connections)
	//     {
	//         sendCreate(connection.output, entity);
	//         for(pos in 0...32)
	//         {
	//             if( (entity.code & 1 << pos) != 0)
	//             {
	//                 if(entity.components[pos]._sid == -1) continue;
	//                 sendAddComponent(entity.id, entity.components[pos], connection);
	//             }
	//         }
	//     }
	//     entities.set(entity.id, entity);
	//     return entity;
	// }

	function sendCreate(output:BytesOutput, entity:Entity):Void {
		output.writeInt8(CREATE_TEMPLATE_ENTITY);
		output.writeInt16(entity.id);
		output.writeInt8(entity.templateId);
	}

	/**
		Destroy an entity locally AND on the network.
	**/
	public function destroyEntity(entity:Entity):Void {
		for (connection in socket.connections) {
			connection.output.writeInt8(DESTROY_ENTITY);
			connection.output.writeInt16(entity.id);
		}

		entity.destroy();

		// CLEANUP
		connections.remove(entity);
	}

	inline function sendAddComponent<T:Component>(entityId:Int, component:T, output:BytesOutput):T {
		output.writeInt8(ADD_COMPONENT);
		output.writeInt16(entityId);
		output.writeInt8(component._sid);
		component.serialize(output);

		return component;
	}

	/**
		Add an component locally AND on the network.
	**/
	public function addComponent<T:Component>(entity:Entity, component:T):T {
		for (connection in socket.connections)
			sendAddComponent(entity.id, component, connection.output);

		entity.add(component);
		return component;
	}

	/**
		Add an component locally AND on the network at the
		specified connection linked to `connEntity`.
	**/
	public function addComponentTo<T:Component>(entity:Entity, component:T, connEntity:Entity):T {
		return sendAddComponent(entity.id, component, connections.get(connEntity).output);
	}

	inline function sendRemoveComponent(entityId:Int, componentId:Int, output:BytesOutput) {
		output.writeInt8(REMOVE_COMPONENT);
		output.writeInt16(entityId);
		output.writeInt8(componentId);
	}

	/**
		Remove a component locally AND on the network.
	**/
	public function removeComponent<T:Class<Component>>(entity:Entity, componentType:T) {
		for (connection in socket.connections)
			sendRemoveComponent(entity.id, componentType.get__sid(), connection.output);
		entity.remove(componentType);
	}

	/**
		Send all the server entities to `connection`.
	**/
	public function sendWorldStateTo(connection:Connection) {
		var connectionEntity = connections.reverse.get(connection);
		if (connectionEntity == null)
			throw "Connection has to have a bound entity";

		for (entity in entities) {
			if (entity == connectionEntity)
				continue;

			sendCreate(connection.output, entity);
			sendDeltas(connection, entity);
		}
	}

	function sendDeltas(connection:Connection, entity:Entity) {
		var templateCode = em.templateStore.getById(entity.templateId).code;
		var deltaCode = entity.code.xor(templateCode);

		for (componentId in 0...MAX_COMPONENTS) {
			// CHECK IF COMPONENT REMOVED FROM TEMPLATE
			if (deltaCode.contains(componentId)) // CHANGE
			{
				if (entity.code.contains(componentId)) // ADD
				{
					// // Reflect until i find something cleaner (with podstream)
					// if(Reflect.field(entity.components[pos], "_sid") == null)
					//     continue;
					// sendAddComponent(entity.id, cast entity.components[pos], connection);
				} else {
					var sid = (cast allTypes[componentId]).__sid;
					if (sid == -1)
						continue; // NOT NETWORKED
					sendRemoveComponent(entity.id, sid, connection.output);
				}
			}

			// SEND ENTITY COMPONENT VALUES
			if (entity.code.contains(componentId)) {
				if (entity.components[componentId]._sid == -1)
					continue;
				sendAddComponent(entity.id, entity.components[componentId], connection.output);
			}
		}
	}

	/**
		Notify the `EntityManager` that you modified a specific component.
		Will dispatch events to all the other systems.

		Will also dispatch through the network.

		if `entitySet` is specified, will not notify that very `EntitySet`.
		Prevents circular notification.
	**/
	public function markChanged<T:Component>(entity:Entity, component:T, ?entitySet:EntitySet) {
		if (component._sid == -1)
			throw 'Component $component is not serializable';

		em.markChanged(entity, component, entitySet);

		for (connection in socket.connections) {
			connection.output.writeInt8(UPDATE_COMPONENT);
			connection.output.writeInt16(entity.id);
			connection.output.writeInt8(component._sid);
			component.serialize(connection.output);
		}
	}

	override function onData(connection:Connection) {
		while (connection.input.mark - connection.input.position > 0) {
			var msgtype = connection.input.readInt8();
			if (msgtype == EVENT) {
				var messageTypeId = connection.input.readInt8();
				receiveEvent(messageTypeId, connection);
			}
		}
	}
	#end

	/// COMMON ///

	function receiveEvent(messageTypeId:Int, connection:Connection) {
		var eventContainer:EventContainer = eventListeners.get(messageTypeId);
		if (eventContainer == null)
			throw("No event  registered for " + messageTypeId);
		eventContainer.message.unserialize(connection.input);
		eventContainer.func(eventContainer.message, connection);
	}

	/**
		Send event `message` on the network to everyone or only to `connection` if specified.
	**/
	public function sendEvent(message:Message, ?connection:Connection) {
		#if server
		if (connection != null)
			_sendEvent(connection.output, message);
		else
			for (connection in socket.connections)
				_sendEvent(connection.output, message);
		#end

		#if client
		_sendEvent(socket.connection.output, message);
		#end
	}

	inline function _sendEvent(output:BytesOutput, message:Message) {
		output.writeInt8(EVENT);
		output.writeInt8(message._sid);
		message.serialize(output);
	}

	/**
		Link an event `messageClass` to a `func`.

		Usage :

		```
		class MessageHello implements Message
		{
			@String public var txt:String;

			public function new() {}
		}

		netEntityManager.addEvent(MessageHello, function(msg:MessageHello, connection:Connection) {
			trace(msg.txt);
		});
		```
	**/
	public function addEvent<T:Message>(messageClass:Class<Message>, func:T->Connection->Void) {
		var event = new EventContainer();
		event.message = Type.createInstance(messageClass, []);
		event.func = cast func;

		eventListeners.set(event.message._sid, event);
	}

	//////////////// CLIENT //////////////
	#if client
	override function onData(connection:Connection) {
		while (connection.input.mark - connection.input.position > 0) {
			var msgtype:NETWORK_ORDER = connection.input.readInt8();

			switch (msgtype) {
				case CREATE_ENTITY:
					var entityId = connection.input.readInt16();
					trace("CREATE_ENTITY " + entityId);
					var entity = em.createEntity();
					entities.set(entityId, entity);

				case DESTROY_ENTITY:
					var entityId = connection.input.readInt16();
					trace("DESTROY_ENTITY " + entityId);
					var entity = entities.get(entityId);
					entities.remove(entityId);
					entity.destroy();

				case ADD_COMPONENT:
					var entityId = connection.input.readInt16();
					var entity = entities.get(entityId);
					var componentTypeId = connection.input.readInt8();
					// trace("ADD_COMPONENT " + componentTypeId); // DEBUG
					var componentType:Class<Component> = cast serializableTypes[componentTypeId];
					var component:Component = Type.createInstance(componentType, []);
					component.unserialize(connection.input);
					entity.add(component);

				case REMOVE_COMPONENT:
					var entityId = connection.input.readInt16();
					var componentTypeId = connection.input.readInt8();
					var componentType:Class<Component> = cast serializableTypes[componentTypeId];
					trace("REMOVE_COMPONENT " + untyped (componentType));
					var entity = entities.get(entityId);
					var component = entity.get(componentType);
					em._removeComponentInstance(entity, component);

				case UPDATE_COMPONENT:
					var entityId = connection.input.readInt16();
					var componentTypeId = connection.input.readInt8();
					var componentType:Class<Component> = cast serializableTypes[componentTypeId];
					var entity = entities.get(entityId);
					// trace("UPDATE_COMPONENT ID " + componentTypeId);
					// trace("UPDATE_COMPONENT " + untyped(componentType));

					if (entity != null) {
						var component = entity.get(componentType);
						component.unserialize(connection.input);
						em.markChanged(entity, component);
					} else {
						trace("COMPONENT_UPDATE received but the entity doesn't exist anymore, skipping");
					}

				case EVENT:
					// trace("EVENT");
					var messageTypeId = connection.input.readInt8();
					receiveEvent(messageTypeId, connection);

				case CREATE_TEMPLATE_ENTITY:
					var entityId = connection.input.readInt16();
					// trace("CREATE_TEMPLATE_ENTITY " + entityId); // DEBUG
					var templateId = connection.input.readInt8();
					var entity = em.templateStore.getById(templateId).func();
					entities.set(entityId, entity);
			}
		}
	}

	@:dox(hide)
	public function markChanged<T:Component>(entity:Entity, component:T, ?entitySet:EntitySet) {
		// DUMMY, ACTUALLY USED FOR SERVER TO PREVENT ISSUES
		// WHEN SHARING SAME SYSTEM BETWEEN CLIENT & SERVER
	}
	#end

	@:allow(osis.EntityManager)
	function pump() {
		if (socket != null) {
			socket.pump();
			socket.flush();
		}
	}
}
