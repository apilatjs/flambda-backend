(* TEST
   flags = "-extension layouts_alpha"
*)

(* This file contains various tests for float#.  It's not an expect test to make
   sure it gets tested for native code. *)

(* CR layouts v2.5: When unboxed literals work, change this file to use them
   instead of [of_float] on boxed literals everywhere. *)

(*****************************************)
(* Prelude: Functions on unboxed floats. *)

module Float_u = struct
  include Stdlib__Float_u

  let ( + ) = add
  let ( - ) = sub
  let ( * ) = mul
  let ( / ) = div
  let ( ** ) = pow
  let ( > ) x y = (compare x y) > 0
end

(*********************************)
(* Test 1: some basic arithmetic *)

let print_floatu prefix x = Printf.printf "%s: %.2f\n" prefix (Float_u.to_float x)

(* Tests all the operators above *)
let test1 () =
  (* CR layouts: When float64 defs are allowed at the module level, get rid of
     [test1] and move these definitions there. *)
  let open Float_u in
  let pi = of_float 3.14 in
  print_floatu "Test 1, pi" pi;

  let twice_pi = pi + (of_float 3.14) in
  print_floatu "Test 1, twice_pi" twice_pi;

  let thrice_pi = (of_float 3.0) * pi in
  print_floatu "Test 1, thrice_pi" thrice_pi;

  let twice_pi_again = thrice_pi - pi in
  print_floatu "Test 1, twice_pi_again" twice_pi;

  let pi_again = twice_pi_again / (of_float 2.0) in
  print_floatu "Test 1, pi_again" pi_again;

  let twice_pi_to_the_pi = twice_pi ** pi in
  print_floatu "Test 1, twice_pi_to_the_pi" twice_pi_to_the_pi;

  let twice_pi_greater_than_pi = twice_pi > pi in
  Printf.printf "Test 1, twice_pi_greater_than_pi: %b\n"
    twice_pi_greater_than_pi;

  let pi_with_effort =
    ((of_float 3.14) + twice_pi) * (of_float 2.0) / (of_float 6.0) in
  print_floatu "Test 1, pi_with_effort" pi_with_effort

let _ = test1 ()

(**********************************)
(* Test 2: higher-order functions *)

(* CR layouts v1.5: This type definition can be eliminated once we have
   annotations. *)
type ('a : float64) t_float64 = 'a

let[@inline never] twice f (x : 'a t_float64) = f (f x)
let[@inline never] compose f g (x : 'a t_float64) = f (g x)

let[@inline never] twice_on_pi f =
  let pi = Float_u.of_float 3.14 in
  twice f pi

let times_four = twice Float_u.(fun x -> x * (of_float 2.0))

let _ =
  let open Float_u in
  print_floatu "Test 2, add pi twice"
    (twice (fun x -> x + (of_float 3.14)) (of_float 0.0));
  print_floatu "Test 2, add pi four times"
    (twice (twice (fun x -> x + (of_float 3.14))) (of_float 0.0));
  print_floatu "Test 2, increment pi twice"
    (twice_on_pi (fun x -> (of_float 1.0) + x));
  print_floatu "Test 2, increment pi four times"
    (twice_on_pi (twice (fun x -> (of_float 1.0) + x)));
  print_floatu "Test 2, e times four"
    (times_four (of_float 2.72));
  print_floatu "Test 2, pi times sixteen"
    (twice_on_pi times_four);
  print_floatu "Test 2, pi times sixteen again"
    (compose times_four times_four (of_float 3.14));
  print_floatu "Test 2, pi minus four"
    (let two = twice (fun x -> x + (of_float 1.0)) (of_float 0.0) in
     let add_two = Float_u.(+) two in
     let add_two_after = compose add_two in
     let minus_four = add_two_after (twice (fun x -> x - (of_float 3.0))) in
     minus_four (of_float 3.14))

(******************************)
(* Test 3: float# in closures *)

(* [go]'s closure should haave an [int] (immediate), a [float#] (float64) and a
   [float array] (value). *)
let[@inline never] f3 n m steps () =
  let[@inline never] rec go k =
    if k = n
    then Float_u.of_float 0.
    else begin
      let acc = go (k + 1) in
      steps.(k) <- Float_u.to_float acc;
      Float_u.(+) m acc
    end
  in
  go 0

(* many args - even args are tuples, odd args are unboxed floats *)
let[@inline_never] f3_manyargs x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 steps () =
  let (start_k, end_k) = x0 in
  let[@inline never] rec go k =
    if k = end_k
    then Float_u.of_float 0.
    else begin
      let (x2_1, x2_2) = x2 in
      let (x4_1, x4_2) = x4 in
      let (x6_1, x6_2) = x6 in
      let (x8_1, x8_2) = x8 in
      let sum = x2_1 + x2_2 + x4_1 + x4_2 + x6_1 + x6_2 + x8_1 + x8_2 in
      let acc = go (k + 1) in
      steps.(k) <- Float_u.to_float acc;
      Float_u.(acc + ((x1 + x3 + x5 + x7 + x9) * (of_float (Float.of_int sum))))
    end
  in
  go start_k

let test3 () =
  (* Test f3 *)
  let steps = Array.init 10 (fun _ -> 0.0) in
  let five_pi = f3 5 (Float_u.of_float 3.14) steps in
  print_floatu "Test 3, 5 * pi: " (five_pi ());
  Array.iteri (Printf.printf "  Test 3, step %d: %.2f\n") steps;

  (* Test f3_manyargs

          (3.14 + 2.72 + 1.62 + 1.41 + 42.0) = 50.86
      3 * (3.14 + 2.72 + 1.62 + 1.41 + 42.0) = 152.58
      6 * (3.14 + 2.72 + 1.62 + 1.41 + 42.0) = 306.16
      9 * (3.14 + 2.72 + 1.62 + 1.41 + 42.0) = 457.74

    ( but we expect some floating point error )
  *)
  let steps = Array.init 10 (fun _ -> 0.0) in
  let x1 = Float_u.of_float 3.14 in
  let x3 = Float_u.of_float 2.72 in
  let x5 = Float_u.of_float 1.62 in
  let x7 = Float_u.of_float 1.41 in
  let x9 = Float_u.of_float 42.0 in

  (* these sum to 3 *)
  let x2 = (7, 42) in
  let x4 = (-23, 109) in
  let x6 = (-242, 90) in
  let x8 = (-2, 22) in

  let f3_manyargs = f3_manyargs (4,8) x1 x2 x3 x4 x5 x6 x7 x8 x9 steps in
  print_floatu "Test 3, 610.68: " (f3_manyargs ());
  Array.iteri (Printf.printf "  Test 3, step %d: %.2f\n") steps

let _ = test3 ()

(*********************************************)
(* Test 4: Partial and indirect applications *)

let[@inline never] test4 () =
  (* Simple indirect call *)
  let[@inline never] go f =
    Float_u.to_float (f (Float_u.of_float 1.) (Float_u.of_float 2.))
  in
  let (x1, x2) = (go Float_u.(+), go Float_u.(-)) in
  print_floatu "Test 4, 1 + 2" (Float_u.of_float x1);
  print_floatu "Test 4, 1 - 2" (Float_u.of_float x2);

  (* partial application to float# *)
  let steps = Array.init 10 (fun _ -> 0.0) in
  let f = Sys.opaque_identity (f3 5 (Float_u.of_float 3.14)) in
  let five_pi = f steps in
  print_floatu "Test 4, 5 * pi: " (five_pi ());
  Array.iteri (Printf.printf "  Test 4, step %d: %.2f\n") steps;

  (* partial application with float# remaining *)
  let steps = Array.init 10 (fun _ -> 0.0) in
  let f = Sys.opaque_identity (f3 6) in
  let five_pi = f (Float_u.of_float 3.14) steps in
  print_floatu "Test 4, 6 * pi: " (five_pi ());
  Array.iteri (Printf.printf "  Test 4, step %d: %.2f\n") steps;

  (* Those two tests again, but making f3 also opaque to prevent expansion of
     the partial application. *)
  let f3 = Sys.opaque_identity f3 in

  let steps = Array.init 10 (fun _ -> 0.0) in
  let f = Sys.opaque_identity (f3 5 (Float_u.of_float 3.14)) in
  let five_pi = f steps in
  print_floatu "Test 4, 5 * pi: " (five_pi ());
  Array.iteri (Printf.printf "  Test 4, step %d: %.2f\n") steps;

  let steps = Array.init 10 (fun _ -> 0.0) in
  let f = Sys.opaque_identity (f3 6) in
  let five_pi = f (Float_u.of_float 3.14) steps in
  print_floatu "Test 4, 6 * pi: " (five_pi ());
  Array.iteri (Printf.printf "  Test 4, step %d: %.2f\n") steps

let _ = test4 ()

(****************************)
(* Test 5: Over application *)

let[@inline never] f5 n m =
  let open Float_u in
  (* Also testing a closure with only float# values *)
  let[@inline never] go f =
    f (n + m)
  in
  go

let test5 () =
  let open Float_u in
  let _ : unit =
    f5 (of_float 3.14) (of_float 2.72)
      (fun n s m -> print_floatu s (n + m)) "Test 5, pi+e+1"
      (of_float 1.0)
  in
  ()

let _ = test5 ()

(*****************************)
(* Test 6: methods on floats *)

(* CR layouts: add tests that capture floats in objects, once that is
   allowed. *)

(* float# args and returns *)
let f6_1 () = object
  method f6_m1 f1 f2 f3 =
    let open Float_u in
    (f1 - f2) / f3
end

(* capture a pair, recursion *)
let f6_2 n = object(self)
  method f6_m2 n3 m1 f =
    if n3 = ((Sys.opaque_identity fst) n) + ((Sys.opaque_identity snd) n) then
      m1
    else f (self#f6_m2 (n3+1) m1 f)
end

(* overapplication to float# and non-float# args *)
let f6_3 n k = object
  method f6_m3 n3 m1 f =
    let n = ((Sys.opaque_identity fst) n) + ((Sys.opaque_identity snd) n) in
    f (n + k + n3) m1
end

let test6 () =
  let add3 n (m, k) = n + m + k in
  let open Float_u in

  (* (3.14 - 2.72) / 2.5 = ~0.17 *)
  let o = (Sys.opaque_identity f6_1) () in
  print_floatu "Test 6, 0.17"
    (o#f6_m1 (of_float 3.14) (of_float 2.72) (of_float 2.5));

  (* 4.25 * 8 = 34 *)
  let o = (Sys.opaque_identity f6_2) (4,7) in
  let result = o#f6_m2 8 (of_float 4.25) (fun x -> x * of_float 2.) in
  print_floatu "Test 6, 34.00" result;

  (* (1 + 2 + 3 + (-2) + (-12) + 4) * (2.72 + (-1) + 10) = -46.88 *)
  let o = (Sys.opaque_identity f6_3) (1,2) 3 in
  let result =
    o#f6_m3 (-2) (of_float 2.72)
      (fun[@inline never] i m1 m2 n m3 ->
         (of_float (Float.of_int (add3 i n))) * (m1 + m2 + m3))
      (of_float (-1.)) (-12,4) (of_float 10.)
  in
  print_floatu "Test 6, -46.88" result

let _ = test6 ()
