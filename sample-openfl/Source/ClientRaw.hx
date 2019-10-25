import osis.EntityManager;
import Common;

class CDrawable implements Component {
	public var imageName:String;

	public function new() {}
}

class ClientRaw {
	var em:EntityManager = new EntityManager();
	var net:NetEntityManager;

	public function new() {
		var ec = new EntityCreator(em);
		net = em.connect("127.0.0.1", 32000);
		net.addEvent(MessageHello, onMessage);
		net.addEvent(PingPong, onPong);
		em.addSystem(new DummySystem());

		while (true)
			loop();
	}

	function onMessage(msg:MessageHello, connection:Connection) {
		trace("Message: " + msg.txt);
		trace("Entity id: " + msg.entityId);

		var entity = net.entities.get(msg.entityId);
		trace("ctest " + entity.has(CTest));

		var msg = new MessageHello();
		msg.txt = "coucou";
		net.sendEvent(msg);
	}

	function onPong(msg:PingPong, connection:Connection) {
		trace("pong");
		var latency = haxe.Timer.stamp() - frames[msg.frameId];
		latency *= 1000;
		trace(latency);
	}

	var lastSend:Float = 0;
	var frameId:Int = 0;
	var frames:Array<Float> = new Array();

	function loop() {
		em.fixedUpdate(function() {
			frameId++;

			if (haxe.Timer.stamp() - lastSend > 1) {
				var ping = new PingPong();
				ping.frameId = frameId;
				net.sendEvent(ping);

				lastSend = haxe.Timer.stamp();
				frames[frameId] = lastSend;

				trace("send");
			}

			em.processAllSystems();
		});
	}

	static function main() {
		new ClientRaw();
	}
}
