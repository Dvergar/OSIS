package ecs;
import haxe.macro.Expr;
import haxe.macro.Context;
import anette.*;
import anette.Protocol;
import anette.Bytes;
import de.polygonal.ds.LinkedQueue;
import de.polygonal.ds.ListSet;


enum Mod
{
    REMOVE;
    MOD;
}


class Change
{
    public var entityId:Int;
    public var component:Component;
    public var type:Mod;

    public function new(entityId:Int, component:Component, type:Mod)
    {
        this.entityId = entityId;
        this.component = component;
        this.type = type;
    }
}


class EntitySet
{
    static var ids:Int = 0;
    public var code:Int = 0;
    public var entities:Map<Int, Entity2> = new Map();
    public var changes:LinkedQueue<Change> = new LinkedQueue();
    public var ed:EntityData;
    public var addedEntities:ListSet<Entity2> = new ListSet();
    public var changedEntities:ListSet<Entity2> = new ListSet();
    public var removedEntities:ListSet<Entity2> = new ListSet();

    public function new(ed:EntityData)
    {
        code = ids++;
        this.ed = ed;
    }

    public function applyChanges():Bool
    {
        addedEntities.clear();
        changedEntities.clear();
        removedEntities.clear();

        var changed = false;
        if(changes.size() > 0) changed = true;

        for(change in changes)
        {
            var entity = entities.get(change.entityId);
            if(entity == null)
            {
                var component = cast change.component;
                entity = new Entity2(ed, change.entityId);
                entity.code = entity.code | (1 << component._id);
                entities.set(entity.id, entity);
                addedEntities.set(entity);
            }

            if( (code & entity.code) == code )
            {
                var component = cast change.component;
                switch(change.type)
                {
                    case Mod.MOD:
                        changedEntities.set(entity);
                        entity.components[component._id] = change.component;
                    case Mod.REMOVE:
                        removedEntities.set(entity);
                        entities.remove(entity.id);
                }
            }
        }

        changes.clear();

        return changed;
    }
}


class EntityData
{
    static var entityIds:Int = 0;
    var entitySets:Array<EntitySet> = new Array();

    public function new() {}

    public function createEntity()
    {
        return new Entity2(this, entityIds++);
    }

    public function getEntities(componentClassList:Array<Class<Component>>)
    {
        var entitySet = new EntitySet(this);

        // Move into EntitySet?
        for(componentClass in componentClassList)
        {
            var cclass = cast componentClass;
            entitySet.code = entitySet.code | (1 << (cclass.__id));
        }

        entitySets.push(entitySet);

        return entitySet;
    }

    public function setComponent<T:{var _id:Int;}>(entity:Entity2, component:T):T
    {
        var change = new Change(entity.id, cast component, Mod.MOD);

        for(set in entitySets)
        {
            set.changes.enqueue(change);
        }

        return component;
    }
}


typedef Component2 = {> Component,
                      // public var __id:Int;
                      public var _id:Int;};


class Entity2
{
    public var code:Int = 0;
    public var id:Int;
    public var components:Array<Component> = new Array();
    public var registeredSystemsCode:Int = 0;
    public var ed:EntityData;

    public function new(ed:EntityData, id:Int)
    {
        this.ed = ed;
        this.id = id;
        trace("ENTITY ID " + id);
    }

    public function get<T:Component>(componentClass:Class<T>):T
    {
        // var cclass = cast componentClass;
        var comp:T = cast components[(cast componentClass).__id];
        if(comp == null) throw "Entity " + id + " doesn't have component " + componentClass;
        return comp;
    }

    public function set<T:{_id:Int}, U:{__id:Int}>(component:T):T
    {
        var componentClass:U = cast Type.getClass(component);
        if(has(componentClass))
        {
            components[componentClass.__id] = cast component;
        }

        ed.setComponent(this, component);

        return component;
    }

    public function has<T:{__id:Int}>(componentClass:T):Bool
    {
        // var ctype = cast componentType;
        // var comp = cast components[ctype.__id];
        if(components[componentClass.__id] == null) return false;
        return true;
    }
}


////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

class IdAssign
{
    #if macro
    static var ids:Int = 1;  // Careful common to systems & components
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


// Removed _id & __id _sid & __sid are generated from hxserializer
typedef CompTP = {public var _sid:Int;
                  public var _id:Int;
                  public var sync:Bool;
                  public var netOwner:Int;
                  public function unserialize(bi:haxe.io.BytesInput):Void;
                  public function serialize(bo:haxe.io.BytesOutput):Void;};



class Lel
{
    #if macro
    static var ids:Int = 0;
    static public function _build(fields:Array<Field>):Array<Field>
    {
        var fields = Context.getBuildFields();
        var pos = Context.currentPos();

        fields = hxserializer.SerializerMacro._build(fields);
        fields = IdAssign._build(fields);

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


@:autoBuild(ecs.Lel.build())
class Component
{
    public var sync:Bool = false;
    public var netOwner:Int;


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
    public var triggerEvent:Bool;
    public var args:Dynamic;

    public function new()
    {
        this.id = ids++;
        trace("ENTITY ID " + id);
    }

    public function get<T>(componentType:Class<T>):T
    {
        var ctype = cast componentType;
        var comp = cast components[ctype.__id];
        if(comp == null) throw "Entity " + id + " doesn't have component " + componentType;
        return comp;
    }

    public function has<T>(componentType:Class<T>):Bool
    {
        var ctype = cast componentType;
        var comp = cast components[ctype.__id];
        if(comp == null) return false;
        return true;
    }
}


typedef System2 = {> System, _id: Int}
@:autoBuild(ecs.IdAssign.build())
class System
{
    public var code:Int = 0;
    public var entities:Array<Entity> = new Array();
    public var em:EntityManager;

    public function need(componentTypeList:Array<Dynamic>)
    {
        for(componentType in componentTypeList)
        {
            code = code | (1 << (componentType.__id));
        }
    }

    public function processEntities(entity:Entity)
    {
        // trace("processEntities");
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


class EntityManager
{
    var systems:haxe.ds.IntMap<System2> = new haxe.ds.IntMap();
    public var net:NetEntityManager;

    public function new()
    {
        net = new NetEntityManager(this);
    }

    public function createEntity():Entity
    {
        return new Entity();
    }

    // Shouldn't be called for network entities
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

    public function addComponent<T:{var _id:Int; var sync:Bool; var netOwner:Int;}>(entity:Entity, component:T, ?sync:Bool):T
    {
        if(sync != null)
        {
            component.sync = sync;
            component.netOwner = entity.id;
        }

        entity.components[component._id] = cast component;
        entity.code = entity.code | (1 << component._id);

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

        return cast component;
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

    // public function addSystem<T:{__id:Int}>(systemClass:T, ?args:Dynamic)
    // {
    //     var system:System = Type.createInstance(cast systemClass, args);
    //     system.em = this;
    //     systems.set(systemClass.__id, cast system);
    // }

    public function addSystem<T:{_id:Int, em:EntityManager}>(system:T)
    {
        system.em = this;
        systems.set(system._id, cast system);
    }

    public function processSystem<T:{__id:Int}>(systemClass:T)
    {
        var system = systems.get(systemClass.__id);
        for(entity in system.entities)
        {
            system.processEntities(entity);
        }
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
}


class Net
{
    #if server
    public var socket:Server;
    public function server(address:String, port:Int)
    {
        socket = new Server(address, port);
        socket.protocol = new Prefixed();
        socket.onData = onData;
        return socket;
    }

    #elseif client
    public var socket:Client;
    public function connect(address:String, port:Int)
    {
        socket = new Client();
        socket.protocol = new Prefixed();
        socket.onData = onData;
        // client.onConnection = onConnection;
        // client.onDisconnection = onDisconnection;
        socket.connect(address, port);
    }

    #end
    function onData(connection:Connection)
    {
        trace("data");
    }
}


class NetEntityManager extends Net
{
    var em:EntityManager;
    var entities:Map<Int, Entity> = new Map();
    var componentTypes:Array<Class<Component>> = new Array();
    var templates:Array<Dynamic->Entity> = new Array();
    var templatesByString:Map<String, Int> = new Map();
    var templatesIds:Int = 0;
    var syncComponents:Array<Component> = new Array();
    // var eventListeners:Map<String, Dynamic->Void> = new Map();

    static inline var CREATE_ENTITY = 0;
    static inline var CREATE_TEMPLATE_ENTITY = 1;
    static inline var ADD_COMPONENT = 2;
    static inline var UPDATE_COMPONENT = 3;
    static inline var DESTROY_ENTITY = 4;
    // static inline var EVENT = 5;

    public function new(em:EntityManager)
    {
        this.em = em;

        // RESOLVE COMPONENT TYPES FROM STRING
        var components = hxserializer.SerializerMacro.getSerialized();
        for(component in components)
        {
            var c = Type.resolveClass(component);
            componentTypes.push(cast c);
        }
    }

    //////////////// SERVER //////////////
    #if server
    public var entitiesByConnection:Map<Connection, Entity> = new Map();

    // USED WHEN DISCONNECTED FOR ENTITY DESTROY
    public function bindEntity(connection:anette.Connection, entity:Entity)
    {
        entitiesByConnection.set(connection, entity);
    }

    public function getBoundEntity(connection:anette.Connection)
    {
        return entitiesByConnection.get(connection);
    }

    // ENTITY CREATION BY TEMPLATES: Needed to handle different compositions between c/s!
    public function create(name:String, args:Dynamic)
    {
        var templateId = templatesByString.get(name);
        if(templateId == null) throw "This entity type hasn't been registered";
        var entity = templates[templateId](args);
        entity.templateId = templateId;
        entity.args = args;

        // SEND
        for(connection in socket.connections)
            _sendCreate(connection.output, entity);

        entities.set(entity.id, entity);

        for(component in entity.components)
            if(component != null)
                if(component.sync) syncComponents.push(component);

        return entity;
    }

    public function _sendCreate(output:haxe.io.BytesOutput, entity:Entity)
    {
        output.writeInt8(CREATE_TEMPLATE_ENTITY);
        output.writeInt16(entity.id);
        output.writeInt8(entity.templateId);
        var argsSerialized = haxe.Serializer.run(entity.args);
        output.writeInt16(argsSerialized.length);
        output.writeString(argsSerialized);
    }

    public function createEntity()
    {
        var entity = em.createEntity();

        for(connection in socket.connections)
        {
            connection.output.writeInt8(CREATE_ENTITY);
            connection.output.writeInt16(entity.id);
        }
        entities.set(entity.id, entity);
        return entity;
    }

    public function destroyEntity(entity:Entity)
    {
        for(connection in socket.connections)
        {
            connection.output.writeInt8(DESTROY_ENTITY);
            connection.output.writeInt16(entity.id);
        }
        var entity = entities.get(entity.id);

        trace("entitycomponents " + entity.components);

        for(component in entity.components)
            if(component != null)
                if(component.sync)
                    syncComponents.remove(component);
        trace("entity destroyed " + syncComponents);


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
        if(component.sync) syncComponents.push(cast component);
        em.addComponent(entity, component);
        return cast component;
    }

    // override function onData(connection:Connection)
    // {
    //     while(connection.input.mark - connection.input.position > 0)
    //     {
    //         var msgtype = connection.input.readInt8();
    //         switch(msgtype)
    //         {
    //             case EVENT:
    //                 receiveEvent(connection);
    //         }
    //     }
    // }

    public function sendWorldStateTo(connection:Connection, player:Entity)
    {
        trace("sendWorldStateTo");
        for(entity in entities)
        {
            if(entity == player) continue;
            _sendCreate(connection.output, entity);
        }
    }
    #end

    //////////////// CLIENT //////////////
    #if client
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

                case CREATE_TEMPLATE_ENTITY:
                    var entityId = connection.input.readInt16();
                    var templateId = connection.input.readInt8();
                    var argsLength = connection.input.readInt16();
                    var argsSerialized = connection.input.readString(argsLength);
                    var args = haxe.Unserializer.run(argsSerialized);
                    var entity = templates[templateId](args);
                    entities.set(entityId, entity);

                // case EVENT:
                //     receiveEvent(connection);
            }
        }
    }
    #end

    // function receiveEvent(connection:Connection)
    // {
    //     // trace("EVENT");
    //     var eventLength = connection.input.readInt8();
    //     var eventName = connection.input.readString(eventLength);
    //     var msgLength = connection.input.readInt16();
    //     var msgSerialized = connection.input.readString(msgLength);
    //     var msg:Dynamic = haxe.Unserializer.run(msgSerialized);

    //     #if server msg.entity = entitiesByConnection.get(connection); #end
    //     var func = eventListeners.get(eventName);
    //     if(func == null) throw "Not listener for event : " + eventName;
    //     func(msg);
    // }

    // public function sendEvent(name:String, msg:Dynamic, ?connection:Connection)
    // {
    //     #if server
    //     if(connection != null)
    //         _sendEvent(connection.output, haxe.Serializer.run(msg), name);
    //     else
    //         for(connection in socket.connections)
    //             _sendEvent(connection.output, haxe.Serializer.run(msg), name);
    //     #end
    //     #if client
    //         _sendEvent(socket.connection.output, haxe.Serializer.run(msg), name);
    //     #end
    // }

    // inline function _sendEvent(output:haxe.io.BytesOutput, serializedMsg:String,
    //                                                                 name:String)
    // {
    //     output.writeInt8(EVENT);
    //     output.writeInt8(name.length);
    //     output.writeString(name);
        
    //     output.writeInt16(serializedMsg.length);
    //     output.writeString(serializedMsg);
    // }

    public function registerTemplate(name:String, func:Dynamic->Entity)
    {
        var id = templatesIds++;
        templates[id] = func;
        templatesByString.set(name, id);
    }

    // public function registerEvent(name:String, func:Dynamic)
    // {
    //     eventListeners.set(name, func);
    // }

    public function pump()
    {
        if(socket != null)
        {
            socket.pump();
            #if server
            for(component in syncComponents)
            {
                var c = cast component;

                for(connection in socket.connections)
                {
                    connection.output.writeInt8(UPDATE_COMPONENT);
                    connection.output.writeInt16(c.netOwner);
                    connection.output.writeInt8(c._sid);
                    c.serialize(connection.output);
                }
            }
            #end
            socket.flush();
        }
    }
}
