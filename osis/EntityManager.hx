package osis;

import haxe.macro.Expr;
import haxe.macro.Context;

import anette.*;
import anette.Protocol;
import anette.Bytes;
import de.polygonal.ds.ListSet;


typedef Connection = anette.Connection;

typedef CompTP = {public var _sid:Int;
                  public var _id:Int;
                  public function unserialize(bi:haxe.io.BytesInput):Void;
                  public function serialize(bo:haxe.io.BytesOutput):Void;};


// @:autoBuild(podstream.SerializerMacro.build())
@:autoBuild(osis.CustomNetworkTypes.build())
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


class System
{
    public var em:EntityManager;
    public var net:NetEntityManager;

    public function new()
    {
    }

    public function init() {}

    public function loop() {}
}


class EntitySet
{
    public var _id:Int;
    static var ids:Int = 0;
    public var code:Int = 0;
    public var entities:Array<Entity> = new Array();
    public var em:EntityManager;

    public var adds:ListSet<Entity> = new ListSet();
    public var changes:ListSet<Entity> = new ListSet();
    public var removes:ListSet<Entity> = new ListSet();

    public var readableAdds:ListSet<Entity> = new ListSet();
    public var readableChanges:ListSet<Entity> = new ListSet();
    public var readableRemoves:ListSet<Entity> = new ListSet();

    public function new(em:EntityManager, componentTypeList:Array<Dynamic>)
    {
        this._id = ids++;
        this.em = em;

        for(componentType in componentTypeList)
        {
            trace("systemcode " + code);
            trace("adding component " + componentType.__id);
            code = code | (1 << componentType.__id);
        }
    }

    public function applyChanges()
    {
        readableAdds = adds;
        readableChanges = changes;
        readableRemoves = removes;

        adds = new ListSet();
        changes = new ListSet();
        removes = new ListSet();
    }

    public function markChanged<T:{var _id:Int;}>(entity:Entity, component:T)
    {
        em.markChanged(entity, component);
    }

    public function entitiesChanged()
    {
        return readableChanges;
    }
    public function entitiesAdded()
    {
        return readableAdds;
    }
    public function entitiesRemoved()
    {
        return readableRemoves;
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


typedef ComponentDestroy = {entity:Entity, componentId:Int};

#if !macro
// YAML
// @:build(osis.yec.Builder.build())
#end
class EntityManager
{
    var systems:Array<System> = new Array();
    var entitySets:haxe.ds.IntMap<EntitySet> = new haxe.ds.IntMap(); // Why not array?
    var componentsToDestroy:Array<ComponentDestroy> = new Array();
    var templatesIds = 0;
    public var templatesByName:Map<String, Template> = new Map();
    public var templatesById:Map<Int, Template> = new Map();
    public var net:NetEntityManager;
    public static var test:Int = 42;
    // var self:EntityManager;  // YAML

    public function new()
    {
        this.net = new NetEntityManager(this);
        // this.self = this;  // YAML
    }

    public function getEntitySet(componentTypeList:Array<Dynamic>)
    {
        var entitySet = new EntitySet(this, componentTypeList);
        // trace("entityset " + entitySet);
        entitySets.set(entitySet._id, entitySet);
        return entitySet;
    }

    public function registerTemplate(name:String, func:Void->Entity)
    {
        var template = new Template(name);
        template.func = func;
        templatesByName.set(name, template);
        templatesById.set(template.id, template);

        // GET CODE
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
            if(component != null)
                removeComponentInstance(entity, cast component);
    }

    public function addComponent<T>(entity:Entity, component:T):T
    {
        // This is horrible, please find a way to type this correctly
        if((untyped component)._id == null) throw "Trying to add a non-component";
        trace("addComponent " + (untyped component)._id);
        entity.components[(untyped component)._id] = cast component;
        entity.code = entity.code | (1 << (untyped component)._id);

        for(entitySet in entitySets)
        {
            if( (entitySet.code & entity.code) == entitySet.code )
            {
                var idCode = 0 | (1 << entitySet._id);
                if( (entity.registeredSystemsCode & idCode) == idCode)
                {
                    continue;
                }

                entitySet.entities.push(entity);  // Doublons can happen with network
                entitySet.adds.set(entity);
                entity.registeredSystemsCode = entity.registeredSystemsCode | (1 << entitySet._id);
            }
        }

        return component;
    }

    @:allow(osis.NetEntityManager)
    function removeComponentInstance<T:{_id:Int}>(entity:Entity, component:T)
    {
        _removeComponent(entity, component._id);
    }

    public function removeComponent<T:{__id:Int}>(entity:Entity, componentType:T)
    {
        _removeComponent(entity, componentType.__id);
    }

    inline function _removeComponent(entity:Entity, componentId:Int)
    {
        entity.code = entity.code & ~(1 << componentId);

        for(entitySet in entitySets)
        {
            if( (entitySet.code & entity.code) != entitySet.code)
            {
                var idCode = 0 | (1 << entitySet._id);
                if( (entity.registeredSystemsCode & idCode) != idCode)
                    continue;

                entitySet.removes.set(entity);
                entitySet.entities.remove(entity);
                entitySet.changes.remove(entity);
                entity.registeredSystemsCode = entity.registeredSystemsCode & ~(1 << entitySet._id);
            }
        }
        
        componentsToDestroy.push({entity:entity, componentId:componentId});  // TEMPORARY, hopefully
    }

    public function getComponent<T>(entity:Entity, componentType:Class<T>):T
    {
        return entity.get(componentType);
    }

    public function addSystem(system:System)
    {
        system.em = this;
        system.net = this.net;
        system.init();
        systems.push(system);
    }

    public function processAllSystems()
    {
        for(system in systems) system.loop();

        for(_ in componentsToDestroy)
            _.entity.components[_.componentId] = null;

        componentsToDestroy = new Array();
    }

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

    public function markChanged<T:{var _id:Int;}>(entity:Entity, component:T)
    {
        for(i in 0...32)
        {
            if( (entity.registeredSystemsCode & 1 << i) != 0)
            {
                var entitySet = entitySets.get(i);
                if( (entitySet.code & (1 << component._id)) != 0 )
                    entitySet.changes.set(entity);
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
    public static var instance:NetEntityManager; // MEH
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

    public function new(em:EntityManager)
    {
        instance = this;
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

    public function createEntity(name:String):Entity
    {
        // YAML
        // var templateId = templatesByString.get(name);
        // var templateId = entityFactory.indexOf(name);
        // trace("wat " + name);
        // if(templateId == -1) throw "The entity '${name}' doesn't exists";

        // BUILD IT
        var template = em.templatesByName.get(name);
        var entity:Entity = template.func();

        // SEND IT
        return sendEntity(name, entity);
    }

    public function sendEntity(name:String, entity:Entity):Entity
    {
        trace("sendEntity " + name);
        var template = em.templatesByName.get(name);
        if(template == null) throw 'Template $name doesn\'t exists';
        entity.templateId = template.id;

        // SEND
        for(connection in socket.connections)
        {   
            sendCreate(connection.output, entity);
            sendDeltas(connection, entity);
        }

        entities.set(entity.id, entity);

        trace("endsendentity");

        return entity;
    }

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

        var entity = entities.get(entity.id);
        em.destroyEntity(entity);
        entities.remove(entity.id);
    }

    inline function sendAddComponent<T:CompTP>(entityId:Int, component:T, conn:Connection)
    {
        conn.output.writeInt8(ADD_COMPONENT);
        conn.output.writeInt16(entityId);
        conn.output.writeInt8(component._sid);
        component.serialize(conn.output);
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

    public function removeComponent<T:{__sid:Int}>(entity:Entity, componentType:T)
    {
        for(connection in socket.connections)
            sendRemoveComponent(entity.id, componentType.__sid, connection);
        em.removeComponent(entity, cast componentType);
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
            sendDeltas(connection, entity);
        }
    }

    inline function sendDeltas(connection:Connection, entity:Entity)
    {
        var templateCode = em.templatesById.get(entity.templateId).code;
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
                    // Reflect until i find something cleaner (with podstream)
                    if(Reflect.field(entity.components[pos], "_sid") == null)
                        continue;
                    sendRemoveComponent(entity.id, pos, connection);
                }
            }

            // SEND ENTITY COMPONENT VALUES
            if( (entity.code & 1 << pos) != 0)
            {
                // Reflect until i find something cleaner (with podstream)
                if(Reflect.field(entity.components[pos], "_sid") == null)
                    continue;

                sendAddComponent(entity.id, cast entity.components[pos], connection);
            }
        }
    }

    public function markChanged<T:CompTP>(entity:Entity, component:T)
    {
        em.markChanged(entity, component);

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
        output.writeInt8(EVENT);
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
                    var entityId = connection.input.readInt16();
                    var entity = entities.get(entityId);
                    var componentTypeId = connection.input.readInt8();
                    // trace("ADD_COMPONENT " + componentTypeId);
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
                    em.removeComponentInstance(entity, component);

                case UPDATE_COMPONENT:
                    var entityId = connection.input.readInt16();
                    var componentTypeId = connection.input.readInt8();
                    var componentType = cast serializableTypes[componentTypeId];
                    var entity = entities.get(entityId);
                    var component = entity.get(componentType);
                    // trace("UPDATE_COMPONENT");
                    // trace(component._id);
                    component.unserialize(connection.input);
                    em.markChanged(entity, cast component);

                case EVENT:
                    // trace("EVENT");
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
