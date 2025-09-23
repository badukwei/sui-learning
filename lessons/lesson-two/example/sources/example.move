module example::example {

    use std::string;
    use std::string::String;
    use sui::transfer::transfer;
    use sui::tx_context::sender;

    public struct ExampleNFT has key {
        id: UID,
        name: String,
        description: String,
        url: String,
    }

    fun init(ctx: &mut TxContext) {
        let default_nft = ExampleNFT {
            id: object::new(ctx),
            name: string::utf8(b"Example NFT"),
            description: string::utf8(b"Example NFT Description"),
            url: string::utf8(b"https://example.com"),
        };
        transfer(default_nft, sender(ctx));
    }

    public entry fun mint_nft(
        name: String,
        description: String,
        url: String,
        ctx: &mut TxContext
    ) {
        let nft = ExampleNFT { id: object::new(ctx), name, description, url };
        transfer(nft, sender(ctx));
    }
}