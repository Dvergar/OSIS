import osis.EntityManager;
import Common;


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


class Server
{
    var net:NetEntityManager;
    var em:EntityManager;

    public function new()
    {
        em = new EntityManager();
        
        net = em.listen("192.168.1.4", 32000);
        net.onConnection = onConnection;
        net.onDisconnection = onDisconnection;
        em.addSystem(new MovementSystem());
        em.addSystem(new DummySystem());

        while(true)
        {
            em.fixedUpdate(function()
            {
                em.processAllSystems();
            });
        }
    }
    
    function onConnection(connection:Connection)
    {
        trace("onConnection");
        var datPlayer = net.create("Player");
        net.bindEntity(connection, datPlayer);
        net.sendWorldStateTo(connection);
    }

    function onDisconnection(conn:Connection)
    {
        trace("onDisconnection");
        var boundEntity = net.getBoundEntity(conn);
        net.destroyEntity(boundEntity);
    }

    static function main() {new Server();}
}
