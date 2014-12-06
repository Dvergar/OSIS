package osis;

import haxe.macro.Expr;
import haxe.macro.Context;
import anette.*;
import anette.Protocol;
import anette.Bytes;
import de.polygonal.ds.LinkedQueue;
import de.polygonal.ds.ListSet;


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
                  public function unserialize(bi:haxe.io.BytesInput):Void;
                  public function serialize(bo:haxe.io.BytesOutput):Void;};


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
    public var triggerEvent:Bool;
    public var args:Dynamic;

    public function new()
    {
        this.id = ids++;
        trace("ENTITY ID " + id);
    }

    public function get<T>(componentType:Class<T>):T
    {
        var comp:T = cast components[(untyped componentType).__sid];
        if(comp == null)
            throw "Entity " + id + " doesn't have component " + componentType;
        return comp;
    }

    public function has<T>(componentType:Class<T>):Bool
    {
        var comp:T = cast components[(untyped componentType).__sid];
        if(comp == null) return false;
        return true;
    }
}


typedef System2 = {> System, _id: Int}
@:autoBuild(osis.IdAssign.build())
class System
{
    public var code:Int = 0;
    public var entities:Array<Entity> = new Array();
    public var em:EntityManager;
    public var change:Bool = true;

    public function need(componentTypeList:Array<Dynamic>)
    {
        for(componentType in componentTypeList)
        {
            code = code | (1 << componentType.__sid);
        }
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

#if !macro
@:build(osis.yec.Builder.build())
#end
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

    public function addComponent<T>(entity:Entity, component:T, ?sync:Bool):T
    {
        entity.components[(untyped component)._sid] = cast component;
        entity.code = entity.code | (1 << (untyped component)._sid);

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

    public function removeComponent<T:{_sid:Int}>(entity:Entity, component:T)
    {
        removeComp(entity, component._sid);
    }

    public function removeComponentOfType<T:{__sid:Int}>(entity:Entity, componentType:T)
    {
        removeComp(entity, componentType.__sid);
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
            system.processEntity(entity);
            if(!system.change) continue;
            system.onEntityChange(entity);
        }
        system.change = false;
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

    // NEEDED HERE TO PREVENT REFLECTION HELL
    public function createFactoryEntity(type:String):Entity
    {
        return Reflect.field(this, type)();
    }

    public function dispatch<T:{_sid:Int}>(entity:Entity, component:T)
    {
        // trace("dispatch");
        for(system in systems)
        {          
            if( (system.code | (1 << (untyped component)._sid)) == system.code )
            {
                // trace("from component id " + (untyped component)._sid);
                system.change = true;
            }
        }
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
    var entityFactory:Array<String>; // FED BY NEW (SERIALIZED BY MACRO)

    static inline var CREATE_ENTITY = 0;
    static inline var CREATE_TEMPLATE_ENTITY = 1;
    static inline var ADD_COMPONENT = 2;
    static inline var UPDATE_COMPONENT = 3;
    static inline var DESTROY_ENTITY = 4;

    public function new(em:EntityManager)
    {
        this.em = em;

        // RESOLVE COMPONENT TYPES FROM STRING (MACRO)
        var components = podstream.SerializerMacro.getSerialized();
        for(component in components)
        {
            trace("stringcomp " + component);
            var c = Type.resolveClass(component);
            componentTypes.push(cast c);
        }

        // GET ENTITY FACTORY (MACRO)
        entityFactory = haxe.Unserializer.run(haxe.Resource.getString("entityFactory"));
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
    public function create(name:String)
    {
        // var templateId = templatesByString.get(name);
        var templateId = entityFactory.indexOf(name);
        if(templateId == -1) throw "The entity '${name}' doesn't exists";

        var entity:Entity = em.createFactoryEntity('create' + entityFactory[templateId]);
        entity.templateId = templateId;

        // SEND
        for(connection in socket.connections)
            _sendCreate(connection.output, entity);

        entities.set(entity.id, entity);

        return entity;
    }

    public function _sendCreate(output:haxe.io.BytesOutput, entity:Entity)
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
            _sendCreate(connection.output, entity);
        }
    }

    public function dispatch<T:CompTP>(entity:Entity, component:T)
    {
        em.dispatch(entity, component);

        for(connection in socket.connections)
        {
            connection.output.writeInt8(UPDATE_COMPONENT);
            connection.output.writeInt16(entity.id);
            connection.output.writeInt8(component._sid);
            component.serialize(connection.output);
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
                    // trace("entity update comenent " + entityId);
                    var componentTypeId = connection.input.readInt8();
                    // trace("componentTypeId " + componentTypeId);
                    // trace("componentTypes " + componentTypes);
                    var componentType = cast componentTypes[componentTypeId];
                    var entity = entities.get(entityId);
                    // trace(componentType);
                    var component = entity.get(componentType);
                    component.unserialize(connection.input);
                    em.dispatch(entity, cast component);
                    // trace("received net event");
                    // trace("gnnn " + (untyped component).x);

                case CREATE_TEMPLATE_ENTITY:
                    var entityId = connection.input.readInt16();
                    var templateId = connection.input.readInt8();
                    var entity = Reflect.field(em,'create' + entityFactory[templateId])();
                    entities.set(entityId, entity);
            }
        }
    }

    public function dispatch<T:CompTP>(entity:Entity, component:T)
    {
        // DUMMY, ACTUALLY USED FOR SERVER BUT PREVENT ISSUES
        // WHEN SHARING SAME SYSTEM BETWEEN CLIENT & SERVER
    }
    #end

    public function pump()
    {
        if(socket != null)
        {
            socket.pump();
            socket.flush();
        }
    }
}
