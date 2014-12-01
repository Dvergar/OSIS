
import osis.EntityManager;

class Main
{
    public function new()
    {

        var em = new EntityManager();
        var player = em.createPlayer();
        trace(PositionComponent.__sid);
        var pos = player.get(PositionComponent);
        trace("pos " + pos.x);

        pos = em.addComponent(player, new PositionComponent());
        trace("pos " + pos.x);

        // trace("gnn");
        // var pos = new Test2();
        // pos.x = 100;
        // pos.y = 200;
        // trace(pos.x);
        // trace(pos.y);

        // var weaponDescr = new DescriptionComponent();
        // trace(weaponDescr.name);
        // trace(weaponDescr.text);
    }

    public static function main()
    {
        new Main();
    }
}
