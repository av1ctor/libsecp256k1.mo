import Array "mo:base/Array";
import E "mo:base/Error";
import Result "mo:base/Result";
import Error "core/error";
import Message "Message";
import Signature "Signature";
import RecoveryId "RecoveryId";
import PublicKey "PublicKey";
import ECMult "core/ecmult";
import Ecdsa "core/ecdsa";

module {
    public type Context = ECMult.ECMultContext;

    public func alloc_context(
    ): Context {
        return ECMult.ECMultContext();
    };
    
    /// Recover public key from a signed message, using the given context.
    public func recover_with_context(
        message: Message.Message,
        signature: Signature.Signature,
        recovery_id: RecoveryId.RecoveryId,
        context: Context,
    ): Result.Result<PublicKey.PublicKey, Error.Error> {
        switch(Ecdsa
            .recover_raw(context, signature.r, signature.s, recovery_id.value, message.value)) {
            case(#err(msg)) {
                return #err(msg);
            };
            case (#ok(af)) {
                return #ok(PublicKey.PublicKey(af));
            };
        };
    };
};