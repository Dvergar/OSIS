package osis.yec;

import osis.EntityManager.Component;

import haxe.macro.Expr;
import haxe.macro.Context;

import yaml.Yaml;
import yaml.Parser;
import yaml.util.ObjectMap;


class Test extends Component
{}

class BuildComponents
{
    #if macro
    static public function _build(fields:Array<Field>):Array<Field>
    {
        trace("hello");

        var pos = Context.currentPos();

        // GET YAML PATH
        var yamlPath = Context.definedValue("yamlpath");
        if(yamlPath == null)
            throw("You need to define your yaml path with
                  '-D yamlpath=your/yaml/path/'");

        // PARSE YAML
        var data:AnyObjectMap  = Yaml.read(yamlPath + "components.yaml");

        // ALLOWED TYPES
        var allowedTypes = ["Int", "String", "Float", "Bool"];
        var allowedNetTypes = ["NetInt", "NetString", "NetFloat", "NetBool"];

        Context.defineType({
            pos: pos,
            params: [],
            pack: [],
            name: "Test2",
            fields: [],
            isExtern: false,
            meta: [],
            // kind: TDClass(TPath({name: "Component", pack: [], params: []}), [], false)
            kind: TDClass(null, [], false)
        });

        // ITERATE COMPONENTS
        for(componentName in data.keys())
        {
            var newArgs:Array<haxe.macro.FunctionArg> = new Array();
            var compFields:Array<Field> = new Array();
            var component:AnyObjectMap = data.get(componentName);
            var block:Array<haxe.macro.Expr> = [];

            trace("componentName " + componentName);

            // ITERATE FIELDS
            if(component != null)
                for(f in component.keys())
                {
                    var type = component.get(f);
                    var meta:Array<haxe.macro.MetadataEntry> = [];

                    trace("type |" + type + "|");

                    // CHECK IF TYPE EXISTS
                    if(!Lambda.has(allowedTypes, type) && !Lambda.has(allowedNetTypes, type))
                        throw("Type not allowed: " + type);

                    // CHECK IF NET TYPE
                    if(Lambda.has(allowedNetTypes, type))
                    {
                        type = type.substr(3, type.length - 3);
                        meta = [{ name: type, params: [], pos: pos }];
                        trace("afternettype " + type);
                    }

                    var tpath = TPath({name: type, pack: [], params: []});

                    // BUILD FIELD
                    compFields.push({kind: FVar(tpath, null),
                                     meta: meta,
                                     name: f,
                                     pos: pos,
                                     access: [APublic]});
                }

            compFields.push({kind: FFun({args: newArgs,
                                         expr: {expr: EBlock(block),
                                                pos: pos},
                                         params: [],
                                         ret: null}),
                             name: "new",
                             pos: pos,
                             meta: [],
                             access: [APublic]
            });

            // BEFORE DEFINETYPE, PLEASE :|
            podstream.SerializerMacro._build(compFields, componentName);
            // if(attachedComponentMacro != null)
            //     attachedComponentMacro(compFields);

            Context.defineType({
                pos: pos,
                params: [],
                pack: [],
                name: componentName,
                fields: compFields,
                isExtern: false,
                meta: [],
                // kind: TDClass(null, [], false),
                kind: TDClass({name: "EntityManager", sub: "Component", pack: ["osis"], params: []}, [], false)
            });


            for(f in compFields)
            {
                trace("Component " + new haxe.macro.Printer().printField(f));
                // trace("rawComponent " + f);
            }
        }

        return fields;
    }
    #end
}