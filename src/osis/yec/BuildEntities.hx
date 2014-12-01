package osis.yec;

import haxe.macro.Expr;
import haxe.macro.Context;

import yaml.Yaml;
import yaml.Parser;
import yaml.util.ObjectMap;


class BuildEntities
{
    #if macro
    static public function _build(fields:Array<Field>):Array<Field>
    {
        var yamlPath = Context.definedValue("yamlpath");
        if(yamlPath == null)
            throw("You need to define your yaml path with
                  '-D yamlpath your/yaml/path/'");
        var data:AnyObjectMap  = Yaml.read(yamlPath + "entities.yaml");

        // var fields = Context.getBuildFields();
        var pos = Context.currentPos();

        trace(data);
        for(entityName in data.keys())
        {
            trace("entityNAme " + entityName);
            var entity:AnyObjectMap = data.get(entityName);
            trace("entity " + entity);

            var block = [];

            // CREATE ENTITY
            block.push(macro var entity = createEntity());

            function buildEntity(component:AnyObjectMap, componentName:String)
            {
                // var component:AnyObjectMap = entity.get(componentName);
                var instanceName = componentName.toLowerCase();

                // DECLARE NEW COMPONENTS
                block.push({
                    expr: EVars([{
                        expr: {
                            expr: ENew({
                                name: componentName,
                                pack: [],
                                params: []},
                                []),
                            pos: pos
                        },
                        name: instanceName,
                        type: null }]),
                    pos:pos
                });

                // ITERATE OVER COMPONENT VALUES
                for(f in component.keys())
                {
                    var varType = null;

                    trace("f " + f);
                    var value = component.get(f);
                    trace(value);
                    trace("type " + Type.typeof(value));

                    if(Type.typeof(value) == TInt)
                        varType = CInt;
                    else
                        varType = CString;

                    block.push(macro $i{instanceName}.$f = $v{value});
                }

                // ATTACH COMPONENT TO ENTITY
                block.push(macro addComponent(entity, $i{instanceName}));
            }

            for(componentName in entity.keys())
            {
                var component:AnyObjectMap = entity.get(componentName);

                if(componentName == "CLIENT")
                {
                    #if client
                    for(subComponentName in component.keys())
                    {
                        var subComponent:AnyObjectMap = component.get(subComponentName);
                        buildEntity(subComponent, subComponentName);
                    }
                    #end
                }

                else if(componentName == "SERVER")
                {
                    #if server
                    for(subComponentName in component.keys())
                    {
                        var subComponent:AnyObjectMap = component.get(subComponentName);
                        buildEntity(subComponent, subComponentName);
                    }
                    #end
                }
                else
                {
                    buildEntity(component, componentName);
                }
            }


            var func = {args:[],
                        ret:null,
                        params:[],
                        expr:{expr:EBlock(block), pos:pos}};

        // haxe.macro.Context.onGenerate(function (types)
        // {
            fields.push({name: "create" + entityName,
                         doc: null,
                         meta: [],
                         access: [APublic],
                         kind: FFun(func),
                         pos: pos});
        // });
        }

        for(f in fields)
        {
            trace("Serialized : " + new haxe.macro.Printer().printField(f));
            trace("gnn " + f);
        }

        return fields;
    }
    #end
}