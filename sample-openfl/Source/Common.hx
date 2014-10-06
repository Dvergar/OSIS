import ecs.EntityManager;

#if client
import Client;
#end



class CText extends Component
{
    @string public var value:String;

    public function new(?value:String)
    {
        this.value = value;
    }
}

class CPosition extends Component
{
    @short public var x:Int;
    @short public var y:Int;

    public function new(x:Int, y:Int)
    {
        this.x = x;
        this.y = y;
    }
}


class MovementSystem extends System
{
    public function new()
    {
        need([CPosition]);
    }

    public override function processEntities(entity:Entity)
    {
        var pos = entity.get(CPosition);
        pos.x += 1;
    }
}


class EntityCreator
{
    var em:EntityManager;

    public function new(em:EntityManager)
    {
        this.em = em;
        em.net.registerTemplate("player", player);
    }

    public function player(args:Dynamic)
    {
        var entity = em.createEntity();
        var pos = em.addComponent(entity, new CPosition(args.x, args.y), true);

        #if client
        em.addComponent(entity, new CDrawable("idassignation.PNG"));
        #end

        return entity;
    }
}


