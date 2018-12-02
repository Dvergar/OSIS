package osis;

import haxe.ds.IntMap;
import haxe.ds.Vector;
import haxe.macro.Expr;
import haxe.macro.Context;

import anette.*;
import anette.Protocol;
import anette.Bytes;

using EntityManager.ArrayEntityExtender;

typedef Connection = anette.Connection;
typedef ListSet<T> = Array<T>;


class ArrayEntityExtender
{
    static public function has(arr:ListSet<Entity>, newItem:Entity):Bool
    {
        for(item in arr) if(item == newItem) return true;
        return false;
    }
    static public function set(arr:Array<Entity>, newItem:Entity):Bool
    {
        for(item in arr) if(item == newItem) return false;
        arr.push(newItem);
        return true;
    }
}


class EntityExtender
{
    static public var em:EntityManager;
    static public inline function add<T:Component>(entity:Entity, component:T):T
    {
        em.addComponent(entity, component);
        return component;
    }

    static public inline function remove<T:Class<Component>>(entity:Entity, componentType:T)
    {
        em.removeComponent(entity, componentType);
    }

    static public inline function destroy(entity:Entity)
    {
        em.destroyEntity(entity);
    }
}


@:autoBuild(osis.CustomNetworkTypes.build())
interface Component
{
    public var _sid:Int;
    public var _id:Int;
    public function unserialize(bi:haxe.io.BytesInput):Void;
    public function serialize(bo:haxe.io.BytesOutput):Void;
}


@:autoBuild(podstream.SerializerMacro.build())
interface IMessage
{
    public var _sid:Int;
    public var _id:Int;
    public function unserialize(bi:haxe.io.BytesInput):Void;
    public function serialize(bo:haxe.io.BytesOutput):Void;
}


class Entity
{
    public var id:Int;
    static var ids:Int = 0;
    public var code:Int = 0;
    public var components:Vector<Component> = new Vector(32);
    public var remComponents:Vector<Bool> = new Vector(32);
    public var registeredSetsCode:Int = 0;

    // NET
    public var templateId:Int;
    #if client
    public var netId:Int;
    #end

    public function new()
    {
        this.id = ids++;
        for(i in 0...32) remComponents[i] = false; // Neko, hehe :|
        // trace("ENTITY ID " + id); // DEBUG
    }

    public function get<T:Component>(componentType:Class<T>):T
    {
        var comp:T = cast components[(untyped componentType).__id];
        if(comp == null)
            throw "Entity " + id + " doesn't have component " + componentType;
        return comp;
    }

    public function has<T:Component>(componentType:Class<T>):Bool
    {
        var comp:T = cast components[(untyped componentType).__id];
        if(comp == null) return false;

        return !remComponents[(untyped componentType).__id];
    }

    public function toString()
    {
        var entityString = "Entity : " + id;

        for(comp in components)
        {
            if(comp == null) continue;
            var className = Type.getClassName(Type.getClass(comp));
            entityString += " <" + className + ">";
        }

        return entityString;
    }
}


class System
{
    public var em:EntityManager;
    public var net:NetEntityManager;

    public function new() {}
    public function init() {}
    public function loop() {}
}


class EntitySet
{
    public var _id:Int;
    static var ids:Int = 0;
    public var code:Int = 0;
    public var em:EntityManager;
    public var entities:ListSet<Entity> = new ListSet();

    public var _adds:ListSet<Entity> = new ListSet();
    public var _changes:ListSet<Entity> = new ListSet();
    public var _removes:ListSet<Entity> = new ListSet();

    public var adds:ListSet<Entity> = new ListSet();
    public var changes:ListSet<Entity> = new ListSet();
    public var removes:ListSet<Entity> = new ListSet();

    public function new(em:EntityManager, componentTypeList:Array<Class<Component>>)
    {
        this._id = ids++;
        this.em = em;

        for(componentType in componentTypeList)
        {
            // trace("Systemcode " + code); // DEBUG
            // trace((untyped componentType).__id); // DEBUG
            // trace("Adding component ID :"); // DEBUG
            // trace((untyped componentType).__id); // DEBUG
            code = code | (1 << (untyped componentType).__id);
        }
    }

    public function applyChanges()
    {
        adds = _adds;
        changes = _changes;
        removes = _removes;

        _adds = new ListSet();
        _changes = new ListSet();
        _removes = new ListSet();
    }

    public function markChanged<T:Component>(entity:Entity, component:T)
    {
        em.markChanged(entity, component, this);
    }
}


class Template
{
    public static var ids:Int = 0;
    public var id:Int;
    public var name:String;
    public var func:Void->Entity;
    public var code:Int;

    public function new()
    {
        this.id = Template.ids++;
    }
}


typedef ComponentDestroy = {entity:Entity, componentId:Int};

#if !macro
// YAML
// @:build(osis.yec.Builder.build())
#end
class EntityManager
{
    var systems:Array<System> = new Array();
    var entitySets:IntMap<EntitySet> = new IntMap(); // Why not array?
    var componentsToDestroy:Array<ComponentDestroy> = new Array();

    public var net:NetEntityManager;
    // var self:EntityManager;  // YAML

    public function new()
    {
        EntityExtender.em = this;
        this.net = new NetEntityManager(this);
        // this.self = this;  // YAML
    }

    public function getEntitySet(componentTypeList:Array<Class<Component>>):EntitySet
    {
        var entitySet = new EntitySet(this, componentTypeList);
        entitySets.set(entitySet._id, entitySet);
        return entitySet;
    }

    public function createEntity():Entity
    {
        return new Entity();
    }

    public function destroyEntity(entity:Entity)
    {
        for(component in entity.components)
            if(component != null)
                _removeComponentInstance(entity, component);

        if(net.entities.get(entity.id) == entity)
        {
            trace("NETWORKED ENTITY DESTROYED");
            net.entities.remove(entity.id);
        }

        trace("ENTITY DESTROYED");
    }

    public function addComponent<T:Component>(entity:Entity, component:T):T
    {
        entity.components[component._id] = component;
        entity.code = entity.code | (1 << component._id);

        for(entitySet in entitySets)
        {
            if( (entitySet.code & entity.code) == entitySet.code )
            {
                // IF addComponent is called from that very entitySet...
                var idCode = 0 | (1 << entitySet._id);
                if( (entity.registeredSetsCode & idCode) == idCode)
                {
                    continue;
                }

                entitySet.entities.set(entity);
                entitySet._adds.set(entity);
                entity.registeredSetsCode = entity.registeredSetsCode | (1 << entitySet._id);
            }
        }

        return component;
    }

    @:allow(osis.NetEntityManager)
    inline function _removeComponentInstance<T:Component>(entity:Entity, component:T)
    {
        _removeComponent(entity, component._id);
    }

    public function removeComponent<T:Class<Component>>(entity:Entity, componentType:T)
    {
        _removeComponent(entity, (untyped componentType).__id);
    }

    inline function _removeComponent(entity:Entity, componentId:Int)
    {
        entity.code = entity.code & ~(1 << componentId);
        for(entitySet in entitySets)
        {
            if( (entitySet.code & entity.code) != entitySet.code)
            {
                var idCode = 0 | (1 << entitySet._id);
                if( (entity.registeredSetsCode & idCode) != idCode)
                    continue;

                entitySet._removes.set(entity);
                entitySet.entities.remove(entity);
                entitySet._changes.remove(entity);
                entity.registeredSetsCode = entity.registeredSetsCode & ~(1 << entitySet._id);
            }
        }
        
        entity.remComponents[componentId] = true;
        componentsToDestroy.push({entity:entity, componentId:componentId});  // TEMPORARY, hopefully
    }

    public function getComponent<T:Component>(entity:Entity, componentType:Class<T>):T
    {
        return entity.get(componentType);
    }

    public function addSystem<T:System>(system:T)
    {
        system.em = this;
        system.net = this.net;
        system.init();
        systems.push(system);

        return system;
    }

    public function processAllSystems()
    {
        for(system in systems) system.loop();

        for(_ in componentsToDestroy)
        {
            _.entity.components[_.componentId] = null;
            _.entity.remComponents[_.componentId] = false;
        }

        componentsToDestroy = new Array();
    }

    // FIXED UPDATE
    public var skipTicks:Float = 1 / 60;
    public var maxFrameSkip:Int = 100;
    public var netfps:Int = 30;

    // INIT
    var loops:Int = 0;
    var nextGameTick:Float = Time.now();
    var lastNetTick:Float = Time.now();

    public function fixedUpdate(func:Void->Void)
    {
        if((Time.now() - lastNetTick) > (1 / netfps))
        {
            net.pump();
            lastNetTick = Time.now();
        }

        loops = 0;
        while(Time.now() > nextGameTick && loops < maxFrameSkip)
        {
            func();
            nextGameTick += skipTicks;
            loops++;
        }

        if(loops > maxFrameSkip) throw "out of fixed timestep";
    }

    // YAML
    // NEEDED HERE TO PREVENT REFLECTION HELL
    // @:allow(osis.NetEntityManager)
    // function createFactoryEntity(type:String):Entity
    // {
    //     return Reflect.field(this, type)();
    // }

    public function markChanged<T:Component>(entity:Entity, component:T, ?entitySet:EntitySet)
    {
        for(i in 0...32)
        {
            if( (entity.registeredSetsCode & 1 << i) != 0)
            {
                var tmpEntitySet = entitySets.get(i);
                if( (tmpEntitySet.code & (1 << component._id)) != 0 )
                {
                    if(tmpEntitySet != null && tmpEntitySet == entitySet) continue;
                    tmpEntitySet._changes.set(entity);
                }
            }
        }
    }

    // NET HELPERS
    #if client
    public function connect(address:String, port:Int)
    {
        net.connect(address, port);
        return net;
    }
    #end

    #if server
    public function listen(address:String, port:Int)
    {
        net.listen(address, port);
        return net;
    }
    #end
}


class Net
{
    public var onConnection:Connection->Void;
    public var onDisconnection:Connection->Void;

    #if server
    public var socket:Server;
    @:allow(osis.EntityManager)
    function listen(address:String, port:Int)
    {
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
    function connect(address:String, port:Int)
    {
        socket = new Client();
        socket.protocol = new Prefixed();
        socket.onData = onData;
        socket.onConnection = _onConnection;
        socket.onDisconnection = _onDisconnection;
        socket.connect(address, port);
    }
    #end

    function _onConnection(connection:Connection)
    {
        if(onConnection == null)
            trace("Client connected: you should probably bind" +
                  "the onConnection function");
        else
            onConnection(connection);
    }

    function _onDisconnection(connection:Connection)
    {
        if(onDisconnection == null)
            trace("Client disconnected: you should probably bind" +
                  " the onDisconnection function");
        else
            onDisconnection(connection);
    }

    function onData(connection:Connection)
    {
        // OVERRIDDEN BY NETENTITYMANAGER
    }
}


class EventContainer
{
    public var message:IMessage;
    public var func:IMessage->Connection->Void;

    public function new() {}
}


class NetEntityManager extends Net
{
    var entityFactory:Array<String>; // YAML FED BY NEW (SERIALIZED BY MACRO)

    var em:EntityManager;
    public static var instance:NetEntityManager; // MEH
    public var entities:IntMap<Entity> = new IntMap(); // MAPS SERVER>CLIENT IDS
    var serializableTypes:Vector<Class<Component>> = new Vector(32); // SERIALIZED SPECIFIC IDS
    var allTypes:Vector<Class<Component>> = new Vector(32); // ALL COMPONENTS IDS
    var eventListeners:IntMap<EventContainer> = new IntMap();

    public var templatesByName:Map<String, Template> = new Map();
    public var templatesById:Array<Template> = new Array();

    static inline var CREATE_ENTITY = 0;
    static inline var CREATE_TEMPLATE_ENTITY = 1;
    static inline var ADD_COMPONENT = 2;
    static inline var UPDATE_COMPONENT = 3;
    static inline var REMOVE_COMPONENT = 4;
    static inline var DESTROY_ENTITY = 5;
    static inline var EVENT = 6;

    public function new(em:EntityManager)
    {
        instance = this;
        this.em = em;

        // RESOLVE COMPONENT TYPES FROM STRING (MACRO)
        var serializables = podstream.SerializerMacro.getSerialized();

        // ONLY RELATED TO '''NETWORK''' SERIALIZABLE TYPES
        for(serializable in serializables)
        {
            if(serializable == null) continue; // Shouldn't be in the array in the first place !??
            var componentType:Class<Component> = cast Type.resolveClass(serializable);

            // NETWORKED COMPONENTS
            var componentNetId = (untyped componentType).__sid;
            if(componentNetId != -1) 
                serializableTypes[componentNetId] = componentType;

            // ALL COMPONENTS
            var componentId = (untyped componentType).__id;
            allTypes[componentId] = componentType;
        }

        trace("componentTypes " + serializableTypes);

        // GET ENTITY FACTORY (MACRO) YAML
        // entityFactory = haxe.Unserializer.run(haxe.Resource.getString("entityFactory"));
    }

    //////////////// SERVER //////////////
    #if server
    public var entitiesByConnection:Map<Connection, Entity> = new Map();
    public var connections:Map<Entity, Connection> = new Map();  // TEMP

    // USED WHEN DISCONNECTED FOR ENTITY DESTROY
    public function bindEntity(connection:Connection, entity:Entity)
    {
        entitiesByConnection.set(connection, entity);
        connections.set(entity, connection);  // TEMP
    }

    public function getBoundEntity(connection:Connection)
    {
        return entitiesByConnection.get(connection);
    }

    // YAML
    // ENTITY CREATION BY TEMPLATES: Needed to handle different compositions between c/s!
    // public function create(name:String)
    // {
    //     // var templateId = templatesByString.get(name);
    //     var templateId = entityFactory.indexOf(name);
    //     trace("wat " + name);
    //     if(templateId == -1) throw "The entity '${name}' doesn't exists";

    //     var entity:Entity = em.createFactoryEntity('create' + entityFactory[templateId]);
    //     entity.templateId = templateId;

    //     // SEND
    //     for(connection in socket.connections)
    //         sendCreate(connection.output, entity);

    //     entities.set(entity.id, entity);

    //     return entity;
    // }

    public function createEntity(name:String):Entity
    {
        // YAML
        // var templateId = templatesByString.get(name);
        // var templateId = entityFactory.indexOf(name);
        // trace("wat " + name);
        // if(templateId == -1) throw "The entity '${name}' doesn't exists";

        // BUILD IT
        var template = templatesByName.get(name);
        var entity:Entity = template.func();

        // SEND IT
        return sendFactoryEntity(name, entity);
    }

    public function sendFactoryEntity(name:String, entity:Entity):Entity
    {
        // trace("sendEntity " + name); // DEBUG
        var template = templatesByName.get(name);
        if(template == null) throw 'Template $name doesn\'t exists';
        entity.templateId = template.id;

        // SEND
        for(connection in socket.connections)
        {   
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

    function sendCreate(output:haxe.io.BytesOutput, entity:Entity)
    {
        output.writeInt8(CREATE_TEMPLATE_ENTITY);
        output.writeInt16(entity.id);
        output.writeInt8(entity.templateId);
    }

    public function destroyEntity(entity:Entity)
    {
        for(connection in socket.connections)
        {
            connection.output.writeInt8(DESTROY_ENTITY);
            connection.output.writeInt16(entity.id);
        }

        em.destroyEntity(entity);

        // CLEANUP
        var connection = connections.get(entity);
        entitiesByConnection.remove(connection);
        connections.remove(entity);  // TEMP

    }

    inline function sendAddComponent<T:Component>(entityId:Int, component:T, conn:Connection):T
    {
        conn.output.writeInt8(ADD_COMPONENT);
        conn.output.writeInt16(entityId);
        conn.output.writeInt8(component._sid);
        component.serialize(conn.output);

        return component;
    }

    public function addComponent<T:Component>(entity:Entity, component:T):T
    {
        for(connection in socket.connections)
            sendAddComponent(entity.id, component, connection);

        em.addComponent(entity, component);
        return component;
    }

    public function addComponentTo<T:Component>(entity:Entity, component:T, connEntity:Entity):T
    {
        return sendAddComponent(entity.id, component, connections.get(connEntity));
    }

    inline function sendRemoveComponent(entityId:Int, componentId:Int, connection:Connection)
    {
        connection.output.writeInt8(REMOVE_COMPONENT);
        connection.output.writeInt16(entityId);
        connection.output.writeInt8(componentId);
    }

    public function removeComponent<T:Class<Component>>(entity:Entity, componentType:T)
    {
        for(connection in socket.connections)
            sendRemoveComponent(entity.id, (untyped componentType).__sid, connection);
        em.removeComponent(entity, componentType);
    }

    public function sendWorldStateTo(connection:Connection)
    {
        var connectionEntity = entitiesByConnection.get(connection);
        if(connectionEntity == null)
            throw "Connection has to have a bound entity";

        for(entity in entities)
        {
            if(entity == connectionEntity) continue;

            sendCreate(connection.output, entity);
            sendDeltas(connection, entity);
        }
    }

    function sendDeltas(connection:Connection, entity:Entity)
    {
        var templateCode = templatesById[entity.templateId].code;
        var deltaCode = entity.code ^ templateCode;

        for(pos in 0...32)
        {
            // CHECK IF COMPONENT REMOVED FROM TEMPLATE
            var deltaBit = deltaCode & (1 << pos);
            if(deltaBit != 0)  // CHANGE
            {
                var addBit = entity.code & (1 << pos);
                if(addBit != 0)  // ADD
                {
                    // // Reflect until i find something cleaner (with podstream)
                    // if(Reflect.field(entity.components[pos], "_sid") == null)
                    //     continue;
                    // sendAddComponent(entity.id, cast entity.components[pos], connection);
                }
                else
                {
                    // if(entity.components[pos]._sid == -1) continue;
                    var sid = (cast allTypes[pos]).__sid;
                    if(sid == -1) continue;
                    var compName = Type.getClassName(allTypes[pos]);
                    sendRemoveComponent(entity.id, sid, connection);
                }
            }

            // SEND ENTITY COMPONENT VALUES
            if( (entity.code & 1 << pos) != 0)
            {
                if(entity.components[pos]._sid == -1) continue;
                sendAddComponent(entity.id, entity.components[pos], connection);
            }
        }
    }

    public function markChanged<T:Component>(entity:Entity, component:T, ?entitySet:EntitySet)
    {
        if(component._sid == -1)
            throw 'Component $component is not serializable';

        em.markChanged(entity, component, entitySet);

        for(connection in socket.connections)
        {
            connection.output.writeInt8(UPDATE_COMPONENT);
            connection.output.writeInt16(entity.id);
            connection.output.writeInt8(component._sid);
            component.serialize(connection.output);
        }
    }

    override function onData(connection:Connection)
    {
        while(connection.input.mark - connection.input.position > 0)
        {
            var msgtype = connection.input.readInt8();
            if(msgtype == EVENT)
            {
                var messageTypeId = connection.input.readInt8();
                receiveEvent(messageTypeId, connection);
            }
        }
    }
    #end

    /// COMMON ///

    public function registerTemplate(name:String, func:Void->Entity)
    {
        var template = new Template();
        template.name = name;
        template.func = func;
        templatesByName.set(name, template);
        templatesById[template.id] = template;

        // GET TEMPLATE CODE (used for network deltas)
        var entity = func();
        template.code = entity.code;
        em.destroyEntity(entity);
    }

    function receiveEvent(messageTypeId:Int, connection:Connection)
    {
        var eventContainer:EventContainer = eventListeners.get(messageTypeId);
        if(eventContainer == null) throw("No event  registered for " + messageTypeId);
        eventContainer.message.unserialize(connection.input);
        eventContainer.func(eventContainer.message, connection);
    }

    public function sendEvent(message:IMessage, ?connection:Connection)
    {
        #if server
        if(connection != null)
            _sendEvent(connection.output, message);
        else
            for(connection in socket.connections)
                _sendEvent(connection.output, message);
        #end
        #if client
            _sendEvent(socket.connection.output, message);
        #end
    }

    inline function _sendEvent(output:haxe.io.BytesOutput, message:IMessage)
    {
        output.writeInt8(EVENT);
        output.writeInt8(message._sid);
        message.serialize(output);
    }

    public function registerEvent<T:IMessage>(messageClass:Class<IMessage>,
                                              func:T->Connection->Void)
    {
        var event = new EventContainer();
        event.message = Type.createInstance(messageClass, []);
        event.func = cast func;

        eventListeners.set(event.message._sid, event);
    }

    //////////////// CLIENT //////////////
    #if client
    public function getEntity(entityId:Int):Entity
        return entities.get(entityId);

    override function onData(connection:Connection)
    {
        while(connection.input.mark - connection.input.position > 0)
        {
            var msgtype = connection.input.readInt8();

            switch(msgtype)
            {
                case CREATE_ENTITY:
                    var entityId = connection.input.readInt16();
                    trace("CREATE_ENTITY " + entityId);
                    var entity = em.createEntity();
                    entity.netId = entityId;
                    entities.set(entityId, entity);

                case DESTROY_ENTITY:
                    var entityId = connection.input.readInt16();
                    trace("DESTROY_ENTITY " + entityId);
                    var entity = entities.get(entityId);
                    entities.remove(entityId);
                    em.destroyEntity(entity);

                case ADD_COMPONENT:
                    var entityId = connection.input.readInt16();
                    var entity = entities.get(entityId);
                    var componentTypeId = connection.input.readInt8();
                    // trace("ADD_COMPONENT " + componentTypeId); // DEBUG
                    var componentType:Class<Component> = cast serializableTypes[componentTypeId];
                    var component:Component = Type.createInstance(componentType, []);
                    component.unserialize(connection.input);
                    em.addComponent(entity, component);

                case REMOVE_COMPONENT:
                    var entityId = connection.input.readInt16();
                    var componentTypeId = connection.input.readInt8();
                    var componentType:Class<Component> = cast serializableTypes[componentTypeId];
                    trace("REMOVE_COMPONENT " + untyped(componentType));
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

                    if(entity != null)
                    {
                        var component = entity.get(componentType);
                        component.unserialize(connection.input);
                        em.markChanged(entity, component);
                    }
                    else
                    {
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
                    // YAML
                    // var entity = Reflect.field(em,'create' + entityFactory[templateId])(); // YAML
                    var entity = templatesById[templateId].func();
                    entity.netId = entityId;
                    entities.set(entityId, entity);
            }
        }
    }

    public function markChanged<T:Component>(entity:Entity, component:T, ?entitySet:EntitySet)
    {
        // DUMMY, ACTUALLY USED FOR SERVER TO PREVENT ISSUES
        // WHEN SHARING SAME SYSTEM BETWEEN CLIENT & SERVER
    }
    #end

    @:allow(osis.EntityManager)
    function pump()
    {
        if(socket != null)
        {
            socket.pump();
            socket.flush();
        }
    }
}
