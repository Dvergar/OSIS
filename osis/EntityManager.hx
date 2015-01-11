package osis;

import haxe.macro.Expr;
import haxe.macro.Context;
import anette.*;
import anette.Protocol;
import anette.Bytes;
import de.polygonal.ds.ListSet;


typedef Connection = anette.Connection;


class IdAssign
{
    #if macro
    static var ids:Int = 1;
    static public function _build(fields:Array<Field>):Array<Field>
    {
        var id = ids++;
        trace("id " + id);

        var def = macro class {public var _id:Int = $v{id};
                               public static var __id:Int = $v{id}};

        return fields.concat(def.fields);
        return fields;
    }
    #end

    macro static public function build():Array<Field>
    {
        var fields = Context.getBuildFields();
        fields = _build(fields);  // remove fields = _...
        return fields;
    }
}


typedef CompTP = {public var _sid:Int;
                  public var _id:Int;
                  public function unserialize(bi:haxe.io.BytesInput):Void;
                  public function serialize(bo:haxe.io.BytesOutput):Void;};


@:autoBuild(podstream.SerializerMacro.build())
interface Component {}


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
    static var ids:Int = 0;
    
    public var code:Int = 0;
    public var id:Int;
    public var components:Array<Component> = new Array();
    public var registeredSystemsCode:Int = 0;

    // NET STUFF
    public var templateId:Int;

    public function new()
    {
        this.id = ids++;
        trace("ENTITY ID " + id);
    }

    public function get<T>(componentType:Class<T>):T
    {
        var comp:T = cast components[(untyped componentType).__id];
        if(comp == null)
            throw "Entity " + id + " doesn't have component " + componentType;
        return comp;
    }

    public function has<T>(componentType:Class<T>):Bool
    {
        var comp:T = cast components[(untyped componentType).__id];
        if(comp == null) return false;
        return true;
    }
}


typedef SystemToAccessThatDamn_id = {> System, _id: Int}
@:autoBuild(osis.IdAssign.build())
class System
{
    public var code:Int = 0;
    public var entities:Array<Entity> = new Array();
    public var em:EntityManager;
    public var net:NetEntityManager;

    public function need(componentTypeList:Array<Dynamic>)
    {
        for(componentType in componentTypeList)
        {
            code = code | (1 << componentType.__id);
        }
    }

    public function markChanged<T:{var _id:Int;}>(entity:Entity, component:T)
    {
        em.changes.push(new Change(entity, component._id, this));
        // em.changes.push(new Change(entity, component._id));
    }

    public function processEntity(entity:Entity)
    {
        // trace("processEntities");
    }

    public function onEntityChange(entity:Entity)
    {
        // trace("onEntityChange");
    }

    public function onEntityAdded(entity:Entity)
    {
        // trace("onEntityAdded");
    }

    public function onEntityRemoved(entity:Entity)
    {
        // trace("onEntityRemoved");
    }
}


// TODO: Pool
class Change
{
    public var entity:Entity;
    public var componentType:Int;
    public var notSystem:System;

    public function new(entity:Entity, componentType:Int, notSystem:System)
    // public function new(entity:Entity, componentType:Int)
    {
        this.entity = entity;
        this.componentType = componentType;
        this.notSystem = notSystem;
    }
}


class Template
{
    public static var ids:Int = 0;
    public var id:Int;
    public var name:String;
    public var func:Void->Entity;
    public var code:Int;

    public function new(name:String)
    {
        this.id = Template.ids++;
        this.name = name;
    }
}


#if !macro
// YAML
// @:build(osis.yec.Builder.build())
#end
class EntityManager
{
    var systems:haxe.ds.IntMap<SystemToAccessThatDamn_id> = new haxe.ds.IntMap();
    var self:EntityManager;
    var templatesIds = 0;
    public var changes:Array<Change> = new Array();
    public var templatesByName:Map<String, Template> = new Map();
    public var templatesById:Map<Int, Template> = new Map();
    public var net:NetEntityManager;

    public function new()
    {
        this.net = new NetEntityManager(this);
        this.self = this;
    }

    public function registerTemplate(name:String, func:Void->Entity)
    {
        var template = new Template(name);
        template.func = func;
        templatesByName.set(name, template);
        templatesById.set(template.id, template);

        // GET CODE
        // template.code = 1;
        var entity = func();
        template.code = entity.code;
        destroyEntity(entity);
    }

    public function createEntity():Entity
    {
        return new Entity();
    }

    public function destroyEntity(entity:Entity)
    {
        for(component in entity.components)
        {
            if(component != null)
            {
                trace("comp " + component);
                removeComponent(entity, cast component);
            }
        }
    }

    public function addComponent<T>(entity:Entity, component:T):T
    {
        entity.components[(untyped component)._id] = cast component;
        entity.code = entity.code | (1 << (untyped component)._id);

        for(system in systems)
        {
            if( (system.code & entity.code) == system.code )
            {
                var idCode = 0 | (1 << system._id);
                if( (entity.registeredSystemsCode & idCode) == idCode)
                {
                    continue;
                }

                system.entities.push(entity);
                system.onEntityAdded(entity);
                entity.registeredSystemsCode = entity.registeredSystemsCode | (1 << system._id);
            }
        }

        trace("addcomponent " + component);
        trace("entitycodeadd " + entity.code);

        return component;
    }

    public function removeComponent<T:{_id:Int}>(entity:Entity, component:T)
    {
        removeComp(entity, component._id);
    }

    public function removeComponentOfType<T:{__id:Int}>(entity:Entity, componentType:T)
    {
        removeComp(entity, componentType.__id);
    }

    inline function removeComp(entity:Entity, componentId:Int)
    {
        entity.code = entity.code & ~(1 << componentId);

        for(system in systems)
        {
            if( (system.code & entity.code) != system.code)
            {
                var idCode = 0 | (1 << system._id);
                if( (entity.registeredSystemsCode & idCode) != idCode)
                    continue;

                system.onEntityRemoved(entity);
                system.entities.remove(entity);
                entity.registeredSystemsCode = entity.registeredSystemsCode & ~(1 << system._id);
            }
        }

        trace("remcomponent " + componentId);
        trace("entitycoderem " + entity.code);
        
        entity.components[componentId] = null;
    }

    public function getComponent<T>(entity:Entity, componentType:Class<T>):T
    {
        return entity.get(componentType);
    }

    public function addSystem<T:{_id:Int,
                                 em:EntityManager,
                                 net:NetEntityManager}>(system:T)
    {
        system.em = this;
        system.net = this.net;
        systems.set(system._id, cast system);
    }

    public function processAllSystems()
    {
        // CHANGE EVENT
        for(change in changes)
        {
            // TODO: iterate over entity.registeredSystemsCode instead
            for(i in 0...32)
            {
                var system = systems.get(i);
                if( (change.entity.registeredSystemsCode & 1 << i) != 0)
                {
                    if(system == change.notSystem) continue;
                    system.onEntityChange(change.entity);
                }
            }

            // for(system in systems)
            // {
            //     if( (system.code | (1 << change.componentType) ) == system.code )
            //     {
            //         if(system == change.notSystem) continue;
            //         system.onEntityChange(change.entity);
            //     }
            // }
        }

        changes = new Array();

        // PROCESS LOOP
        for(system in systems)
        {
            for(entity in system.entities)
            {
                system.processEntity(entity);
            }
        }

    }

    // function processSystem<T:{__id:Int}>(systemClass:T)
    // {
    //     var system = systems.get(systemClass.__id);
    //     for(entity in system.entities)
    //     {
    //         system.processEntity(entity);
    //         if(changedEntities.has(entity)) system.onEntityChange(entity);
    //     }
    // }

    // FIXED UPDATE
    var loops:Int = 0;
    var skipTicks:Float = 1 / 60;
    var maxFrameSkip:Int = 100;
    var nextGameTick:Float = Time.now();
    var netfps:Int = 20;
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

    @:allow(osis.NetEntityManager)
    function markChanged<T:{var _id:Int;}>(entity:Entity, component:T, ?notSystem:System)
    // public function markChanged<T:{var _id:Int;}>(entity:Entity, component:T)
    {
        changes.push(new Change(entity, component._id, notSystem));
        // changes.push(new Change(entity, component._id));
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
    var em:EntityManager;
    public var entities:Map<Int, Entity> = new Map();
    var serializableTypes:Array<Class<Component>> = new Array();
    var entityFactory:Array<String>; // FED BY NEW (SERIALIZED BY MACRO)
    var eventListeners:Map<Int, EventContainer> = new Map();

    static inline var CREATE_ENTITY = 0;
    static inline var CREATE_TEMPLATE_ENTITY = 1;
    static inline var ADD_COMPONENT = 2;
    static inline var UPDATE_COMPONENT = 3;
    static inline var REMOVE_COMPONENT = 4;
    static inline var DESTROY_ENTITY = 5;
    static inline var EVENT = 6;
    static inline var EVENT2 = 7;

    public function new(em:EntityManager)
    {
        this.em = em;

        // RESOLVE COMPONENT TYPES FROM STRING (MACRO)
        var serializables = podstream.SerializerMacro.getSerialized();

        for(serializable in serializables)
        {
            if(serializable == null) continue;
            var c = Type.resolveClass(serializable);
            serializableTypes[cast(c).__sid] = cast c;
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
    public function bindEntity(connection:anette.Connection, entity:Entity)
    {
        entitiesByConnection.set(connection, entity);
        connections.set(entity, connection);  // TEMP
    }

    public function getBoundEntity(connection:anette.Connection)
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

    public function create(name:String)
    {
        // YAML
        // var templateId = templatesByString.get(name);
        // var templateId = entityFactory.indexOf(name);
        // trace("wat " + name);
        // if(templateId == -1) throw "The entity '${name}' doesn't exists";
        trace("ezoirj " + em.templatesByName);
        var template = em.templatesByName.get(name);
        var entity:Entity = template.func();
        entity.templateId = template.id;

        // SEND
        for(connection in socket.connections)
            sendCreate(connection.output, entity);

        entities.set(entity.id, entity);

        return entity;
    }

    function sendCreate(output:haxe.io.BytesOutput, entity:Entity)
    {
        output.writeInt8(CREATE_TEMPLATE_ENTITY);
        output.writeInt16(entity.id);
        output.writeInt8(entity.templateId);
    }

    // MIGHT BE USEFUL AT SOME POINT
    // public function createEntity()
    // {
    //     var entity = em.createEntity();

    //     for(connection in socket.connections)
    //     {
    //         connection.output.writeInt8(CREATE_ENTITY);
    //         connection.output.writeInt16(entity.id);
    //     }
    //     entities.set(entity.id, entity);
    //     return entity;
    // }

    public function destroyEntity(entity:Entity)
    {
        for(connection in socket.connections)
        {
            connection.output.writeInt8(DESTROY_ENTITY);
            connection.output.writeInt16(entity.id);
        }

        var entity = entities.get(entity.id);
        em.destroyEntity(entity);
        entities.remove(entity.id);
    }

    inline function sendAddComponent<T:CompTP>(entityId:Int, component:T, connection:Connection)
    {
        connection.output.writeInt8(ADD_COMPONENT);
        connection.output.writeInt16(entityId);
        connection.output.writeInt8(component._sid);
        component.serialize(connection.output);
    }

    public function addComponent<T:CompTP>(entity:Entity, component:T):T
    {
        for(connection in socket.connections)
            sendAddComponent(entity.id, component, connection);

        em.addComponent(entity, component);
        return cast component;
    }

    inline function sendRemoveComponent(entityId:Int, componentId:Int, connection:Connection)
    {
        connection.output.writeInt8(REMOVE_COMPONENT);
        connection.output.writeInt16(entityId);
        connection.output.writeInt8(componentId);
    }

    public function removeComponentOfType<T:{__sid:Int}>(entity:Entity, componentType:T)
    {
        for(connection in socket.connections)
            sendRemoveComponent(entity.id, componentType.__sid, connection);
        em.removeComponentOfType(entity, cast componentType);
    }

    public function sendWorldStateTo(connection:Connection)
    {
        trace("sendWorldStateTo");
        var connectionEntity = entitiesByConnection.get(connection);
        if(connectionEntity == null)
            throw "Connection has to have a bound entity";

        for(entity in entities)
        {
            if(entity == connectionEntity) continue;
            trace("sendentity " + entity);
            sendCreate(connection.output, entity);
            var templateCode = em.templatesById.get(entity.templateId).code;
            var deltaCode = entity.code ^ templateCode;
            trace("entitycode " + entity.code);
            trace("templateCode " + templateCode);
            for(pos in 0...32)
            {
                var deltaBit = deltaCode & (1 << pos);
                trace("deltacode " + deltaCode);
                trace("gnn " + (1 << pos));
                if(deltaBit != 0)  // CHANGE
                {
                    trace("CHANGE");
                    var addBit = entity.code & (1 << pos);
                    if(addBit != 0)  // ADD
                    {
                        trace("ADD");
                        sendAddComponent(entity.id, cast entity.components[pos], connection);
                    }
                    else
                    {
                        sendRemoveComponent(entity.id, pos, connection);
                        trace("REMOVE");
                    }
                }
            }
        }
    }

    public function markChanged<T:CompTP>(entity:Entity, component:T)
    {
        // em.markChanged(entity, component);

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
            switch(msgtype)
            {
                case EVENT2:
                    var messageTypeId = connection.input.readInt8();
                    receiveEvent(messageTypeId, connection);
            }
        }
    }
    #end

    /// COMMON ///

    function receiveEvent(messageTypeId:Int, connection:Connection)
    {
        var eventContainer:EventContainer = eventListeners.get(messageTypeId);
        eventContainer.message.unserialize(connection.input);
        eventContainer.func(cast eventContainer.message, connection);
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
        output.writeInt8(EVENT2);
        output.writeInt8(message._sid);
        message.serialize(output);
    }

    public function registerEvent<T:IMessage>(messageClass:Class<IMessage>, func:T->Connection->Void)
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
            // trace("msgtype " + msgtype);
            switch(msgtype)
            {
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
                    em.destroyEntity(entity);

                case ADD_COMPONENT:
                    trace("ADD_COMPONENT");
                    var entityId = connection.input.readInt16();
                    var entity = entities.get(entityId);
                    var componentTypeId = connection.input.readInt8();
                    var componentType = cast serializableTypes[componentTypeId];
                    var component:CompTP = Type.createInstance(componentType, []);
                    component.unserialize(connection.input);
                    em.addComponent(entity, component);

                case REMOVE_COMPONENT:
                    trace("REMOVE_COMPONENT");
                    var entityId = connection.input.readInt16();
                    var componentTypeId = connection.input.readInt8();
                    var componentType = cast serializableTypes[componentTypeId];
                    var entity = entities.get(entityId);
                    var component = entity.get(componentType);
                    em.removeComponent(entity, component);

                case UPDATE_COMPONENT:
                    // trace("UPDATE_COMPONENT");
                    var entityId = connection.input.readInt16();
                    var componentTypeId = connection.input.readInt8();
                    var componentType = cast serializableTypes[componentTypeId];
                    var entity = entities.get(entityId);
                    var component = entity.get(componentType);
                    component.unserialize(connection.input);
                    em.markChanged(entity, cast component);

                case EVENT2:
                    trace("EVENT2");
                    var messageTypeId = connection.input.readInt8();
                    receiveEvent(messageTypeId, connection);

                case CREATE_TEMPLATE_ENTITY:
                    var entityId = connection.input.readInt16();
                    trace("CREATE_TEMPLATE_ENTITY " + entityId);
                    var templateId = connection.input.readInt8();
                    // YAML
                    // var entity = Reflect.field(em,'create' + entityFactory[templateId])(); // YAML
                    var entity = em.templatesById.get(templateId).func();
                    entities.set(entityId, entity);
            }
        }
    }

    public function markChanged<T:CompTP>(entity:Entity, component:T)
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
