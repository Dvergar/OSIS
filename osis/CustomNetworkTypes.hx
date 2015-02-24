package osis;

import haxe.macro.Expr;
import haxe.macro.Context;


class CustomNetworkTypes
{
    macro static public function build():Array<haxe.macro.Field>
    {
        var fields = Context.getBuildFields();

        var EntityType = {
            name:"Entity",
            serialize: function(varNameOut:String) {
                var a = [];
                a.push( macro var enId:Int = $i{varNameOut}.id );
                a.push( macro bo.writeInt32(enId) );
                return a;
            },
            unserialize: function(varNameIn:String) {
                return [ macro _netEntityId = bi.readInt32(),
                         macro _net = true];
            }
        };

        fields = podstream.SerializerMacro._build(fields, [EntityType]);

        return fields;
    }
}