import osis.EntityManager;


class MovementSystem extends System
{
    public function new()
    {
        need([CPosition]);
    }

    public override function processEntity(entity:Entity)
    {
        trace("entity update " + entity.id);
        entity.get(CPosition).x += 0.1;
        trace("compopos " + entity.get(CPosition).x);
        em.net.markChanged(entity, entity.get(CPosition));
    }
}

