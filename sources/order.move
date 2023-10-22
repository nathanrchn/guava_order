module guava_order::order {
    use std::debug;

    use sui::transfer;
    use sui::math::{sqrt, pow};
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::object::{Self, UID, ID};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};

    const EStreamDoesNotExist: u64 = 1;
    const ESenderIsRecipient: u64 = 2;
    const EStartTimeIsAfterStopTime: u64 = 3;
    const ESegmentsEmpty: u64 = 4;
    const EBalanceIsZero: u64 = 5;
    const EStreamIsNotSenderOrRecipient: u64 = 6;
    const EInsufficientBalance: u64 = 7;
    const EStreamIsNotRecipient: u64 = 8;
    const EStreamIsNotSender: u64 = 9;

    struct WrappedObject<O: key + store> has key, store {
        id: UID,
        orderId: ID,
        object: O
    }

    struct Stream<phantom T> has key, store {
        id: UID,
        startTime: u64,
        length: u64,
        stopTime: u64,
        client: address,
        seller: address,
        withdrawn: u64,
        balance: Balance<T>
    }

    struct Order<phantom O: key + store, phantom T> has key {
        id: UID,
        client: address,
        seller: address,
        isFulfilled: bool,
        stream: Stream<T>
    }

    entry public fun get_client<O: key + store, T>(self: &Order<O, T>): address {
        self.client
    }

    entry public fun get_seller<O: key + store, T>(self: &Order<O, T>): address {
        self.seller
    }

    entry public fun is_order_fulfilled<O: key + store, T>(self: &Order<O, T>): bool {
        self.isFulfilled
    }

    // unused
    public fun get_stream<O: key + store, T>(self: &Order<O, T>): &Stream<T> {
        &self.stream
    }

    public fun balance_of_stream_<T>(stream: &Stream<T>, time: u64, sender: address): u64 {
        assert!(stream.startTime <= time, EStreamDoesNotExist);
        assert!(time <= stream.stopTime, EStreamDoesNotExist);
        assert!(stream.client == sender || stream.seller == sender, EStreamIsNotSenderOrRecipient);

        let balance = 0;
        let changeTime = stream.startTime + stream.length;

        if (time > changeTime) {
            let a = (time - changeTime) * 1_000_000;
            let b = (stream.stopTime - stream.length);
            balance = sqrt(1_000_000_000_000 - pow(a / b, 2)) * balance::value(&stream.balance) / 1_000_000;
        };

        if (stream.client == sender) {
            balance - stream.withdrawn
        } else {
            balance::value(&stream.balance) - balance
        }
    }

    entry public fun current_balance_of_stream<O: key + store, T>(self: &mut Order<O, T>, clock: &Clock, ctx: &mut TxContext): u64 {
        balance_of_stream_<T>(&self.stream, clock::timestamp_ms(clock), tx_context::sender(ctx))
    }

    entry public fun balance_of_stream_at<O: key + store, T>(self: &mut Order<O, T>, time: u64, ctx: &mut TxContext): u64 {
        balance_of_stream_<T>(&self.stream, time, tx_context::sender(ctx))
    }

    entry public fun create_order<O: key + store, T>(seller: address, coin: Coin<T>, length: u64, totalLength: u64, clock: &Clock, ctx: &mut TxContext) {
        assert!(length > 0, ESegmentsEmpty);
        assert!(length < totalLength, EStartTimeIsAfterStopTime);
        assert!(tx_context::sender(ctx) != seller, ESenderIsRecipient);
        assert!(coin::value(&coin) > 0, EBalanceIsZero);

        let startTime = clock::timestamp_ms(clock);
        let guava = Order<O, T> {
            id: object::new(ctx),
            client: tx_context::sender(ctx),
            seller,
            isFulfilled: false,
            stream: Stream<T> {
                id: object::new(ctx),
                startTime,
                length,
                stopTime: startTime + totalLength,
                client: tx_context::sender(ctx),
                seller,
                withdrawn: 0,
                balance: coin::into_balance(coin),
            }
        };

        transfer::share_object(guava);
    }

    entry public fun wrap_object<O: key + store, T>(self: &mut Order<O, T>, object: O, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == self.seller, EStreamIsNotRecipient);

        let wrapped_object = WrappedObject<O> {
            id: object::new(ctx),
            orderId: object::uid_to_inner(&self.stream.id),
            object
        };

        transfer::public_transfer(wrapped_object, self.seller)
    }

    entry public fun fulfill_order<O: key + store, T>(self: &mut Order<O, T>, wrapped_object: WrappedObject<O>, clock: &Clock, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == self.seller, EStreamIsNotSender);
        let WrappedObject { id, orderId, object } = wrapped_object;
        assert!(object::uid_to_inner(&self.stream.id) == orderId, EStreamDoesNotExist);
        assert!(clock::timestamp_ms(clock) >= self.stream.stopTime, EStreamDoesNotExist);

        transfer::public_transfer(object, self.client);

        // seller withdraw
        let balanceValue = balance_of_stream_<T>(&self.stream, clock::timestamp_ms(clock), self.seller);
        if (balanceValue > 0) {
            transfer::public_transfer(coin::take<T>(&mut self.stream.balance, balanceValue, ctx), tx_context::sender(ctx));
        };
        
        let balanceValue = balance::value(&self.stream.balance);
        if (balance::value(&self.stream.balance) > 0) {
            transfer::public_transfer(coin::take<T>(&mut self.stream.balance, balanceValue, ctx), self.client);
        };

        self.isFulfilled = true;
        object::delete(id);
    }

    entry public fun client_withdraw<O: key + store, T>(self: &mut Order<O, T>, amount: u64, clock: &Clock, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == self.client, EStreamIsNotRecipient);
        assert!(balance_of_stream_<T>(&self.stream, clock::timestamp_ms(clock), tx_context::sender(ctx)) >= amount, EInsufficientBalance);

        self.stream.withdrawn = self.stream.withdrawn + amount;
        transfer::public_transfer(coin::take<T>(&mut self.stream.balance, amount, ctx), tx_context::sender(ctx));
    }
}