import ecs.EntityManager;
import protohx.Protohx;
import haxe.io.BytesOutput;
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

    public function new()
    {
    	var em = new EntityManager();
    	var ec = new EntityCreator(em);
    	this.net = em.net;
    	net.server("192.168.1.4", 32000);
    	net.socket.onConnection = onConnection;
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
		trace("connectionplop");
    	// var entity = net.createEntity();
     //    net.addComponent(entity, new CText("how"));

        net.create("player", {x:200, y:200});
        var newPlayer = net.create("player", {x:400, y:400});
        net.attachConnection(connection, newPlayer);
        // net.sendWorldStateTo(connection, newPlayer);
        // net.destroyEntity(lel);
	}

    static function main() {new Server();}
}
