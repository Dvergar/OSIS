import osis.EntityManager;


#if client
import ClientRaw;
#end



class MessageHello implements IMessage
{
    @String public var txt:String;
    @Short public var entityId:Int = -1;

    public function new() {}
}


class PingPong implements IMessage
{
    @Int public var frameId:Int;

    public function new() {}
}


class CPosition implements Component
{
    @Short public var x:Float = 0;
    @Short public var y:Float = 0;

    public function new() {}
}

class CTest implements Component
{
    @Short public var z:Float = 0;

    public function new() {}
}


class DummySystem extends System
{
    public function new()
    {
        super();
        // need([CPosition]);

    }

    // public override function onEntityChange(entity:Entity)
    // {
    //     // trace("dummy change");
    // }
}


class MovementSystem extends System
{
    var entitySet:EntitySet;

    public override function init()
    {
        entitySet = em.getEntitySet([CPosition]);

    }

    // public override function processEntity(entity:Entity)
    // {
    //     var pos = entity.get(CPosition);
    //     pos.x += 0.1;
    //     net.markChanged(entity, pos);
    // }

    public override function loop()
    {
        // trace("loop");
        entitySet.applyChanges();

        for(entity in entitySet.entities)
        {
            var pos = entity.get(CPosition);
            pos.x += 0.1;
            net.markChanged(entity, pos);
        }
    }
}


class EntityCreator
{
    var em:EntityManager;

    public function new(em:EntityManager)
    {
        this.em = em;
        em.net.registerTemplate("player", createPlayer);
    }

    public function createPlayer()
    {
        var entity = em.createEntity();
        var pos = em.addComponent(entity, new CPosition());
        // em.addComponent(entity, new CTest());

        #if client
        var drawable = new CDrawable();
        drawable.imageName = "soldier_idle.png";
        em.addComponent(entity, drawable);
        #end

        return entity;
    }
}