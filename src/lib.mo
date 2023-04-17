import Utils "./core/utils";
import Result "mo:base/Result";
import Field "core/field";
import Error "core/error";
import E "mo:base/Error";
import Scalar "core/scalar";
import Group "core/group";

module {
    public class PublicKey(
        affine_: Group.Affine
    ) {
        public let affine = affine_;
    };

    public func parse(
        p: [Nat8]
    ): Result.Result<PublicKey, Error.Error> {
        if(not (p[0] == Utils.TAG_PUBKEY_FULL
            or p[0] == Utils.TAG_PUBKEY_HYBRID_EVEN
            or p[0] == Utils.TAG_PUBKEY_HYBRID_ODD)) {
            return #err(#InvalidPublicKey);
        };
        var x = Field.Field();
        var y = Field.Field();
        if(not x.set_b32(Utils.array_ref(p, 1, 32))) {
            return #err(#InvalidPublicKey);
        };
        if(not y.set_b32(Utils.array_ref(p, 33, 32))) {
            return #err(#InvalidPublicKey);
        };
        var elem = Group.Affine();
        elem.set_xy(x, y);
        if((p[0] == Utils.TAG_PUBKEY_HYBRID_EVEN or p[0] == Utils.TAG_PUBKEY_HYBRID_ODD)
            and (y.is_odd() != (p[0] == Utils.TAG_PUBKEY_HYBRID_ODD))) {
            return #err(#InvalidPublicKey);
        };
        if(elem.is_infinity()) {
            return #err(#InvalidPublicKey);
        };
        if(elem.is_valid_var()) {
            #ok(PublicKey(elem))
        } else {
            #err(#InvalidPublicKey)
        };
    };

    public func parse_compressed(
        p: [Nat8],
    ): Result.Result<PublicKey, Error.Error> {
        if(not (p[0] == Utils.TAG_PUBKEY_EVEN or p[0] == Utils.TAG_PUBKEY_ODD)) {
            return #err(#InvalidPublicKey);
        };
        var x = Field.Field();
        if(not x.set_b32(Utils.array_ref(p, 1, 32))) {
            return #err(#InvalidPublicKey);
        };
        var elem = Group.Affine();
        ignore elem.set_xo_var(x, p[0] == Utils.TAG_PUBKEY_ODD);
        if(elem.is_infinity()) {
            return #err(#InvalidPublicKey);
        };
        if(elem.is_valid_var()) {
            #ok(PublicKey(elem))
        } else {
            #err(#InvalidPublicKey)
        };
    };
};