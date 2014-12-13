package osis.yec;

import haxe.macro.Expr;
import haxe.macro.Context;

import osis.yec.BuildComponents;


class Builder
{
    // #if macro
    // static public function _build(fields:Array<Field>):Array<Field>
    // {
    //     BuildComponents._build(fields);
    //     return fields;
    // }
    // #end
// 
    // #if macro
    macro static public function build():Array<Field>
    {
        trace("wat");
        var fields:Array<Field> = Context.getBuildFields();
        var pos = Context.currentPos();
        BuildComponents._build(fields);
        BuildEntities._build(fields, pos);
        // podstream._build(fields);
        return fields;
    }
    // #end
}