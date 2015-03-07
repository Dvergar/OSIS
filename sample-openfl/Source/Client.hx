import flash.display.Bitmap;
import flash.display.Sprite;
import flash.display.DisplayObject;
import flash.display.DisplayObjectContainer;
import flash.events.KeyboardEvent;
import flash.events.MouseEvent;
import flash.events.Event;
import flash.ui.Keyboard;
import flash.Lib;
import openfl.Assets;

import osis.EntityManager;

import Common;


class CDrawable implements Component
{
    public var imageName:String;

    public function new() {}
}


class DrawableSystem extends System
{
    var sprites:Map<Int, Sprite> = new Map();
    var entitySet:EntitySet;

    public override function init()
    {
        entitySet = em.getEntitySet([CDrawable, CPosition]);
    }

    public override function loop()
    {
        entitySet.applyChanges();

        for(entity in entitySet.adds)
        {
            trace("onEntityAdded");
            var drawable = entity.get(CDrawable);
            var sprite = getSprite(drawable.imageName);
            Lib.current.addChild(sprite);
            sprites.set(entity.id, sprite);
        }

        for(entity in entitySet.changes)
        {
            var pos = entity.get(CPosition);
            var sprite = sprites.get(entity.id);

            sprite.x = pos.x;
            sprite.y = pos.y;
        }

        for(entity in entitySet.removes)
        {
            var drawable = entity.get(CDrawable);

            var sprite = sprites.get(entity.id);
            Lib.current.removeChild(sprite);
            sprites.remove(entity.id);
        }
    }

    public inline static function getBitmap(imageName:String)
    {
        var bitmapData = Assets.getBitmapData("assets/" + imageName);
        return new Bitmap(bitmapData);
    }

    public inline static function getSprite(imageName:String, ?centered:Bool)
    {
        var bitmap = DrawableSystem.getBitmap(imageName);
        if(centered)
        {
            bitmap.x -= bitmap.width / 2;
            bitmap.y -= bitmap.height / 2;
        }
        var sprite = new Sprite();
        sprite.addChild(bitmap);
        return sprite;
    }
}


class DebugSystem extends System
{
    var labels:Map<Int, flash.text.TextField> = new Map();
    var entitySet:EntitySet;

    public override function init()
    {
        entitySet = em.getEntitySet([CTest, CPosition]);
    }

    public override function loop()
    {
        entitySet.applyChanges();

        for(entity in entitySet.adds)
        {
            trace("ondebug added");
            var pos = entity.get(CPosition);
            var label = new flash.text.TextField();
            label.textColor = 0xFF0000;
            label.x = pos.x;
            label.y = pos.y + 80;
            label.text = "boom boom";
            Lib.current.addChild(label);
            labels.set(entity.id, label);
        }

        for(entity in entitySet.changes)
        {
            var pos = entity.get(CPosition);
            var label = labels.get(entity.id);

            label.x = pos.x;
            label.y = pos.y + 80;
        }

        for(entity in entitySet.removes)
        {
            var label = labels.get(entity.id);
            Lib.current.removeChild(label);
            labels.remove(entity.id);
        }
    }
}


class Client
{
    var em:EntityManager = new EntityManager();
    var net:NetEntityManager;

    public function new()
    {
        var ec = new EntityCreator(em);
        net = em.connect("127.0.0.1", 32000);
        net.registerEvent(MessageHello, onMessage);
        net.registerEvent(PingPong, onPong);
        em.addSystem(new DrawableSystem());
        em.addSystem(new DummySystem());
        em.addSystem(new DebugSystem());

        Lib.current.stage.addEventListener(Event.ENTER_FRAME, loop);
    }

    function onMessage(msg:MessageHello, connection:Connection)
    {
        trace("Message: " + msg.txt);
        trace("Entity id: " + msg.entityId);

        var entity = net.entities.get(msg.entityId);
        trace("ctest " + entity.has(CTest));

        var msg = new MessageHello();
        msg.txt = "coucou";
        net.sendEvent(msg);
    }

    function onPong(msg:PingPong, connection:Connection)
    {
        trace("pong");
        var latency = haxe.Timer.stamp() - frames[msg.frameId];
        latency *= 1000;
        trace(latency);
    }

    var lastSend:Float = 0;
    var frameId:Int = 0;
    var frames:Array<Float> = new Array();

    function loop(event:Event)
    {
        frameId++;

        em.fixedUpdate(function()
        {
            if(haxe.Timer.stamp() - lastSend > 1)
            {
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
}
