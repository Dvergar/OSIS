package osis;

import haxe.macro.Expr;
import haxe.macro.Context;

class CustomNetworkTypes {
	macro static public function build():Array<haxe.macro.Field> {
		var fields = Context.getBuildFields();

		var EntityType = {
			name: "Entity",
			serialize: function(varNameOut:String) {
				var a = [];
				a.push(macro var enId:Int = NetEntityManager.instance.entities.reverse.get($i{varNameOut}));
				a.push(macro bo.writeInt32(enId));
				return a;
			},
			unserialize: function(varNameIn:String) {
				var a = [];
				a.push(macro var _netEntityId = bi.readInt32());
				a.push(macro $i{varNameIn} = NetEntityManager.instance.entities.get(_netEntityId));
				return a;
			}
		};

		fields = podstream.SerializerMacro._build(fields, [EntityType]);

		return fields;
	}
}
