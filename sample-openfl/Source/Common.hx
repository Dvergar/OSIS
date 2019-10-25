import osis.EntityManager;
#if (client && !raw)
import Client;
#end
#if raw
import ClientRaw;
#end

class MessageHello implements Message {
	@String public var txt:String;
	@Short public var entityId:Int = -1;

	public function new() {}
}

class PingPong implements Message {
	@Int public var frameId:Int;

	public function new() {}
}

class CPosition implements Component {
	@Short public var x:Float = 0;
	@Short public var y:Float = 0;

	public function new() {}
}

class CTest implements Component {
	@Short public var z:Float = 0;

	public function new() {}
}

class DummySystem extends System {
	public function new()
		super();
}

class MovementSystem extends System {
	var entitySet:EntitySet;

	public override function init()
		entitySet = em.getEntitySet([CPosition]);

	public override function loop() {
		entitySet.applyChanges();

		for (entity in entitySet.entities) {
			var pos = entity.get(CPosition);
			pos.x += 0.1;
			net.markChanged(entity, pos);
		}
	}
}

class EntityCreator {
	var em:EntityManager;

	public function new(em:EntityManager) {
		this.em = em;
		em.addTemplate("player", createPlayer);
	}

	public function createPlayer() {
		var entity = em.createEntity();
		var pos = em.addComponent(entity, new CPosition());
		// em.addComponent(entity, new CTest());

		#if client
		var drawable = new CDrawable();
		drawable.imageName = "soldier_idle.png";
		em.addComponent(entity, drawable);
		#end

		return entity;
	}
}
