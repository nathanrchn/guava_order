module guava_order::tests {
    use std::debug;

    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::clock::{Self, Clock};
    use sui::test_scenario::{Self, ctx, next_tx};

    use guava_order::order::{Self, Order, Stream, WrappedObject};

    const MIST: u64 = 1_000_000;

    struct TestObject has key, store {
        id: UID
    }

    #[test]
    fun create_order_and_basic_balance() {
        let admin = @0x1;
        let client = @0xA;
        let seller = @0xB;
        let scenario = test_scenario::begin(admin);
        let test = &mut scenario;

        let clock = clock::create_for_testing(ctx(test));

        next_tx(test, client);
        {
            let coin = coin::mint_for_testing<SUI>(10 * MIST, ctx(test));
            order::create_order<TestObject, SUI>(seller, coin, 1000, 10000, &clock, ctx(test));
        };

        next_tx(test, admin);
        {
            let created_order = test_scenario::take_shared<Order<TestObject, SUI>>(test);
            assert!(order::get_client(&created_order) == client, 0);
            assert!(order::get_seller(&created_order) == seller, 0);
            assert!(order::is_order_fulfilled(&created_order) == false, 0);

            let stream = order::get_stream(&created_order);

            let client_balance = order::balance_of_stream_<SUI>(stream, clock::timestamp_ms(&clock), client);
            assert!(client_balance == 0 * MIST, 0);
            let seller_balance = order::balance_of_stream_<SUI>(stream, clock::timestamp_ms(&clock), seller);
            assert!(seller_balance == 10 * MIST, 0);

            clock::increment_for_testing(&mut clock, 100);

            let client_balance = order::balance_of_stream_<SUI>(stream, clock::timestamp_ms(&clock), client);
            assert!(client_balance == 0 * MIST, 0);
            let seller_balance = order::balance_of_stream_<SUI>(stream, clock::timestamp_ms(&clock), seller);
            assert!(seller_balance == 10 * MIST, 0);

            clock::increment_for_testing(&mut clock, 900);

            let client_balance = order::balance_of_stream_<SUI>(stream, clock::timestamp_ms(&clock), client);
            assert!(client_balance == 0 * MIST, 0);
            let seller_balance = order::balance_of_stream_<SUI>(stream, clock::timestamp_ms(&clock), seller);
            assert!(seller_balance == 10 * MIST, 0);

            clock::increment_for_testing(&mut clock, 100);

            let client_balance = order::balance_of_stream_<SUI>(stream, clock::timestamp_ms(&clock), client);
            assert!(client_balance == 9999380, 0);
            let seller_balance = order::balance_of_stream_<SUI>(stream, clock::timestamp_ms(&clock), seller);
            assert!(seller_balance == 620, 0);

            clock::increment_for_testing(&mut clock, 100);

            let client_balance = order::balance_of_stream_<SUI>(stream, clock::timestamp_ms(&clock), client);
            assert!(client_balance == 9997530, 0);
            let seller_balance = order::balance_of_stream_<SUI>(stream, clock::timestamp_ms(&clock), seller);
            assert!(seller_balance == 2470, 0);

            clock::increment_for_testing(&mut clock, 8800);

            let client_balance = order::balance_of_stream_<SUI>(stream, clock::timestamp_ms(&clock), client);
            assert!(client_balance == 0, 0);
            let seller_balance = order::balance_of_stream_<SUI>(stream, clock::timestamp_ms(&clock), seller);
            assert!(seller_balance == 10_000_000, 0);

            test_scenario::return_shared<Order<TestObject, SUI>>(created_order);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun fulfill_order_in_time() {
        let admin = @0x1;
        let client = @0xA;
        let seller = @0xB;
        let scenario = test_scenario::begin(admin);
        let test = &mut scenario;

        let clock = clock::create_for_testing(ctx(test));

        next_tx(test, client);
        {
            let coin = coin::mint_for_testing<SUI>(10 * MIST, ctx(test));
            order::create_order<TestObject, SUI>(seller, coin, 1000, 10000, &clock, ctx(test));
        };

        next_tx(test, seller);
        {
            let created_order = test_scenario::take_shared<Order<TestObject, SUI>>(test);

            let stream = order::get_stream(&created_order);

            clock::increment_for_testing(&mut clock, 100);

            let id = object::new(ctx(test));
            let key = object::uid_to_inner(&id);

            order::wrap_object<TestObject, SUI>(&mut created_order, TestObject { id }, ctx(test));
            test_scenario::return_shared<Order<TestObject, SUI>>(created_order);
            debug::print(&key);
        };

        next_tx(test, seller);
        {
            let created_order = test_scenario::take_shared<Order<TestObject, SUI>>(test);

            let wrapped_object = test_scenario::take_from_sender<WrappedObject<TestObject>>(test);

            order::fulfill_order(&mut created_order, wrapped_object, &clock, ctx(test));
            test_scenario::return_shared<Order<TestObject, SUI>>(created_order);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}