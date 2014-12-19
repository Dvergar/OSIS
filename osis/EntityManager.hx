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
class Component
{
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

typedef SystemTP = {> System, _id: Int}
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
        changes.push(new Change(entity, component._id, this));
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

    public function new(name:String)
    {
        this.id = Template.ids++;
        this.name = name;
    }
}


#if !macro
// @:build(osis.yec.Builder.build())
#end
class EntityManager
{
    var systems:haxe.ds.IntMap<SystemTP> = new haxe.ds.IntMap();
    var changes:Array<Change> = new Array();
    var self:EntityManager;
    var templatesIds = 0;
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

    public function addComponent<T>(entity:Entity, component:T, ?sync:Bool):T
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
            for(system in systems)
            {
                if( (system.code | (1 << change.componentType) ) == system.code )
                {
                    if(system == change.notSystem) continue;
                    system.onEntityChange(change.entity);
                }
            }
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

    // NEEDED HERE TO PREVENT REFLECTION HELL
    @:allow(NetEntityManager)
    public function createFactoryEntity(type:String):Entity
    {
        return Reflect.field(this, type)();
    }

    public function markChanged<T:{var _id:Int;}>(entity:Entity, component:T, notSystem:System)
    {
        changes.push(new Change(entity, component._id, notSystem));
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
    @:allow(EntityManager)
    public function listen(address:String, port:Int)
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
    @:allow(EntityManager)
    public function connect(address:String, port:Int)
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


class NetEntityManager extends Net
{
    var em:EntityManager;
    var entities:Map<Int, Entity> = new Map();
    var componentTypes:Array<Class<Component>> = new Array();
    var entityFactory:Array<String>; // FED BY NEW (SERIALIZED BY MACRO)
    var eventListeners:Map<String, Dynamic->Void> = new Map();

    static inline var CREATE_ENTITY = 0;
    static inline var CREATE_TEMPLATE_ENTITY = 1;
    static inline var ADD_COMPONENT = 2;
    static inline var UPDATE_COMPONENT = 3;
    static inline var DESTROY_ENTITY = 4;
    static inline var EVENT = 5;

    public function new(em:EntityManager)
    {
        this.em = em;

        // RESOLVE COMPONENT TYPES FROM STRING (MACRO)
        var components = podstream.SerializerMacro.getSerialized();
        // for(component in components)
        // {
        //     trace("stringcomp " + component);
        //     var c = Type.resolveClass(component);
        //     componentTypes.push(cast c);
        // }

        for(component in components)
        {
            if(component == null) continue;
            var c = Type.resolveClass(component);
            componentTypes[cast(c).__sid] = cast c;
        }

        trace("componentTypes " + componentTypes);
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

    // ENTITY CREATION BY TEMPLATES: Needed to handle different compositions between c/s!
    // YAML
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
        // var templateId = templatesByString.get(name);
        // var templateId = entityFactory.indexOf(name);
        // trace("wat " + name);
        // if(templateId == -1) throw "The entity '${name}' doesn't exists";

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

    public function addComponent<T:CompTP>(entity:Entity, component:T):T
    {
        for(connection in socket.connections)
        {
            connection.output.writeInt8(ADD_COMPONENT);
            connection.output.writeInt16(entity.id);
            connection.output.writeInt8(component._sid);
            component.serialize(connection.output);
        }

        em.addComponent(entity, component);
        return cast component;
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
            sendCreate(connection.output, entity);
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
                case EVENT:
                    receiveEvent(connection);
            }
        }
    }
    #end

    /// COMMON ///

    function receiveEvent(connection:Connection)
    {
        // trace("EVENT");
        var eventLength = connection.input.readInt8();
        var eventName = connection.input.readString(eventLength);
        var msgLength = connection.input.readInt16();
        var msgSerialized = connection.input.readString(msgLength);
        var msg:Dynamic = haxe.Unserializer.run(msgSerialized);

        #if server
        // msg.entity = entitiesByConnection.get(connection);
        msg.connection = connection;
        #end
        var func = eventListeners.get(eventName);
        if(func == null) throw "Not listener for event : " + eventName;
        func(msg);
    }

    public function sendEvent(name:String, msg:Dynamic, ?connection:Connection)
    {
        #if server
        if(connection != null)
            _sendEvent(connection.output, haxe.Serializer.run(msg), name);
        else
            for(connection in socket.connections)
                _sendEvent(connection.output, haxe.Serializer.run(msg), name);
        #end
        #if client
            _sendEvent(socket.connection.output, haxe.Serializer.run(msg), name);
        #end
    }

    inline function _sendEvent(output:haxe.io.BytesOutput, serializedMsg:String,
                                                                    name:String)
    {
        output.writeInt8(EVENT);
        output.writeInt8(name.length);
        output.writeString(name);
        
        output.writeInt16(serializedMsg.length);
        output.writeString(serializedMsg);
    }

    public function registerEvent(name:String, func:Dynamic)
    {
        eventListeners.set(name, func);
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
                    var componentType = cast componentTypes[componentTypeId];
                    var component:CompTP = Type.createInstance(componentType, []);
                    component.unserialize(connection.input);
                    em.addComponent(entity, component);

                case UPDATE_COMPONENT:
                    // trace("UPDATE_COMPONENT");
                    var entityId = connection.input.readInt16();
                    var componentTypeId = connection.input.readInt8();
                    var componentType = cast componentTypes[componentTypeId];
                    var entity = entities.get(entityId);
                    var component = entity.get(componentType);
                    component.unserialize(connection.input);
                    em.markChanged(entity, cast component);

                case CREATE_TEMPLATE_ENTITY:
                    var entityId = connection.input.readInt16();
                    var templateId = connection.input.readInt8();
                    // var entity = Reflect.field(em,'create' + entityFactory[templateId])(); // YAML
                    var entity = em.templatesById.get(templateId).func();
                    entities.set(entityId, entity);

                case EVENT:
                    receiveEvent(connection);
            }
        }
    }

    public function markChanged<T:CompTP>(entity:Entity, component:T)
    {
        // DUMMY, ACTUALLY USED FOR SERVER TO PREVENT ISSUES
        // WHEN SHARING SAME SYSTEM BETWEEN CLIENT & SERVER
    }
    #end

    @:allow(EntityManager)
    public function pump()
    {
        if(socket != null)
        {
            socket.pump();
            socket.flush();
        }
    }
}
