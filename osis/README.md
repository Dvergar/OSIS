`EntityManager.hx` is the core of the library.

`CustomNetworkTypes.hx` adds custom network types in addition to `@Short`, `@Bool`...  
Here i'm adding the `@Entity` network type so that only the entity id is actually sent through the wires but the user only plays with the `Entity` type.

`yec` folder is for yaml support which is disabled for now.