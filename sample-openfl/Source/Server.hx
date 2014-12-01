import osis.EntityManager;
// import haxe.io.BytesOutput;
import anette.*;
import Common;


class PositionSystem extends System
{
	public function new()
	{
		need([CPosition]);
	}
}

class LelSystem extends System
{
	public function new()
	{
		need([CPosition]);
	}
}



class Server
{
	var net:NetEntityManager;
    var em:EntityManager;
    // var ec:EntityCreator;

    public function new()
    {
    	em = new EntityManager();
    	// ec = new EntityCreator(em);
    	net = em.net;
    	net.server("192.168.1.4", 32000);
        net.socket.onConnection = onConnection;
    	net.socket.onDisconnection = onDisconnection;
    	em.addSystem(new MovementSystem());

        // DEBUG
        // var entity = em.createEntity();
        // net.addComponent(entity, new CText("how"));

    	while(true)
    	{
    		em.fixedUpdate(function()
    		{
    			em.processSystem(MovementSystem);
			});
    	}
    }
    
	function onConnection(connection:Connection)
	{
		trace("onConnection");

        var datPlayer = net.create("Player");
        // net.bindEntity(connection, datPlayer);
        // net.sendWorldStateTo(connection);
	}

    function onDisconnection(conn:Connection)
    {
        trace("onDisconnection");
        var boundEntity = net.getBoundEntity(conn);
        net.destroyEntity(boundEntity);
    }

    static function main() {new Server();}
}
