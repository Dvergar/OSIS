package osis.yec;

import haxe.macro.Expr;
import haxe.macro.Context;

import osis.yec.BuildComponents;


class Builder
{
    macro static public function build():Array<Field>
    {
        trace("wat");
        var fields:Array<Field> = Context.getBuildFields();
        var pos = Context.currentPos();
        BuildComponents._build(fields);
        BuildEntities._build(fields, pos);
        return fields;
    }
}