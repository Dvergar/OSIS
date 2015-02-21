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
                // a.push( macro trace("1entityid " + ($i{varNameOut}).id) );
                a.push( macro var enId:Int = $i{varNameOut}.id );
                // a.push( macro trace(enId) );
                // a.push( macro bo = cast(bo, haxe.io.BytesOutput) );
                // a.push( macro bo.writeInt32(5) );
                a.push( macro bo.writeInt32(enId) );
                return a;
                // return [macro trace("1entityid " + ($i{varNameOut}).id),
                //         macro var enId = $i{varNameOut}.id,
                //         macro bo.writeInt32(enId),
                //          ];
            },
            unserialize: function(varNameIn:String) {
                return [ macro _netEntityId = bi.readInt32(),
                         macro _net = true,
                         macro trace(_net) ];
                        // macro $i{varNameIn} = bi.readInt32() ];
            }
        };


        fields = podstream.SerializerMacro._build(fields, [EntityType]);

        return fields;
    }
}