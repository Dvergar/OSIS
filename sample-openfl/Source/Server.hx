import Common;

import osis.EntityManager;


class Server
{
    var em:EntityManager = new EntityManager();
    var net:NetEntityManager;

    public function new()
    {
        var ec = new EntityCreator(em);
        
        net = em.listen("127.0.0.1", 32000);
        net.onConnection = onConnection;
        net.onDisconnection = onDisconnection;
        net.registerEvent(MessageHello, onMessage);
        net.registerEvent(PingPong, onPing);
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

    function onMessage(msg:MessageHello, connection:Connection)
    {
        trace("Message: " + msg.txt);
    }

    function onPing(msg:PingPong, connection:Connection)
    {
        trace("ping");
        net.sendEvent(msg);
    }
    
    function onConnection(connection:Connection)
    {
        trace("onConnection");
        var datPlayer = net.createEntity("player");
        net.bindEntity(connection, datPlayer);
        net.sendWorldStateTo(connection);
        trace("datplayer ID " + datPlayer.id);

        var msg = new MessageHello();
        msg.txt = "youhou";
        msg.entityId = datPlayer.id;
        net.sendEvent(msg);

        net.addComponent(datPlayer, new CTest());
    }

    function onDisconnection(conn:Connection)
    {
        trace("onDisconnection");
        var boundEntity = net.getBoundEntity(conn);
        net.destroyEntity(boundEntity);
    }

    static function main() {new Server();}
}
