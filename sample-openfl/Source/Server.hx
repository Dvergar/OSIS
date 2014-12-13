import osis.EntityManager;
import Common;


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
        net.registerEvent("MESSAGE", onMessage);
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

    function onMessage(o:Dynamic)
    {
        trace("o " + o.txt);
    }
    
    function onConnection(connection:Connection)
    {
        trace("onConnection");
        var datPlayer = net.create("Player");
        net.bindEntity(connection, datPlayer);
        net.sendWorldStateTo(connection);
        net.sendEvent("MESSAGE", {txt:"hello"});
    }

    function onDisconnection(conn:Connection)
    {
        trace("onDisconnection");
        var boundEntity = net.getBoundEntity(conn);
        net.destroyEntity(boundEntity);
    }

    static function main() {new Server();}
}
