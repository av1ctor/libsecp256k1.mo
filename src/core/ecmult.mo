import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Int32 "mo:base/Int32";
import Int "mo:base/Int";
import Buffer "mo:base/Buffer";
import Field "field";
import Group "group";
import Scalar "scalar";
import Utils "utils";
import Subtle "../subtle/lib";

module {
    type Field = Field.Field;
    type AffineStorage = Group.AffineStorage;
    type Affine = Group.Affine;
    type Jacobian = Group.Jacobian;
    type JacobianStatic = Group.JacobianStatic;
    type Scalar = Scalar.Scalar;
    type Choice = Subtle.Choice;

    public let WINDOW_A: Nat32 = 5;
    public let WINDOW_G: Nat32 = 16;
    public let ECMULT_TABLE_SIZE_A: Nat = 8; //  1 << (WINDOW_A - 2);
    public let ECMULT_TABLE_SIZE_G: Nat = 16384; // 1 << (WINDOW_G - 2);
    public let WNAF_BITS: Nat = 256;

    /// Context for accelerating the computation of a*P + b*G.
    public class ECMultContext() {
        public let pre_g = Array.init<AffineStorage>(ECMULT_TABLE_SIZE_G, Group.AffineStorage());
        let gj = Group.Jacobian();
        gj.set_ge(Group.affineStatic(Group.AFFINE_G));
        odd_multiples_table_storage_var(pre_g, gj);

        public func ecmult(
            r: Jacobian, 
            a: Jacobian, 
            na: Scalar.Scalar, 
            ng: Scalar.Scalar
        ): Jacobian {
            let pre_a = Array.init<Affine>(ECMULT_TABLE_SIZE_A, Group.Affine());
            var z = Field.Field();
            let wnaf_na = Array.init<Int32>(256, 0: Int32);
            let wnaf_ng = Array.init<Int32>(256, 0: Int32);
            let bits_na = ecmult_wnaf(wnaf_na, na, WINDOW_A);
            var bits = bits_na;
            odd_multiples_table_globalz_windowa(pre_a, z, a);

            let bits_ng = ecmult_wnaf(wnaf_ng, ng, WINDOW_G);
            if(bits_ng > bits) {
                bits := bits_ng;
            };

            var rr = Group.Jacobian();
            rr.assign_mut(r);
            rr.set_infinity();
            for(ii in Iter.revRange(Nat32.toNat(Int32.toNat32(bits))-1, 0)) {
                let i = Int.abs(ii);
                rr := rr.double_var(null);

                let n1 = wnaf_na[i];
                if(i < Int32.toInt(bits_na) and n1 != 0) {
                    let tmpa = table_get_ge(pre_a, n1, Int32.fromNat32(WINDOW_A));
                    rr := rr.add_ge_var(tmpa, null);
                };
                
                let n2 = wnaf_ng[i];
                if(i < Int32.toInt(bits_ng) and n2 != 0) {
                    let tmpa = table_get_ge_storage(pre_g, n2, Int32.fromNat32(WINDOW_G));
                    rr := rr.add_zinv_var(tmpa, z);
                };
            };

            if(not rr.is_infinity()) {
                rr.z.assign_mut(z);
            };

            return rr;
        };
    };

    public func ecmult_wnaf(
        wnaf: [var Int32], 
        a: Scalar.Scalar, 
        w: Nat32
    ): Int32 {
        let size = Nat32.fromNat(wnaf.size());
        var s = a;
        var last_set_bit = -1: Int32;
        var bit = 0: Nat32;
        var sign = 1: Int32;
        var carry = 0: Nat32;

        assert(wnaf.size() <= 256);
        assert(w >= 2 and w <= 31);

        for(i in Iter.range(0, wnaf.size()-1)) {
            wnaf[i] := 0;
        };

        if(s.bits_32(255, 1) > 0) {
            s.neg_mut();
            sign := -1;
        };

        label L while(bit < size) {
            var word = 0: Nat32;
            if(s.bits_32(bit, 1) == carry) {
                bit += 1;
                continue L;
            };

            var now = w;
            if(now > size - bit) {
                now := size - bit;
            };

            word := s.bits_var(bit, now) + carry;

            carry := (word >> (w - 1)) & 1;
            word -= carry << w;

            wnaf[Nat32.toNat(bit)] := sign * Int32.fromNat32(word);
            last_set_bit := Int32.fromNat32(bit);

            bit += now;
        };
        assert(carry == 0);
        assert(do {
            var t = true;
            while(bit < 256) {
                t := t and (s.bits_32(bit, 1) == 0);
                bit += 1;
            };
            t
        });
        
        return last_set_bit + 1;
    };

    /// Set a batch of group elements equal to the inputs given in jacobian
    /// coordinates. Not constant time.
    public func set_all_gej_var(
        a: [Jacobian]
    ): [var Affine] {
        let az_buf = Buffer.Buffer<Field>(a.size());
        for (point in Array.vals(a)) {
            if (not point.is_infinity()) {
                az_buf.add(point.z);
            };
        };
        let az: [var Field] = Buffer.toVarArray(az_buf);
        let azi: [var Field] = inv_all_var(az);

        let ret = Array.init<Affine>(a.size(), Group.Affine());

        var count = 0;
        for (i in Iter.range(0, a.size()-1)) {
            ret[i].infinity := a[i].infinity;
            if (not a[i].is_infinity()) {
                ret[i].set_gej_zinv(a[i], azi[count]);
                count += 1;
            };
        };
        ret
    };

    /// Calculate the (modular) inverses of a batch of field
    /// elements. Requires the inputs' magnitudes to be at most 8. The
    /// output magnitudes are 1 (but not guaranteed to be
    /// normalized).
    public func inv_all_var(
        fields: [var Field]
    ): [var Field] {
        if (fields.size() == 0) {
            return [var];
        };

        let ret_buf = Buffer.Buffer<Field>(fields.size());
        ret_buf.add(fields[0]);

        for (i in Iter.range(1, fields.size()-1)) {
            ret_buf.add(Field.Field());
            ret_buf.put(i, ret_buf.get(i-1).mul(fields[i]));
        };
        let ret = Buffer.toVarArray(ret_buf);

        var u = ret[fields.size() - 1].inv_var();

        for (i in Iter.range(fields.size()-1, 1)) {
            let j: Nat = i;
            let x: Nat = i - 1;
            ret[j] := ret[x].mul(u);
            u := u.mul(fields[j]);
        };

        ret[0] := u;
        ret
    };

    // Scalar.n = GEN_BLIND
    let GEN_BLIND: [Nat32] = [
        2217680822, 850875797, 1046150361, 1330484644, 4015777837, 2466086288, 2052467175, 2084507480,
    ];
    // Field::new_raw
    let GEN_INITIAL: JacobianStatic = {
        x = [
            586608, 43357028, 207667908, 262670128, 142222828, 38529388, 267186148, 45417712,
            115291924, 13447464,
        ];
        y = [
            12696548, 208302564, 112025180, 191752716, 143238548, 145482948, 228906000, 69755164,
            243572800, 210897016,
        ];
        z = [
            3685368, 75404844, 20246216, 5748944, 73206666, 107661790, 110806176, 73488774, 5707384,
            104448710,
        ];
        infinity = false;
    };

    /// Context for accelerating the computation of a*G.
    public class ECMultGenContext() {
        public var prec = Array.init<[var AffineStorage]>(
            64, Array.init<AffineStorage>(
                16, Group.AffineStorage()));
        public var blind = Scalar.Scalar();
        public var initial = Group.Jacobian();
    };

    func odd_multiples_table_globalz_windowa(
        pre: [var Group.Affine],
        globalz: Field.Field,
        a: Jacobian,
    ) {
        let prej = Array.init<Jacobian>(ECMULT_TABLE_SIZE_A, Group.Jacobian());
        let zr = Array.init<Field.Field>(ECMULT_TABLE_SIZE_A, Field.Field());

        odd_multiples_table(prej, zr, a);
        Group.globalz_set_table_gej(pre, globalz, prej, zr);
    };

    func table_get_ge(
        pre: [var Group.Affine], 
        n: Int32, 
        w: Int32
    ): Group.Affine {
        assert(n & 1 == 1);
        assert(n >= -((1 << (w - 1)) - 1));
        assert(n <= ((1 << (w - 1)) - 1));
        if(n > 0) {
            return pre[Int.abs(Int32.toInt((n - 1) / 2))];
        } else {
            return pre[Int.abs(Int32.toInt((-n - 1) / 2))].neg();
        };
    };

    func table_get_ge_storage(
        pre: [var Group.AffineStorage], 
        n: Int32, 
        w: Int32
    ): Group.Affine {
        assert(n & 1 == 1);
        assert(n >= -((1 << (w - 1)) - 1));
        assert(n <= ((1 << (w - 1)) - 1));
        if(n > 0) {
            return Group.from_as(pre[Int.abs(Int32.toInt((n - 1) / 2))]); // FIXME: calling .into() on Rust
        } else {
            let r = Group.from_as(pre[Int.abs(Int32.toInt((-n - 1) / 2))]); // FIXME: calling .into() on Rust
            return r.neg();
        };
    };

    public func odd_multiples_table(
        prej: [var Jacobian], 
        zr: [var Field], 
        a: Jacobian
    ) {
        let len = prej.size();
        assert(prej.size() == zr.size());
        assert(not (len == 0));
        assert(not a.is_infinity());

        let d = a.double_var(null);
        let d_ge = Group.new_af(d.x, d.y);

        let a_ge = Group.Affine();
        a_ge.set_gej_zinv(a, d.z);
        prej[0].x := a_ge.x;
        prej[0].y := a_ge.y;
        prej[0].z := a.z;
        prej[0].infinity := false;

        zr[0] := d.z;
        for (i in Iter.range(1, len-1)) {
            prej[i] := prej[i-1].add_ge_var(d_ge, ?zr[i]);
        };

        let l = prej[len-1].z.mul(d.z);
        prej[len-1].z := l;
    };

    func odd_multiples_table_storage_var(
        pre: [var AffineStorage], 
        a: Jacobian
    ) {
        let prej = Array.init<Jacobian>(pre.size(), Group.Jacobian());
        let prea = Array.init<Affine>(pre.size(), Group.Affine());
        let zr = Array.init<Field>(pre.size(), Field.Field());

        odd_multiples_table(prej, zr, a);
        Group.set_table_gej_var(prea, prej, zr);

        for (i in Iter.range(0, pre.size()-1)) {
            pre[i] := Group.into_as(prea[i]);
        };
    };
};