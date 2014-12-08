import osis.EntityManager;


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

