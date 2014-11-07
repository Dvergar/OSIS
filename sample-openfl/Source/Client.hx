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

import ecs.EntityManager;

import Common;


class CDrawable extends Component
{
    public var imageName:String;

    public function new(imageName:String)
    {
        this.imageName = imageName;
    }
}


// class DrawableSystem extends System
// {
//     var sprites:Map<Int, Sprite> = new Map();

//     public function new()
//     {
//         need([CDrawable, CPosition]);
//     }

//     public override function onEntityAdded(entity:Entity)
//     {
//         var drawable = entity.get(CDrawable);
//         var sprite = getSprite(drawable.imageName);
//         Lib.current.addChild(sprite);
//         sprites.set(entity.id, sprite);
//     }

//     public override function onEntityRemoved(entity:Entity)
//     {
//         var drawable = entity.get(CDrawable);

//         trace("entityid " + entity.id);
//         trace("spritse " + sprites);
//         var sprite = sprites.get(entity.id);
//         Lib.current.removeChild(sprite);
//         sprites.remove(entity.id);
//     }

//     public override function processEntities(entity:Entity)
//     {
//         var pos = entity.get(CPosition);
//         var sprite = sprites.get(entity.id);

//         sprite.x = pos.x;
//         sprite.y = pos.y;
//     }

//     public inline static function getBitmap(imageName:String)
//     {
//         var bitmapData = Assets.getBitmapData("assets/" + imageName);
//         return new Bitmap(bitmapData);
//     }

//     public inline static function getSprite(imageName:String, ?centered:Bool)
//     {
//         var bitmap = DrawableSystem.getBitmap(imageName);
//         if(centered)
//         {
//             bitmap.x -= bitmap.width / 2;
//             bitmap.y -= bitmap.height / 2;
//         }
//         var sprite = new Sprite();
//         sprite.addChild(bitmap);
//         return sprite;
//     }
// }


// class Client
// {
//     var em:EntityManager = new EntityManager();

//     public function new()
//     {
//         var ec = new EntityCreator(em);
//         var net = em.net;
//         net.connect("192.168.1.4", 32000);
//         em.addSystem(new DrawableSystem());

//         Lib.current.stage.addEventListener(Event.ENTER_FRAME, loop);
//     }

//     function loop(event:Event)
//     {
//         em.fixedUpdate(function()
//         {
//             em.processSystem(DrawableSystem);
//         });
//     }
// }

class DrawableSystem
{
    var sprites:Map<Int, Sprite> = new Map();
    var entities:EntitySet;

    public function new(ed:EntityData)
    {
        entities = ed.getEntities([CPosition, CDrawable]);
    }

    public function update()
    {
        if(entities.applyChanges())
        {
            for(entity in entities.addedEntities)
            {
                var drawable = entity.get(CDrawable);
                var pos = entity.get(CPosition);

                trace("pos " + pos.x);
                trace("image " + drawable.imageName);

                var sprite = getSprite(drawable.imageName);
                Lib.current.addChild(sprite);
                sprites.set(entity.id, sprite);
            }

            for(entity in entities.changedEntities)
            {
                trace("change");
                var pos = entity.get(CPosition);
                var sprite = sprites.get(entity.id);
                sprite.x = pos.x;
                sprite.y = pos.y;
            }
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


class InputSystem
{
    var entities:EntitySet;

    public function new(ed:EntityData)
    {
        entities = ed.getEntities([CPosition]);

        Lib.current.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        Lib.current.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyUp);
    }

    var left:Bool;
    var right:Bool;
    var up:Bool;
    var down:Bool;

    function onKeyDown(ev:KeyboardEvent)
    {
        if(ev.keyCode == Keyboard.LEFT) left = true;
        if(ev.keyCode == Keyboard.RIGHT) right = true;
        if(ev.keyCode == Keyboard.UP) up = true;
        if(ev.keyCode == Keyboard.DOWN) down = true;
    }

    function onKeyUp(ev:KeyboardEvent)
    {
        if(ev.keyCode == Keyboard.LEFT) left = false;
        if(ev.keyCode == Keyboard.RIGHT) right = false;
        if(ev.keyCode == Keyboard.UP) up = false;
        if(ev.keyCode == Keyboard.DOWN) down = false;
    }

    public function update()
    {
        entities.applyChanges();

        for(entity in entities.entities)
        {
            var pos = entity.get(CPosition);
            var newpos = new CPosition(pos.x, pos.y);

            if(left) newpos.x -= 5;
            if(right) newpos.x += 5;
            if(up) newpos.y -= 5;
            if(down) newpos.y += 5;
            // trace("wot " + newpos.x);

            entity.set(newpos);
        }
    }
}


class Client
{
    var drawableSystem:DrawableSystem;
    var inputSystem:InputSystem;

    public function new()
    {
        var ed = new EntityData();
        var entity = ed.createEntity();
        entity.set(new CDrawable("idassignation.PNG"));

        drawableSystem = new DrawableSystem(ed);
        trace("inputsystem");
        inputSystem = new InputSystem(ed);

        entity.set(new CPosition(200, 300));

        Lib.current.stage.addEventListener(Event.ENTER_FRAME, loop);
    }

    function loop(event:Event)
    {
        drawableSystem.update();
        inputSystem.update();

        // throw("lel");
    }
}