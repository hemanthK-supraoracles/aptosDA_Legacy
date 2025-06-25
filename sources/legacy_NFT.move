module MOON::token_management {
    use std::signer;
    use std::vector;
    use std::option;
    use std::string::{Self, String};
    use std::debug;
    use std::bcs;
    use 0x3::token::{Self, TokenDataId};

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_TOKEN_DOES_NOT_EXIST: u64 = 2;
    const E_INSUFFICIENT_BALANCE: u64 = 3;
    const E_INSUFFICIENT_TOKEN_BALANCE: u64 = 4;
    const E_TOKEN_ALREADY_EXISTS: u64 = 5;

    const BURNABLE_BY_CREATOR: vector<u8> = b"TOKEN_BURNABLE_BY_CREATOR";
    const BURNABLE_BY_OWNER: vector<u8> = b"TOKEN_BURNABLE_BY_OWNER";
    const TOKEN_PROPERTY_MUTABLE: vector<u8> = b"TOKEN_PROPERTY_MUTATBLE";

    /// Resource to store token management data
    struct TokenManager has key {
        vec_token_data_id: vector<TokenDataId>
        // token_data_id: TokenDataId
    }

    /// Initialize the token collection and create a token
    public entry fun initialize_collection_and_create_token(
        account: &signer,
        collection_name: String,
        collection_description: String,
        collection_uri: String,
        token_name: String,
        token_description: String,
        token_uri: String,
        maximum_collection: u64,
        maximum_token: u64
    ) acquires TokenManager {
        let creator = signer::address_of(account);

        assert!(creator == @MOON, E_NOT_AUTHORIZED);

        // Create collection
        token::create_collection(
            account,
            collection_name,
            collection_description,
            collection_uri,
            maximum_collection,
            vector<bool>[true, true, true]
        );
        let mutate_config = vector<bool>[
            true, // control if the token properties are mutable
            true, // control if the token royalty is mutable
            true, // control if the token description is mutable
            true, // control if the token uri is mutable
            true,
            true
        ];

        let token_mut = token::create_token_mutability_config(&mutate_config);

        // Create token
        let token_data_id =
            token::create_tokendata(
                account,
                collection_name,
                token_name,
                token_description,
                maximum_token,
                token_uri,
                creator,
                0, // royalty denominator
                0, // royalty numerator
                token_mut,
                vector<String>[string::utf8(BURNABLE_BY_OWNER), string::utf8(BURNABLE_BY_CREATOR), string::utf8(TOKEN_PROPERTY_MUTABLE)],
                vector<vector<u8>>[bcs::to_bytes<bool>(&true), bcs::to_bytes<bool>(&true), bcs::to_bytes<bool>(&true)],
                vector<String>[string::utf8(b"bool"), string::utf8(b"bool"), string::utf8(b"bool")]
            );

        if (!exists<TokenManager>(creator)) {
            move_to(
                account,
                TokenManager {
                    vec_token_data_id: vector<TokenDataId>[token_data_id]
                }
            );
        } else {
            let token_manager = borrow_global_mut<TokenManager>(creator);
            vector::push_back(&mut token_manager.vec_token_data_id, token_data_id);
        };

    }

    /// Mint tokens
    public entry fun mint_token(
        account: &signer,
        collection_name: String,
        token_name: String,
        amount: u64
    ) acquires TokenManager {
        let token_data_id = find_token_data_id(collection_name, token_name);

        token::mint_token(account, token_data_id, amount);

    }

    /// Transfer tokens to another address
    public entry fun transfer_token(
        sender: &signer,
        receiver: address,
        collection_name: String,
        token_name: String,
        amount: u64
    ) acquires TokenManager {

        let token_data_id = find_token_data_id(collection_name, token_name);

        let token_id = token::create_token_id(token_data_id, 0);
        // Verify balance
        let balance = token::balance_of(signer::address_of(sender), token_id);
        debug::print(&balance);
        assert!(balance >= amount, E_INSUFFICIENT_TOKEN_BALANCE);

        token::transfer(sender, token_id, receiver, amount);

    }

    /// Burn tokens
    public entry fun burn_token(
        account: &signer,
        amount: u64,
        collection_name: String,
        token_name: String,
        property_version: u64
    ) acquires TokenManager {
        let creator = @MOON;

        let token_data_id = find_token_data_id(collection_name, token_name);

        let token_id = token::create_token_id(token_data_id, 0);
        // Verify balance
        let balance = token::balance_of(signer::address_of(account), token_id);
        assert!(balance >= amount, E_INSUFFICIENT_TOKEN_BALANCE);

        token::burn(
            account,
            creator,
            collection_name,
            token_name,
            property_version,
            amount
        );

    }

    /// Mutate token properties
    public entry fun mutate_token_properties(
        account: &signer,
        collection_name: String,
        token_name: String,
        new_description: String,
        new_uri: String,
        new_maximum: u64
    ) acquires TokenManager {

        let token_data_id = find_token_data_id(collection_name, token_name);

        token::mutate_tokendata_description(account, token_data_id, new_description);

        token::mutate_tokendata_uri(account, token_data_id, new_uri);

        token::mutate_tokendata_maximum(account, token_data_id, new_maximum);

    }

    /// Get token balance
    #[view]
    public fun get_token_balance(
        account: address, collection_name: String, token_name: String
    ): u64 acquires TokenManager {
        let token_data_id = find_token_data_id(collection_name, token_name);
        let token_id = token::create_token_id(token_data_id, 0);

        let message1 = string::utf8(b"token_id is :");
        debug::print(&token_id);

        let balance = token::balance_of(account, token_id);

        balance
    }

    #[view]
    public fun get_token_data_id(
        account: address, collection_name: String, token_name: String
    ): TokenDataId acquires TokenManager {
        let token_data_id = find_token_data_id(collection_name, token_name);
        token_data_id
    }

    fun find_token_data_id(
        collection_name: String, token_name: String
    ): TokenDataId acquires TokenManager {
        let creator = @MOON;
        let token_manager = borrow_global<TokenManager>(creator);
        let length: u64 = vector::length(&token_manager.vec_token_data_id);
        let i: u64 = 0;
        let found: bool = false;
        let result = option::none<TokenDataId>();
        while (i < length) {
            let token_data_id = vector::borrow(&token_manager.vec_token_data_id, i);
            let (creator_address, collection, name) =
                token::get_token_data_id_fields(token_data_id);
            if (creator_address == creator
                && collection == collection_name
                && name == token_name) {
                // Found the matching token data ID
                found = true;
                result = option::some(*token_data_id);
            };
            i = i + 1;
        };
        assert!(found, E_TOKEN_DOES_NOT_EXIST);
        option::extract(&mut result)
    }
}
