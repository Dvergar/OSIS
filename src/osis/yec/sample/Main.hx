import osis.EntityManager;


class Main
{
    public function new()
    {
        var em = new EntityManager();

        var player = em.createPlayer();
        var pos = player.get(CPosition);
        trace("pos " + pos.x);

        pos = em.addComponent(player, new CPosition());
        trace("pos " + pos.x);
    }

    public static function main()
    {
        new Main();
    }
}
