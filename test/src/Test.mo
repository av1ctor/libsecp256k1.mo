import S "mo:matchers/Suite";
import T "mo:matchers/Testable";
import M "mo:matchers/Matchers";
import Field "../../src/core/field";
import Group "../../src/core/group";
import Error "../../src/core/error";
import Scalar "../../src/core/scalar";
import Subtle "../../src/subtle/lib";
import ECmult "../../src/core/ecmult";

let a = Group.Jacobian();
a.double_var(null);