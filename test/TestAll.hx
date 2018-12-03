import osis.EntityManager;


class Test
{
    public static function assertTrue(b:Bool):Void
    {
        if (b == false)
            throw "expected true but was false";
    }

    public static function assertFalse(b:Bool):Void
    {
        if (b == true)
            throw "expected false but was true";
    }

    public static function assertEquals<T>(actual:T, expected:T):Void
    {
        if (actual != expected)
            throw "expected '" + expected + "' but was '" + actual + "'";
    }

    public static function run(func:Void->Void)
    {

    }
}


class TestAll
{
    var em:EntityManager = new EntityManager();

    public function new()
    {
        em.addSystem(new SomethingSystem());
        run();
    }

    public function run():Void
    {
        // ENTITY TEST
        var entity = em.createEntity();

        //// FIRST ID SHOULD BE 0
        Test.assertEquals(entity.id, 0);

        // ENTITYSET TEST
        var entitySet = em.getEntitySet([CPosition, CVector]);
        //// FIRST ID SHOULD BE 0
        Test.assertEquals(entitySet._id, 0);

        var entity = em.createEntity();
        em.addComponent(entity, new CPosition());
        em.addComponent(entity, new CVector());

        //// CHECKING IF ENTITY HAS BEEN ADDED
        Test.assertEquals(entitySet._adds.length, 1);
        Test.assertEquals(entitySet.adds.length, 0);

        //// CHECKING ENTITY NOT YET ADDED TO ENTITIES
        Test.assertEquals(entitySet.entities.length, 0);

        //// CHECKING APPLYCHANGES ON ADDED
        entitySet.applyChanges();
        Test.assertEquals(entitySet.adds.length, 1);
        Test.assertEquals(entitySet._adds.length, 0);

        //// CHECKING APPLYCHANGES ON REMOVE
        em.removeComponent(entity, CVector);
        entitySet.applyChanges();
        Test.assertEquals(entitySet.removes.length, 1);
    }

    static function main():Void
    {
        new TestAll();
        trace("All tests passed");
    }
}



class CPosition implements Component
{
    public var x:Float = 0;
    public var y:Float = 0;

    public function new() {}
}


class CVector implements Component
{
    public var x:Float = 0;
    public var y:Float = 0;

    public function new() {}
}


class SomethingSystem extends System
{
    var entitySet:EntitySet;

    public function new()
    {
        super();
        trace("new");
        // TestAll.instance.assertTrue(true);
    }

    public override function init()
    {
        trace("init");
        // entitySet = em.getEntitySet([CNetPosition, CPosition]);
    }

    // public override function loop()
    // {
    //     entitySet.applyChanges();

    //     for(entity in entitySet.entities)
    //     {
    //         var netPos = entity.get(CNetPosition);
    //         var pos = entity.get(CPosition);

    //         netPos.x = pos.x;
    //         netPos.y = pos.y;
    //         // trace("netpos " + netPos);

    //         net.markChanged(entity, netPos);
    //     }
    // }
}