import osis.EntityManager;


class MovementSystem extends System
{
    public function new()
    {
        need([CPosition]);
    }

    public override function processEntity(entity:Entity)
    {
        entity.get(CPosition).x += 0.1;
        em.net.dispatch(entity, entity.get(CPosition));
    }
}

