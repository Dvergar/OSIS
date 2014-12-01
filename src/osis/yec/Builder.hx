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
        BuildComponents._build(fields, podstream.SerializerMacro._build);
        BuildEntities._build(fields);
        // podstream._build(fields);
        return fields;
    }
    // #end
}