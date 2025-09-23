module example::example {

    use sui::display;
    use sui::package;
    use std::string::String;
    use sui::transfer::public_transfer;
    use sui::tx_context::sender;

    public struct ExampleNFT has key, store {
        id: UID,
        name: String,
        description: String,
        image_url: String,
    } 

    public struct EXAMPLE has drop {}

    fun init(otw: EXAMPLE, ctx: &mut TxContext) {
        let keys = vector[
            b"name".to_string(),
            b"link".to_string(),
            b"image_url".to_string(),
            b"description".to_string(),
            b"project_url".to_string(),
            b"creator".to_string(),
        ];

        let values = vector[
            // For `name` one can use the `ExampleNFT.name` property
            b"{name}".to_string(),
            // For `link` one can build a URL using an `ExampleNFT.id` property
            b"{link}".to_string(),
            // For `image_url` one can use the `ExampleNFT.image_url` property
            b"{image_url}".to_string(),
            // Description is static for all `ExampleNFT` objects.
            b"{description}".to_string(),
            // Project URL is usually static
            b"{project_url}".to_string(),
            // Creator field can be any ExampleNFT.creator
            b"{creator}".to_string(),
        ];

        let publisher = package::claim(otw, ctx);

        let mut display = display::new_with_fields<ExampleNFT>(
            &publisher, keys, values, ctx
        );
        
        display.update_version();

        public_transfer(publisher, ctx.sender());
        public_transfer(display, ctx.sender());
    }

    entry fun mint_nft(
        name: String,
        description: String,
        image_url: String,
        ctx: &mut TxContext
    ) {
        let nft = ExampleNFT { id: object::new(ctx), name, description, image_url };
        public_transfer(nft, sender(ctx));
    }
}