package;

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


class DrawableSystem extends System
{
    var sprites:Map<Int, Sprite> = new Map();

    public function new()
    {
        need([CDrawable, CPosition]);
    }

    public override function onEntityAdded(entity:Entity)
    {
        trace("onEntityAdded");
        var drawable = entity.get(CDrawable);
        var sprite = getSprite(drawable.imageName);
        Lib.current.addChild(sprite);
        sprites.set(entity.id, sprite);
    }

    public override function onEntityRemoved(entity:Entity)
    {
        var drawable = entity.get(CDrawable);

        var sprite = sprites.get(entity.id);
        Lib.current.removeChild(sprite);
        sprites.remove(entity.id);
    }

    public override function onEntityChange(entity:Entity)
    {
        trace("entity change");
        var pos = entity.get(CPosition);
        var sprite = sprites.get(entity.id);

        sprite.x = pos.x;
        sprite.y = pos.y;
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


class Client
{
    var em:EntityManager = new EntityManager();

    public function new()
    {
        var net = em.connect("192.168.1.4", 32000);
        em.addSystem(new DrawableSystem());
        em.addSystem(new DummySystem());

        Lib.current.stage.addEventListener(Event.ENTER_FRAME, loop);
    }

    function loop(event:Event)
    {
        em.fixedUpdate(function()
        {
            em.processAllSystems();
        });
    }
}
