import osis.EntityManager;


#if client
import Client;
#end



class MessageHello implements IMessage
{
    @String public var txt:String;

    public function new() {}

}


class CPosition implements Component
{
    @Short public var x:Float = 0;
    @Short public var y:Float = 0;

    public function new() {}
}


class DummySystem extends System
{
    public function new()
    {
        need([CPosition]);
    }

    public override function onEntityChange(entity:Entity)
    {
        // trace("dummy change");
    }
}


class MovementSystem extends System
{
    public function new()
    {
        need([CPosition]);
    }

    public override function processEntity(entity:Entity)
    {
        var pos = entity.get(CPosition);
        pos.x += 0.1;
        net.markChanged(entity, pos);
    }
}


class EntityCreator
{
    var em:EntityManager;

    public function new(em:EntityManager)
    {
        this.em = em;
        em.registerTemplate("player", createPlayer);
    }

    public function createPlayer()
    {
        var entity = em.createEntity();
        var pos = em.addComponent(entity, new CPosition());

        #if client
        var drawable = new CDrawable();
        drawable.imageName = "soldier_idle.png";
        em.addComponent(entity, drawable);
        #end

        return entity;
    }
}