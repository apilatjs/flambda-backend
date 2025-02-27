(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*                       Pierre Chambart, OCamlPro                        *)
(*           Mark Shinwell and Leo White, Jane Street Europe              *)
(*                                                                        *)
(*   Copyright 2013--2019 OCamlPro SAS                                    *)
(*   Copyright 2014--2019 Jane Street Group LLC                           *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

module H = Lambda_to_flambda_primitives_helpers
module K = Flambda_kind
module I = K.Standard_int
module I_or_f = K.Standard_int_or_float
module L = Lambda
module P = Flambda_primitive

let convert_integer_comparison_prim (comp : L.integer_comparison) :
    P.binary_primitive =
  match comp with
  | Ceq -> Phys_equal Eq
  | Cne -> Phys_equal Neq
  | Clt -> Int_comp (Tagged_immediate, Yielding_bool (Lt Signed))
  | Cgt -> Int_comp (Tagged_immediate, Yielding_bool (Gt Signed))
  | Cle -> Int_comp (Tagged_immediate, Yielding_bool (Le Signed))
  | Cge -> Int_comp (Tagged_immediate, Yielding_bool (Ge Signed))

let convert_boxed_integer_comparison_prim (kind : L.boxed_integer)
    (comp : L.integer_comparison) : P.binary_primitive =
  match kind, comp with
  | Pint32, Ceq -> Int_comp (Naked_int32, Yielding_bool Eq)
  | Pint32, Cne -> Int_comp (Naked_int32, Yielding_bool Neq)
  | Pint32, Clt -> Int_comp (Naked_int32, Yielding_bool (Lt Signed))
  | Pint32, Cgt -> Int_comp (Naked_int32, Yielding_bool (Gt Signed))
  | Pint32, Cle -> Int_comp (Naked_int32, Yielding_bool (Le Signed))
  | Pint32, Cge -> Int_comp (Naked_int32, Yielding_bool (Ge Signed))
  | Pint64, Ceq -> Int_comp (Naked_int64, Yielding_bool Eq)
  | Pint64, Cne -> Int_comp (Naked_int64, Yielding_bool Neq)
  | Pint64, Clt -> Int_comp (Naked_int64, Yielding_bool (Lt Signed))
  | Pint64, Cgt -> Int_comp (Naked_int64, Yielding_bool (Gt Signed))
  | Pint64, Cle -> Int_comp (Naked_int64, Yielding_bool (Le Signed))
  | Pint64, Cge -> Int_comp (Naked_int64, Yielding_bool (Ge Signed))
  | Pnativeint, Ceq -> Int_comp (Naked_nativeint, Yielding_bool Eq)
  | Pnativeint, Cne -> Int_comp (Naked_nativeint, Yielding_bool Neq)
  | Pnativeint, Clt -> Int_comp (Naked_nativeint, Yielding_bool (Lt Signed))
  | Pnativeint, Cgt -> Int_comp (Naked_nativeint, Yielding_bool (Gt Signed))
  | Pnativeint, Cle -> Int_comp (Naked_nativeint, Yielding_bool (Le Signed))
  | Pnativeint, Cge -> Int_comp (Naked_nativeint, Yielding_bool (Ge Signed))

let convert_float_comparison (comp : L.float_comparison) : unit P.comparison =
  match comp with
  | CFeq -> Eq
  | CFneq -> Neq
  | CFlt -> Lt ()
  | CFgt -> Gt ()
  | CFle -> Le ()
  | CFge -> Ge ()
  | CFnlt | CFngt | CFnle | CFnge ->
    Misc.fatal_error
      "Negated floating-point comparisons should have been removed by \
       [Lambda_to_flambda]"

let boxable_number_of_boxed_integer (bint : L.boxed_integer) :
    K.Boxable_number.t =
  match bint with
  | Pnativeint -> Naked_nativeint
  | Pint32 -> Naked_int32
  | Pint64 -> Naked_int64

let standard_int_of_boxed_integer (bint : L.boxed_integer) : K.Standard_int.t =
  match bint with
  | Pnativeint -> Naked_nativeint
  | Pint32 -> Naked_int32
  | Pint64 -> Naked_int64

let standard_int_or_float_of_boxed_integer (bint : L.boxed_integer) :
    K.Standard_int_or_float.t =
  match bint with
  | Pnativeint -> Naked_nativeint
  | Pint32 -> Naked_int32
  | Pint64 -> Naked_int64

let convert_block_access_field_kind i_or_p : P.Block_access_field_kind.t =
  match i_or_p with L.Immediate -> Immediate | L.Pointer -> Any_value

let convert_init_or_assign (i_or_a : L.initialization_or_assignment) :
    P.Init_or_assign.t =
  match i_or_a with
  | Assignment mode -> Assignment (Alloc_mode.For_assignments.from_lambda mode)
  | Heap_initialization -> Initialization
  | Root_initialization ->
    Misc.fatal_error "[Root_initialization] should not appear in Flambda input"

let convert_block_shape (shape : L.block_shape) ~num_fields =
  match shape with
  | None -> List.init num_fields (fun _field -> K.With_subkind.any_value)
  | Some shape ->
    let shape_length = List.length shape in
    if num_fields <> shape_length
    then
      Misc.fatal_errorf
        "Flambda_arity.of_block_shape: num_fields is %d yet the shape has %d \
         fields"
        num_fields shape_length;
    List.map K.With_subkind.from_lambda_value_kind shape

let check_float_array_optimisation_enabled () =
  if not (Flambda_features.flat_float_array ())
  then
    Misc.fatal_error
      "[Pgenarray] is not expected when the float array optimisation is \
       disabled"

type converted_array_kind =
  | Array_kind of P.Array_kind.t
  | Float_array_opt_dynamic

let convert_array_kind (kind : L.array_kind) : converted_array_kind =
  match kind with
  | Pgenarray ->
    check_float_array_optimisation_enabled ();
    Float_array_opt_dynamic
  | Paddrarray -> Array_kind Values
  | Pintarray -> Array_kind Immediates
  | Pfloatarray -> Array_kind Naked_floats

module Array_ref_kind = struct
  type t =
    | Immediates
    | Values
    | Naked_floats of L.alloc_mode
end

type converted_array_ref_kind =
  | Array_ref_kind of Array_ref_kind.t
  | Float_array_opt_dynamic_ref of L.alloc_mode

let convert_array_ref_kind (kind : L.array_ref_kind) : converted_array_ref_kind
    =
  match kind with
  | Pgenarray_ref mode ->
    check_float_array_optimisation_enabled ();
    Float_array_opt_dynamic_ref mode
  | Paddrarray_ref -> Array_ref_kind Values
  | Pintarray_ref -> Array_ref_kind Immediates
  | Pfloatarray_ref mode -> Array_ref_kind (Naked_floats mode)

type converted_array_set_kind =
  | Array_set_kind of P.Array_set_kind.t
  | Float_array_opt_dynamic_set of Alloc_mode.For_assignments.t

let convert_array_set_kind (kind : L.array_set_kind) : converted_array_set_kind
    =
  match kind with
  | Pgenarray_set mode ->
    check_float_array_optimisation_enabled ();
    Float_array_opt_dynamic_set (Alloc_mode.For_assignments.from_lambda mode)
  | Paddrarray_set mode ->
    Array_set_kind
      (Values (Assignment (Alloc_mode.For_assignments.from_lambda mode)))
  | Pintarray_set -> Array_set_kind Immediates
  | Pfloatarray_set -> Array_set_kind Naked_floats

type converted_duplicate_array_kind =
  | Duplicate_array_kind of P.Duplicate_array_kind.t
  | Float_array_opt_dynamic

let convert_array_kind_to_duplicate_array_kind (kind : L.array_kind) :
    converted_duplicate_array_kind =
  match kind with
  | Pgenarray ->
    check_float_array_optimisation_enabled ();
    Float_array_opt_dynamic
  | Paddrarray -> Duplicate_array_kind Values
  | Pintarray -> Duplicate_array_kind Immediates
  | Pfloatarray -> Duplicate_array_kind (Naked_floats { length = None })

let convert_field_read_semantics (sem : L.field_read_semantics) : Mutability.t =
  match sem with Reads_agree -> Immutable | Reads_vary -> Mutable

let bigarray_dim_bound b dimension =
  H.Prim (Unary (Bigarray_length { dimension }, b))

let tag_int (arg : H.expr_primitive) : H.expr_primitive =
  Unary (Tag_immediate, Prim arg)

let untag_int (arg : H.simple_or_prim) : H.simple_or_prim =
  Prim (Unary (Untag_immediate, arg))

let box_float (mode : L.alloc_mode) (arg : H.expr_primitive) ~current_region :
    H.expr_primitive =
  Unary
    ( Box_number
        ( K.Boxable_number.Naked_float,
          Alloc_mode.For_allocations.from_lambda mode ~current_region ),
      Prim arg )

let unbox_float (arg : H.simple_or_prim) : H.simple_or_prim =
  Prim (Unary (Unbox_number K.Boxable_number.Naked_float, arg))

let box_bint bi mode (arg : H.expr_primitive) ~current_region : H.expr_primitive
    =
  Unary
    ( Box_number
        ( boxable_number_of_boxed_integer bi,
          Alloc_mode.For_allocations.from_lambda mode ~current_region ),
      Prim arg )

let unbox_bint bi (arg : H.simple_or_prim) : H.simple_or_prim =
  Prim (Unary (Unbox_number (boxable_number_of_boxed_integer bi), arg))

let bint_unary_prim bi mode prim arg1 =
  box_bint bi mode
    (Unary
       (Int_arith (standard_int_of_boxed_integer bi, prim), unbox_bint bi arg1))

let bint_binary_prim bi mode prim arg1 arg2 =
  box_bint bi mode
    (Binary
       ( Int_arith (standard_int_of_boxed_integer bi, prim),
         unbox_bint bi arg1,
         unbox_bint bi arg2 ))

let bint_shift bi mode prim arg1 arg2 =
  box_bint bi mode
    (Binary
       ( Int_shift (standard_int_of_boxed_integer bi, prim),
         unbox_bint bi arg1,
         untag_int arg2 ))

let check_non_negative_imm imm prim_name =
  if not (Targetint_31_63.is_non_negative imm)
  then
    Misc.fatal_errorf "%s with negative index %a" prim_name
      Targetint_31_63.print imm

(* Smart constructor for checked accesses *)
let checked_access ~dbg ~primitive ~conditions : H.expr_primitive =
  Checked
    { primitive;
      validity_conditions = conditions;
      failure = Index_out_of_bounds;
      dbg
    }

let checked_alignment ~dbg ~primitive ~conditions : H.expr_primitive =
  Checked
    { primitive;
      validity_conditions = conditions;
      failure = Address_was_misaligned;
      dbg
    }

let check_bound_tagged tagged_index bound : H.expr_primitive =
  Binary
    ( Int_comp (I.Naked_immediate, Yielding_bool (Lt Unsigned)),
      untag_int tagged_index,
      bound )

(* This computes the maximum of a given value [x] with zero, in an optimized
   way. It takes as named argument the size (in bytes) of an integer register on
   the target architecture.

   It is equivalent to the `max_or_zero` function in `cmm_helpers.ml` *)
let max_with_zero ~size_int x =
  let register_bitsize_minus_one =
    H.Simple
      (Simple.const
         (Reg_width_const.naked_immediate
            (Targetint_31_63.of_int ((size_int * 8) - 1))))
  in
  let sign =
    H.Prim
      (Binary (Int_shift (Naked_nativeint, Asr), x, register_bitsize_minus_one))
  in
  let minus_one =
    H.Simple
      (Simple.const
         (Reg_width_const.naked_nativeint (Targetint_32_64.of_int (-1))))
  in
  let sign_negation =
    H.Prim (Binary (Int_arith (Naked_nativeint, Xor), sign, minus_one))
  in
  let ret =
    H.Prim (Binary (Int_arith (Naked_nativeint, And), sign_negation, x))
  in
  ret

(* actual (strict) upper bound for an index in a string-like read/write *)
let actual_max_length_for_string_like_access ~size_int ~access_size length =
  (* offset to subtract from the length depending on the size of the
     read/write *)
  let length_offset_of_size size =
    let offset =
      match (size : Flambda_primitive.string_accessor_width) with
      | Eight -> 0
      | Sixteen -> 1
      | Thirty_two -> 3
      | Sixty_four -> 7
    in
    Targetint_31_63.of_int offset
  in
  match (access_size : Flambda_primitive.string_accessor_width) with
  | Eight -> length (* micro-optimization *)
  | Sixteen | Thirty_two | Sixty_four ->
    let offset = length_offset_of_size access_size in
    let reduced_length =
      H.Prim
        (Binary
           ( Int_arith (Naked_immediate, Sub),
             length,
             Simple (Simple.const (Reg_width_const.naked_immediate offset)) ))
    in
    (* We need to convert the length into a naked_nativeint because the
       optimised version of the max_with_zero function needs to be on
       machine-width integers to work (or at least on an integer number of bytes
       to work). *)
    let reduced_length_nativeint =
      H.Prim
        (Unary
           ( Num_conv { src = Naked_immediate; dst = Naked_nativeint },
             reduced_length ))
    in
    let nativeint_res = max_with_zero ~size_int reduced_length_nativeint in
    H.Prim
      (Unary
         ( Num_conv { src = Naked_nativeint; dst = Naked_immediate },
           nativeint_res ))

(* String-like validity conditions *)
let string_like_access_validity_condition ~size_int ~access_size ~length index :
    H.expr_primitive =
  check_bound_tagged index
    (actual_max_length_for_string_like_access ~size_int ~access_size length)

let string_or_bytes_access_validity_condition ~size_int str kind access_size
    index : H.expr_primitive =
  string_like_access_validity_condition index ~size_int ~access_size
    ~length:(Prim (Unary (String_length kind, str)))

let bigstring_access_validity_condition ~size_int big_str access_size index :
    H.expr_primitive =
  string_like_access_validity_condition index ~size_int ~access_size
    ~length:(bigarray_dim_bound big_str 1)

let bigstring_alignment_validity_condition bstr alignment tagged_index :
    H.expr_primitive =
  Binary
    ( Int_comp (I.Naked_immediate, Yielding_bool Eq),
      Prim
        (Binary (Bigarray_get_alignment alignment, bstr, untag_int tagged_index)),
      Simple Simple.untagged_const_zero )

let checked_string_or_bytes_access ~dbg ~size_int ~access_size ~primitive kind
    string index =
  checked_access ~dbg ~primitive
    ~conditions:
      [ string_or_bytes_access_validity_condition ~size_int string kind
          access_size index ]

let checked_bigstring_access ~dbg ~size_int ~access_size ~primitive arg1 arg2 =
  (* TODO(mslater): check alignment based on access size *)
  ignore checked_alignment;
  ignore bigstring_alignment_validity_condition;
  checked_access ~dbg ~primitive
    ~conditions:
      [bigstring_access_validity_condition ~size_int arg1 access_size arg2]

(* String-like loads *)
let string_like_load_unsafe ~access_size kind mode string index ~current_region
    =
  let wrap =
    match (access_size : Flambda_primitive.string_accessor_width), mode with
    | (Eight | Sixteen), None -> tag_int
    | Thirty_two, Some mode -> box_bint Pint32 mode ~current_region
    | Sixty_four, Some mode -> box_bint Pint64 mode ~current_region
    | (Eight | Sixteen), Some _ | (Thirty_two | Sixty_four), None ->
      Misc.fatal_error "Inconsistent alloc_mode for string or bytes load"
  in
  wrap (Binary (String_or_bigstring_load (kind, access_size), string, index))

let get_header obj mode ~current_region =
  let wrap hd = box_bint Pnativeint mode hd ~current_region in
  wrap (Unary (Get_header, obj))

let string_like_load_safe ~dbg ~size_int ~access_size kind mode str index
    ~current_region =
  match (kind : P.string_like_value) with
  | String ->
    checked_string_or_bytes_access ~dbg ~size_int ~access_size String
      ~primitive:
        (string_like_load_unsafe ~access_size String mode str index
           ~current_region)
      str index
  | Bytes ->
    checked_string_or_bytes_access ~dbg ~size_int ~access_size Bytes
      ~primitive:
        (string_like_load_unsafe ~access_size Bytes mode str index
           ~current_region)
      str index
  | Bigstring ->
    checked_bigstring_access ~dbg ~size_int ~access_size
      ~primitive:
        (string_like_load_unsafe ~access_size Bigstring mode str index
           ~current_region)
      str index

(* Bytes-like set *)
let bytes_like_set_unsafe ~access_size kind bytes index new_value =
  let wrap =
    match (access_size : Flambda_primitive.string_accessor_width) with
    | Eight | Sixteen -> untag_int
    | Thirty_two -> unbox_bint Pint32
    | Sixty_four -> unbox_bint Pint64
  in
  H.Ternary
    (Bytes_or_bigstring_set (kind, access_size), bytes, index, wrap new_value)

let bytes_like_set_safe ~dbg ~size_int ~access_size kind bytes index new_value =
  match (kind : P.bytes_like_value) with
  | Bytes ->
    checked_string_or_bytes_access ~dbg ~size_int ~access_size Bytes
      ~primitive:
        (bytes_like_set_unsafe ~access_size Bytes bytes index new_value)
      bytes index
  | Bigstring ->
    checked_bigstring_access ~dbg ~size_int ~access_size
      ~primitive:
        (bytes_like_set_unsafe ~access_size Bigstring bytes index new_value)
      bytes index

(* Bigarray accesses *)
let bigarray_box_or_tag_raw_value_to_read kind alloc_mode =
  let error what =
    Misc.fatal_errorf "Don't know how to box %s after reading it in a bigarray"
      what
  in
  match P.Bigarray_kind.element_kind kind with
  | Value -> Fun.id
  | Naked_number Naked_immediate -> fun arg -> H.Unary (Tag_immediate, Prim arg)
  | Naked_number Naked_float ->
    fun arg -> H.Unary (Box_number (Naked_float, alloc_mode), Prim arg)
  | Naked_number Naked_int32 ->
    fun arg -> H.Unary (Box_number (Naked_int32, alloc_mode), Prim arg)
  | Naked_number Naked_int64 ->
    fun arg -> H.Unary (Box_number (Naked_int64, alloc_mode), Prim arg)
  | Naked_number Naked_nativeint ->
    fun arg -> H.Unary (Box_number (Naked_nativeint, alloc_mode), Prim arg)
  | Naked_number Naked_vec128 ->
    fun arg -> H.Unary (Box_number (Naked_vec128, alloc_mode), Prim arg)
  | Region -> error "a region expression"
  | Rec_info -> error "recursion info"

let bigarray_unbox_or_untag_value_to_store kind =
  let error what =
    Misc.fatal_errorf "Don't know how to unbox %s to store it in a bigarray"
      what
  in
  match P.Bigarray_kind.element_kind kind with
  | Value -> Fun.id
  | Naked_number Naked_immediate ->
    fun arg -> H.Prim (Unary (Untag_immediate, arg))
  | Naked_number Naked_float ->
    fun arg -> H.Prim (Unary (Unbox_number Naked_float, arg))
  | Naked_number Naked_int32 ->
    fun arg -> H.Prim (Unary (Unbox_number Naked_int32, arg))
  | Naked_number Naked_int64 ->
    fun arg -> H.Prim (Unary (Unbox_number Naked_int64, arg))
  | Naked_number Naked_nativeint ->
    fun arg -> H.Prim (Unary (Unbox_number Naked_nativeint, arg))
  | Naked_number Naked_vec128 ->
    fun arg -> H.Prim (Unary (Unbox_number Naked_vec128, arg))
  | Region -> error "a region expression"
  | Rec_info -> error "recursion info"

(* CR Gbury: this function in effect duplicates the bigarray_length access: one
   is done in the validity check, and one in the final offset computation,
   whereas cmmgen let-binds this access. It might matter for the performance,
   although the processor cache might make it not matter at all. *)
let bigarray_indexing layout b args =
  let num_dim = List.length args in
  let rec aux dim delta_dim = function
    | [] -> assert false
    | [idx] ->
      let bound = bigarray_dim_bound b dim in
      let check = check_bound_tagged idx bound in
      [check], idx
    | idx :: r ->
      let checks, rem = aux (dim + delta_dim) delta_dim r in
      let bound = bigarray_dim_bound b dim in
      let check = check_bound_tagged idx bound in
      (* CR gbury: because we tag bound, and the tagged multiplication untags
         it, we might be left with a needless zero-extend here. *)
      let tmp =
        H.Prim
          (Binary
             ( Int_arith (I.Tagged_immediate, Mul),
               rem,
               Prim (Unary (Tag_immediate, bound)) ))
      in
      let offset =
        H.Prim (Binary (Int_arith (I.Tagged_immediate, Add), tmp, idx))
      in
      check :: checks, offset
  in
  match (layout : P.Bigarray_layout.t) with
  | C -> aux num_dim (-1) (List.rev args)
  | Fortran ->
    aux 1 1
      (List.map
         (fun idx ->
           H.Prim
             (Binary
                ( Int_arith (I.Tagged_immediate, Sub),
                  idx,
                  H.Simple (Simple.const_int Targetint_31_63.one) )))
         args)

let bigarray_access ~dbg ~unsafe ~access layout b indexes =
  let num_dim = List.length indexes in
  let checks, offset = bigarray_indexing layout b indexes in
  let primitive = access num_dim offset in
  if unsafe
  then primitive
  else checked_access ~dbg ~conditions:checks ~primitive

let bigarray_load ~dbg ~unsafe kind layout b indexes =
  let access num_dim offset =
    H.Binary (Bigarray_load (num_dim, kind, layout), b, offset)
  in
  bigarray_access ~dbg ~unsafe ~access layout b indexes

let bigarray_set ~dbg ~unsafe kind layout b indexes value =
  let access num_dim offset =
    H.Ternary (Bigarray_set (num_dim, kind, layout), b, offset, value)
  in
  bigarray_access ~dbg ~unsafe ~access layout b indexes

(* Array accesses *)
let array_access_validity_condition array index =
  [ H.Binary
      ( Int_comp (Tagged_immediate, Yielding_bool (Lt Unsigned)),
        index,
        Prim (Unary (Array_length, array)) ) ]

let check_array_access ~dbg ~array ~index primitive : H.expr_primitive =
  checked_access ~primitive
    ~conditions:(array_access_validity_condition array index)
    ~dbg

let array_load_unsafe ~array ~index (array_ref_kind : Array_ref_kind.t)
    ~current_region : H.expr_primitive =
  match array_ref_kind with
  | Immediates -> Binary (Array_load (Immediates, Mutable), array, index)
  | Values -> Binary (Array_load (Values, Mutable), array, index)
  | Naked_floats mode ->
    box_float mode
      (Binary (Array_load (Naked_floats, Mutable), array, index))
      ~current_region

let array_set_unsafe ~array ~index ~new_value
    (array_set_kind : P.Array_set_kind.t) : H.expr_primitive =
  let new_value =
    match array_set_kind with
    | Immediates | Values _ -> new_value
    | Naked_floats -> unbox_float new_value
  in
  Ternary (Array_set array_set_kind, array, index, new_value)

let[@inline always] match_on_array_ref_kind ~array array_ref_kind f :
    H.expr_primitive =
  match convert_array_ref_kind array_ref_kind with
  | Array_ref_kind array_ref_kind -> f array_ref_kind
  | Float_array_opt_dynamic_ref mode ->
    (* CR keryan: we should push the ITE as low as possible to avoid duplicating
       too much *)
    If_then_else
      ( Unary (Is_flat_float_array, array),
        f (Array_ref_kind.Naked_floats mode),
        f Array_ref_kind.Values )

let[@inline always] match_on_array_set_kind ~array array_ref_kind f :
    H.expr_primitive =
  match convert_array_set_kind array_ref_kind with
  | Array_set_kind array_set_kind -> f array_set_kind
  | Float_array_opt_dynamic_set mode ->
    (* CR keryan: we should push the ITE as low as possible to avoid duplicating
       too much *)
    If_then_else
      ( Unary (Is_flat_float_array, array),
        f P.Array_set_kind.Naked_floats,
        f (P.Array_set_kind.Values (Assignment mode)) )

(* Safe arith (div/mod by zero) *)
let checked_arith_op ~dbg (bi : Lambda.boxed_integer option) op mode arg1 arg2
    ~current_region : H.expr_primitive =
  let primitive, kind, zero, arg_wrap =
    match bi, mode with
    | None, None ->
      ( H.Binary (Int_arith (I.Tagged_immediate, op), arg1, arg2),
        I.Tagged_immediate,
        Reg_width_const.tagged_immediate Targetint_31_63.zero,
        Fun.id )
    | Some bi, Some mode ->
      let kind, zero =
        match bi with
        | Pint32 -> I.Naked_int32, Reg_width_const.naked_int32 0l
        | Pint64 -> I.Naked_int64, Reg_width_const.naked_int64 0L
        | Pnativeint ->
          ( I.Naked_nativeint,
            Reg_width_const.naked_nativeint Targetint_32_64.zero )
      in
      ( bint_binary_prim bi mode op arg1 arg2 ~current_region,
        kind,
        zero,
        unbox_bint bi )
    | _, _ -> Misc.fatal_error "Inconsistent allocation mode"
  in
  (* CR gbury: try and avoid the unboxing duplication of arg2. (the simplifier
     might cse the duplication away, but it won't be the case for classic
     mode). *)
  Checked
    { primitive;
      validity_conditions =
        [ Binary
            ( Int_comp (kind, Yielding_bool Neq),
              arg_wrap arg2,
              Simple (Simple.const zero) ) ];
      failure = Division_by_zero;
      dbg
    }

let bbswap bi si mode arg ~current_region : H.expr_primitive =
  let mode = Alloc_mode.For_allocations.from_lambda mode ~current_region in
  Unary
    ( Box_number (bi, mode),
      Prim
        (Unary
           ( Int_arith (si, Swap_byte_endianness),
             Prim (Unary (Unbox_number bi, arg)) )) )

(* Primitive conversion *)
let convert_lprim ~big_endian (prim : L.primitive) (args : Simple.t list list)
    (dbg : Debuginfo.t) ~current_region : H.expr_primitive list =
  let args =
    List.map (List.map (fun arg : H.simple_or_prim -> Simple arg)) args
  in
  let size_int =
    assert (Targetint.size mod 8 = 0);
    Targetint.size / 8
  in
  match prim, args with
  | Pmakeblock (tag, mutability, shape, mode), _ ->
    let args = List.flatten args in
    let mode = Alloc_mode.For_allocations.from_lambda mode ~current_region in
    let tag = Tag.Scannable.create_exn tag in
    let shape = convert_block_shape shape ~num_fields:(List.length args) in
    let mutability = Mutability.from_lambda mutability in
    [Variadic (Make_block (Values (tag, shape), mutability, mode), args)]
  | Pmakefloatblock (mutability, mode), _ ->
    let args = List.flatten args in
    let mode = Alloc_mode.For_allocations.from_lambda mode ~current_region in
    let mutability = Mutability.from_lambda mutability in
    [ Variadic
        (Make_block (Naked_floats, mutability, mode), List.map unbox_float args)
    ]
  | Pmakearray (array_kind, mutability, mode), _ -> (
    let args = List.flatten args in
    let mode = Alloc_mode.For_allocations.from_lambda mode ~current_region in
    let array_kind = convert_array_kind array_kind in
    let mutability = Mutability.from_lambda mutability in
    match array_kind with
    | Array_kind array_kind ->
      let args =
        match array_kind with
        | Immediates | Values -> args
        | Naked_floats -> List.map unbox_float args
      in
      [Variadic (Make_array (array_kind, mutability, mode), args)]
    | Float_array_opt_dynamic -> (
      (* If this is an empty array we can just give it array kind [Values].
         (Even empty flat float arrays have tag zero.) *)
      match args with
      | [] ->
        [ Variadic
            (Make_array (Values, Immutable, Alloc_mode.For_allocations.heap), [])
        ]
      | elt :: _ ->
        (* Test the first element to see if it's a boxed float: if it is, this
           array must be created as a flat float array. *)
        [ If_then_else
            ( Unary (Is_boxed_float, elt),
              Variadic
                ( Make_array (Naked_floats, mutability, mode),
                  List.map unbox_float args ),
              Variadic (Make_array (Values, mutability, mode), args) ) ]))
  | Popaque layout, [[arg]] ->
    let kind = K.With_subkind.kind (K.With_subkind.from_lambda layout) in
    [Unary (Opaque_identity { middle_end_only = false; kind }, arg)]
  | Pobj_magic layout, [[arg]] ->
    let kind = K.With_subkind.kind (K.With_subkind.from_lambda layout) in
    [Unary (Opaque_identity { middle_end_only = true; kind }, arg)]
  | Pduprecord (repr, num_fields), [[arg]] ->
    let kind : P.Duplicate_block_kind.t =
      match repr with
      | Record_boxed _ ->
        Values
          { tag = Tag.Scannable.zero;
            length = Targetint_31_63.of_int num_fields
          }
      | Record_float ->
        Naked_floats { length = Targetint_31_63.of_int num_fields }
      | Record_inlined (Ordinary { runtime_tag; _ }, Variant_boxed _) ->
        Values
          { tag = Tag.Scannable.create_exn runtime_tag;
            length = Targetint_31_63.of_int num_fields
          }
      | Record_inlined (Extension _, Variant_extensible) ->
        Values
          { tag = Tag.Scannable.zero;
            (* The "+1" is because there is an extra field containing the hashed
               constructor. *)
            length = Targetint_31_63.of_int (num_fields + 1)
          }
      | Record_inlined (Extension _, _)
      | Record_inlined (Ordinary _, (Variant_unboxed | Variant_extensible))
      | Record_unboxed ->
        Misc.fatal_errorf "Cannot handle record kind for Pduprecord: %a"
          Printlambda.primitive prim
    in
    [Unary (Duplicate_block { kind }, arg)]
  | Pnegint, [[arg]] -> [Unary (Int_arith (I.Tagged_immediate, Neg), arg)]
  | Paddint, [[arg1]; [arg2]] ->
    [Binary (Int_arith (I.Tagged_immediate, Add), arg1, arg2)]
  | Psubint, [[arg1]; [arg2]] ->
    [Binary (Int_arith (I.Tagged_immediate, Sub), arg1, arg2)]
  | Pmulint, [[arg1]; [arg2]] ->
    [Binary (Int_arith (I.Tagged_immediate, Mul), arg1, arg2)]
  | Pandint, [[arg1]; [arg2]] ->
    [Binary (Int_arith (I.Tagged_immediate, And), arg1, arg2)]
  | Porint, [[arg1]; [arg2]] ->
    [Binary (Int_arith (I.Tagged_immediate, Or), arg1, arg2)]
  | Pxorint, [[arg1]; [arg2]] ->
    [Binary (Int_arith (I.Tagged_immediate, Xor), arg1, arg2)]
  | Plslint, [[arg1]; [arg2]] ->
    [Binary (Int_shift (I.Tagged_immediate, Lsl), arg1, untag_int arg2)]
  | Plsrint, [[arg1]; [arg2]] ->
    [Binary (Int_shift (I.Tagged_immediate, Lsr), arg1, untag_int arg2)]
  | Pasrint, [[arg1]; [arg2]] ->
    [Binary (Int_shift (I.Tagged_immediate, Asr), arg1, untag_int arg2)]
  | Pnot, [[arg]] -> [Unary (Boolean_not, arg)]
  | Pintcomp comp, [[arg1]; [arg2]] ->
    [tag_int (Binary (convert_integer_comparison_prim comp, arg1, arg2))]
  | Pbintcomp (kind, comp), [[arg1]; [arg2]] ->
    let arg1 = unbox_bint kind arg1 in
    let arg2 = unbox_bint kind arg2 in
    [ tag_int
        (Binary (convert_boxed_integer_comparison_prim kind comp, arg1, arg2))
    ]
  | Pintoffloat, [[arg]] ->
    let src = K.Standard_int_or_float.Naked_float in
    let dst = K.Standard_int_or_float.Tagged_immediate in
    [Unary (Num_conv { src; dst }, unbox_float arg)]
  | Pfloatofint mode, [[arg]] ->
    let src = K.Standard_int_or_float.Tagged_immediate in
    let dst = K.Standard_int_or_float.Naked_float in
    [box_float mode (Unary (Num_conv { src; dst }, arg)) ~current_region]
  | Pnegfloat mode, [[arg]] ->
    [box_float mode (Unary (Float_arith Neg, unbox_float arg)) ~current_region]
  | Pabsfloat mode, [[arg]] ->
    [box_float mode (Unary (Float_arith Abs, unbox_float arg)) ~current_region]
  | Paddfloat mode, [[arg1]; [arg2]] ->
    [ box_float mode
        (Binary (Float_arith Add, unbox_float arg1, unbox_float arg2))
        ~current_region ]
  | Psubfloat mode, [[arg1]; [arg2]] ->
    [ box_float mode
        (Binary (Float_arith Sub, unbox_float arg1, unbox_float arg2))
        ~current_region ]
  | Pmulfloat mode, [[arg1]; [arg2]] ->
    [ box_float mode
        (Binary (Float_arith Mul, unbox_float arg1, unbox_float arg2))
        ~current_region ]
  | Pdivfloat mode, [[arg1]; [arg2]] ->
    [ box_float mode
        (Binary (Float_arith Div, unbox_float arg1, unbox_float arg2))
        ~current_region ]
  | Pfloatcomp comp, [[arg1]; [arg2]] ->
    [ tag_int
        (Binary
           ( Float_comp (Yielding_bool (convert_float_comparison comp)),
             unbox_float arg1,
             unbox_float arg2 )) ]
  | Punbox_float, [[arg]] -> [Unary (Unbox_number Naked_float, arg)]
  | Pbox_float mode, [[arg]] ->
    [ Unary
        ( Box_number
            ( Naked_float,
              Alloc_mode.For_allocations.from_lambda mode ~current_region ),
          arg ) ]
  | Punbox_int bi, [[arg]] ->
    let kind = boxable_number_of_boxed_integer bi in
    [Unary (Unbox_number kind, arg)]
  | Pbox_int (bi, mode), [[arg]] ->
    let kind = boxable_number_of_boxed_integer bi in
    [ Unary
        ( Box_number
            (kind, Alloc_mode.For_allocations.from_lambda mode ~current_region),
          arg ) ]
  | Pfield_computed sem, [[obj]; [field]] ->
    let block_access : P.Block_access_kind.t =
      Values { tag = Unknown; size = Unknown; field_kind = Any_value }
    in
    [ Binary
        (Block_load (block_access, convert_field_read_semantics sem), obj, field)
    ]
  | ( Psetfield_computed (imm_or_pointer, init_or_assign),
      [[obj]; [field]; [value]] ) ->
    let field_kind = convert_block_access_field_kind imm_or_pointer in
    let block_access : P.Block_access_kind.t =
      Values { tag = Unknown; size = Unknown; field_kind }
    in
    [ Ternary
        ( Block_set (block_access, convert_init_or_assign init_or_assign),
          obj,
          field,
          value ) ]
  | Parraylength _kind, [[arg]] ->
    (* See check in flambda2.ml that ensures we don't need to propagate the
       array kind. *)
    [Unary (Array_length, arg)]
  | Pduparray (kind, mutability), [[arg]] -> (
    let duplicate_array_kind =
      convert_array_kind_to_duplicate_array_kind kind
    in
    let source_mutability = Mutability.Immutable in
    let destination_mutability = Mutability.from_lambda mutability in
    match duplicate_array_kind with
    | Duplicate_array_kind duplicate_array_kind ->
      [ Unary
          ( Duplicate_array
              { kind = duplicate_array_kind;
                source_mutability;
                destination_mutability
              },
            arg ) ]
    | Float_array_opt_dynamic ->
      [ If_then_else
          ( Unary (Is_flat_float_array, arg),
            Unary
              ( Duplicate_array
                  { kind = Naked_floats { length = None };
                    source_mutability;
                    destination_mutability
                  },
                arg ),
            Unary
              ( Duplicate_array
                  { kind = Values; source_mutability; destination_mutability },
                arg ) ) ])
  | Pstringlength, [[arg]] -> [tag_int (Unary (String_length String, arg))]
  | Pbyteslength, [[arg]] -> [tag_int (Unary (String_length Bytes, arg))]
  | Pstringrefu, [[str]; [index]] ->
    [ string_like_load_unsafe ~access_size:Eight String None str index
        ~current_region ]
  | Pbytesrefu, [[bytes]; [index]] ->
    [ string_like_load_unsafe ~access_size:Eight Bytes None bytes index
        ~current_region ]
  | Pstringrefs, [[str]; [index]] ->
    [ string_like_load_safe ~dbg ~size_int ~access_size:Eight String None str
        index ~current_region ]
  | Pbytesrefs, [[bytes]; [index]] ->
    [ string_like_load_safe ~dbg ~size_int ~access_size:Eight Bytes None bytes
        index ~current_region ]
  | Pstring_load_16 true (* unsafe *), [[str]; [index]] ->
    [ string_like_load_unsafe ~access_size:Sixteen String None str index
        ~current_region ]
  | Pbytes_load_16 true (* unsafe *), [[bytes]; [index]] ->
    [ string_like_load_unsafe ~access_size:Sixteen Bytes None bytes index
        ~current_region ]
  | Pstring_load_32 (true (* unsafe *), mode), [[str]; [index]] ->
    [ string_like_load_unsafe ~access_size:Thirty_two String (Some mode) str
        index ~current_region ]
  | Pbytes_load_32 (true (* unsafe *), mode), [[bytes]; [index]] ->
    [ string_like_load_unsafe ~access_size:Thirty_two Bytes (Some mode) bytes
        index ~current_region ]
  | Pstring_load_64 (true (* unsafe *), mode), [[str]; [index]] ->
    [ string_like_load_unsafe ~access_size:Sixty_four String (Some mode) str
        index ~current_region ]
  | Pbytes_load_64 (true (* unsafe *), mode), [[bytes]; [index]] ->
    [ string_like_load_unsafe ~access_size:Sixty_four Bytes (Some mode) bytes
        index ~current_region ]
  | Pstring_load_16 false (* safe *), [[str]; [index]] ->
    [ string_like_load_safe ~dbg ~size_int ~access_size:Sixteen String None str
        index ~current_region ]
  | Pstring_load_32 (false (* safe *), mode), [[str]; [index]] ->
    [ string_like_load_safe ~dbg ~size_int ~access_size:Thirty_two String
        (Some mode) str index ~current_region ]
  | Pstring_load_64 (false (* safe *), mode), [[str]; [index]] ->
    [ string_like_load_safe ~dbg ~size_int ~access_size:Sixty_four String
        (Some mode) str index ~current_region ]
  | Pbytes_load_16 false (* safe *), [[bytes]; [index]] ->
    [ string_like_load_safe ~dbg ~size_int ~access_size:Sixteen Bytes None bytes
        index ~current_region ]
  | Pbytes_load_32 (false (* safe *), mode), [[bytes]; [index]] ->
    [ string_like_load_safe ~dbg ~size_int ~access_size:Thirty_two Bytes
        (Some mode) bytes index ~current_region ]
  | Pbytes_load_64 (false (* safe *), mode), [[bytes]; [index]] ->
    [ string_like_load_safe ~dbg ~size_int ~access_size:Sixty_four Bytes
        (Some mode) bytes index ~current_region ]
  | Pbytes_set_16 true (* unsafe *), [[bytes]; [index]; [new_value]] ->
    [bytes_like_set_unsafe ~access_size:Sixteen Bytes bytes index new_value]
  | Pbytes_set_32 true (* unsafe *), [[bytes]; [index]; [new_value]] ->
    [bytes_like_set_unsafe ~access_size:Thirty_two Bytes bytes index new_value]
  | Pbytes_set_64 true (* unsafe *), [[bytes]; [index]; [new_value]] ->
    [bytes_like_set_unsafe ~access_size:Sixty_four Bytes bytes index new_value]
  | Pbytes_set_16 false (* safe *), [[bytes]; [index]; [new_value]] ->
    [ bytes_like_set_safe ~dbg ~size_int ~access_size:Sixteen Bytes bytes index
        new_value ]
  | Pbytes_set_32 false (* safe *), [[bytes]; [index]; [new_value]] ->
    [ bytes_like_set_safe ~dbg ~size_int ~access_size:Thirty_two Bytes bytes
        index new_value ]
  | Pbytes_set_64 false (* safe *), [[bytes]; [index]; [new_value]] ->
    [ bytes_like_set_safe ~dbg ~size_int ~access_size:Sixty_four Bytes bytes
        index new_value ]
  | Pisint { variant_only }, [[arg]] ->
    [tag_int (Unary (Is_int { variant_only }, arg))]
  | Pisout, [[arg1]; [arg2]] ->
    [ tag_int
        (Binary
           ( Int_comp (I.Tagged_immediate, Yielding_bool (Lt Unsigned)),
             arg1,
             arg2 )) ]
  | Pbintofint (bi, mode), [[arg]] ->
    let dst = standard_int_or_float_of_boxed_integer bi in
    [ box_bint bi mode
        (Unary (Num_conv { src = I_or_f.Tagged_immediate; dst }, arg))
        ~current_region ]
  | Pintofbint bi, [[arg]] ->
    let src = standard_int_or_float_of_boxed_integer bi in
    [Unary (Num_conv { src; dst = I_or_f.Tagged_immediate }, unbox_bint bi arg)]
  | Pcvtbint (source, destination, mode), [[arg]] ->
    [ box_bint destination mode
        (Unary
           ( Num_conv
               { src = standard_int_or_float_of_boxed_integer source;
                 dst = standard_int_or_float_of_boxed_integer destination
               },
             unbox_bint source arg ))
        ~current_region ]
  | Pnegbint (bi, mode), [[arg]] ->
    [bint_unary_prim bi mode Neg arg ~current_region]
  | Paddbint (bi, mode), [[arg1]; [arg2]] ->
    [bint_binary_prim bi mode Add arg1 arg2 ~current_region]
  | Psubbint (bi, mode), [[arg1]; [arg2]] ->
    [bint_binary_prim bi mode Sub arg1 arg2 ~current_region]
  | Pmulbint (bi, mode), [[arg1]; [arg2]] ->
    [bint_binary_prim bi mode Mul arg1 arg2 ~current_region]
  | Pandbint (bi, mode), [[arg1]; [arg2]] ->
    [bint_binary_prim bi mode And arg1 arg2 ~current_region]
  | Porbint (bi, mode), [[arg1]; [arg2]] ->
    [bint_binary_prim bi mode Or arg1 arg2 ~current_region]
  | Pxorbint (bi, mode), [[arg1]; [arg2]] ->
    [bint_binary_prim bi mode Xor arg1 arg2 ~current_region]
  | Plslbint (bi, mode), [[arg1]; [arg2]] ->
    [bint_shift bi mode Lsl arg1 arg2 ~current_region]
  | Plsrbint (bi, mode), [[arg1]; [arg2]] ->
    [bint_shift bi mode Lsr arg1 arg2 ~current_region]
  | Pasrbint (bi, mode), [[arg1]; [arg2]] ->
    [bint_shift bi mode Asr arg1 arg2 ~current_region]
  | Poffsetint n, [[arg]] ->
    let const =
      Simple.const (Reg_width_const.tagged_immediate (Targetint_31_63.of_int n))
    in
    [Binary (Int_arith (I.Tagged_immediate, Add), arg, Simple const)]
  | Pfield (index, sem), [[arg]] ->
    let imm = Targetint_31_63.of_int index in
    check_non_negative_imm imm "Pfield";
    let field = Simple.const (Reg_width_const.tagged_immediate imm) in
    let mutability = convert_field_read_semantics sem in
    let block_access : P.Block_access_kind.t =
      Values { tag = Unknown; size = Unknown; field_kind = Any_value }
    in
    [Binary (Block_load (block_access, mutability), arg, Simple field)]
  | Pfloatfield (field, sem, mode), [[arg]] ->
    let imm = Targetint_31_63.of_int field in
    check_non_negative_imm imm "Pfloatfield";
    let field = Simple.const (Reg_width_const.tagged_immediate imm) in
    let mutability = convert_field_read_semantics sem in
    let block_access : P.Block_access_kind.t =
      Naked_floats { size = Unknown }
    in
    [ box_float mode
        (Binary (Block_load (block_access, mutability), arg, Simple field))
        ~current_region ]
  | ( Psetfield (index, immediate_or_pointer, initialization_or_assignment),
      [[block]; [value]] ) ->
    let field_kind = convert_block_access_field_kind immediate_or_pointer in
    let imm = Targetint_31_63.of_int index in
    check_non_negative_imm imm "Psetfield";
    let field = Simple.const (Reg_width_const.tagged_immediate imm) in
    let init_or_assign = convert_init_or_assign initialization_or_assignment in
    let block_access : P.Block_access_kind.t =
      Values { tag = Unknown; size = Unknown; field_kind }
    in
    [ Ternary
        (Block_set (block_access, init_or_assign), block, Simple field, value)
    ]
  | Psetfloatfield (field, initialization_or_assignment), [[block]; [value]] ->
    let imm = Targetint_31_63.of_int field in
    check_non_negative_imm imm "Psetfloatfield";
    let field = Simple.const (Reg_width_const.tagged_immediate imm) in
    let block_access : P.Block_access_kind.t =
      Naked_floats { size = Unknown }
    in
    let init_or_assign = convert_init_or_assign initialization_or_assignment in
    [ Ternary
        ( Block_set (block_access, init_or_assign),
          block,
          Simple field,
          unbox_float value ) ]
  | Pdivint Unsafe, [[arg1]; [arg2]] ->
    [Binary (Int_arith (I.Tagged_immediate, Div), arg1, arg2)]
  | Pdivint Safe, [[arg1]; [arg2]] ->
    [checked_arith_op ~dbg None Div None arg1 arg2 ~current_region]
  | Pmodint Safe, [[arg1]; [arg2]] ->
    [checked_arith_op ~dbg None Mod None arg1 arg2 ~current_region]
  | Pdivbint { size = Pint32; is_safe = Safe; mode }, [[arg1]; [arg2]] ->
    [ checked_arith_op ~dbg (Some Pint32) Div (Some mode) arg1 arg2
        ~current_region ]
  | Pmodbint { size = Pint32; is_safe = Safe; mode }, [[arg1]; [arg2]] ->
    [ checked_arith_op ~dbg (Some Pint32) Mod (Some mode) arg1 arg2
        ~current_region ]
  | Pdivbint { size = Pint64; is_safe = Safe; mode }, [[arg1]; [arg2]] ->
    [ checked_arith_op ~dbg (Some Pint64) Div (Some mode) arg1 arg2
        ~current_region ]
  | Pmodbint { size = Pint64; is_safe = Safe; mode }, [[arg1]; [arg2]] ->
    [ checked_arith_op ~dbg (Some Pint64) Mod (Some mode) arg1 arg2
        ~current_region ]
  | Pdivbint { size = Pnativeint; is_safe = Safe; mode }, [[arg1]; [arg2]] ->
    [ checked_arith_op ~dbg (Some Pnativeint) Div (Some mode) arg1 arg2
        ~current_region ]
  | Pmodbint { size = Pnativeint; is_safe = Safe; mode }, [[arg1]; [arg2]] ->
    [ checked_arith_op ~dbg (Some Pnativeint) Mod (Some mode) arg1 arg2
        ~current_region ]
  | Parrayrefu array_ref_kind, [[array]; [index]] ->
    (* For this and the following cases we will end up relying on the backend to
       CSE the two accesses to the array's header word in the [Pgenarray]
       case. *)
    [ match_on_array_ref_kind ~array array_ref_kind
        (array_load_unsafe ~array ~index ~current_region) ]
  | Parrayrefs array_ref_kind, [[array]; [index]] ->
    [ check_array_access ~dbg ~array ~index
        (match_on_array_ref_kind ~array array_ref_kind
           (array_load_unsafe ~array ~index ~current_region)) ]
  | Parraysetu array_set_kind, [[array]; [index]; [new_value]] ->
    [ match_on_array_set_kind ~array array_set_kind
        (array_set_unsafe ~array ~index ~new_value) ]
  | Parraysets array_set_kind, [[array]; [index]; [new_value]] ->
    [ check_array_access ~dbg ~array ~index
        (match_on_array_set_kind ~array array_set_kind
           (array_set_unsafe ~array ~index ~new_value)) ]
  | Pbytessetu (* unsafe *), [[bytes]; [index]; [new_value]] ->
    [bytes_like_set_unsafe ~access_size:Eight Bytes bytes index new_value]
  | Pbytessets, [[bytes]; [index]; [new_value]] ->
    [ bytes_like_set_safe ~dbg ~size_int ~access_size:Eight Bytes bytes index
        new_value ]
  | Poffsetref n, [[block]] ->
    let block_access : P.Block_access_kind.t =
      Values
        { tag = Known Tag.Scannable.zero;
          size = Known Targetint_31_63.one;
          field_kind = Immediate
        }
    in
    let old_ref_value =
      H.Prim
        (Binary
           (Block_load (block_access, Mutable), block, Simple Simple.const_zero))
    in
    let new_ref_value =
      H.Prim
        (Binary
           ( Int_arith (Tagged_immediate, Add),
             Simple (Simple.const_int (Targetint_31_63.of_int n)),
             old_ref_value ))
    in
    [ Ternary
        ( Block_set
            (block_access, Assignment (Alloc_mode.For_assignments.local ())),
          block,
          Simple Simple.const_zero,
          new_ref_value ) ]
  | Pctconst const, _ -> (
    match const with
    | Big_endian -> [Simple (Simple.const_bool big_endian)]
    | Word_size ->
      [Simple (Simple.const_int (Targetint_31_63.of_int (8 * size_int)))]
    | Int_size ->
      [Simple (Simple.const_int (Targetint_31_63.of_int ((8 * size_int) - 1)))]
    | Max_wosize ->
      [ Simple
          (Simple.const_int
             (Targetint_31_63.of_int
                ((1 lsl ((8 * size_int) - (10 + Config.profinfo_width))) - 1)))
      ]
    | Ostype_unix -> [Simple (Simple.const_bool (Sys.os_type = "Unix"))]
    | Ostype_win32 -> [Simple (Simple.const_bool (Sys.os_type = "Win32"))]
    | Ostype_cygwin -> [Simple (Simple.const_bool (Sys.os_type = "Cygwin"))]
    | Backend_type ->
      [Simple Simple.const_zero] (* constructor 0 is the same as Native here *))
  | Pbswap16, [[arg]] ->
    [ tag_int
        (Unary (Int_arith (Naked_immediate, Swap_byte_endianness), untag_int arg))
    ]
  | Pbbswap (Pint32, mode), [[arg]] ->
    [bbswap Naked_int32 Naked_int32 mode arg ~current_region]
  | Pbbswap (Pint64, mode), [[arg]] ->
    [bbswap Naked_int64 Naked_int64 mode arg ~current_region]
  | Pbbswap (Pnativeint, mode), [[arg]] ->
    [bbswap Naked_nativeint Naked_nativeint mode arg ~current_region]
  | Pint_as_pointer mode, [[arg]] ->
    let mode = Alloc_mode.For_allocations.from_lambda mode ~current_region in
    [Unary (Int_as_pointer mode, arg)]
  | Pbigarrayref (unsafe, num_dimensions, kind, layout), args -> (
    let args =
      List.map
        (function
          | [arg] -> arg
          | [] | _ :: _ :: _ ->
            Misc.fatal_errorf "Non-singleton arguments for Pbigarrayref: %a %a"
              Printlambda.primitive prim H.print_list_of_lists_of_simple_or_prim
              args)
        args
    in
    match
      P.Bigarray_kind.from_lambda kind, P.Bigarray_layout.from_lambda layout
    with
    | Some kind, Some layout ->
      let b, indexes =
        match args with
        | b :: indexes ->
          if List.compare_length_with indexes num_dimensions <> 0
          then Misc.fatal_errorf "Bad index arity for Pbigarrayref";
          b, indexes
        | [] -> Misc.fatal_errorf "Pbigarrayref is missing its arguments"
      in
      let box =
        bigarray_box_or_tag_raw_value_to_read kind
          Alloc_mode.For_allocations.heap
      in
      [box (bigarray_load ~dbg ~unsafe kind layout b indexes)]
    | None, _ ->
      Misc.fatal_errorf
        "Lambda_to_flambda_primitives.convert_lprim: Pbigarrayref primitives \
         with an unknown kind should have been removed by Lambda_to_flambda."
    | _, None ->
      Misc.fatal_errorf
        "Lambda_to_flambda_primitives.convert_lprim: Pbigarrayref primitives \
         with an unknown layout should have been removed by Lambda_to_flambda.")
  | Pbigarrayset (unsafe, num_dimensions, kind, layout), args -> (
    let args =
      List.map
        (function
          | [arg] -> arg
          | [] | _ :: _ :: _ ->
            Misc.fatal_errorf "Non-singleton arguments for Pbigarrayset: %a %a"
              Printlambda.primitive prim H.print_list_of_lists_of_simple_or_prim
              args)
        args
    in
    match
      P.Bigarray_kind.from_lambda kind, P.Bigarray_layout.from_lambda layout
    with
    | Some kind, Some layout ->
      let b, indexes, value =
        match args with
        | b :: args ->
          let indexes, value = Misc.split_last args in
          if List.compare_length_with indexes num_dimensions <> 0
          then Misc.fatal_errorf "Bad index arity for Pbigarrayset";
          b, indexes, value
        | [] -> Misc.fatal_errorf "Pbigarrayset is missing its arguments"
      in
      let unbox = bigarray_unbox_or_untag_value_to_store kind in
      [bigarray_set ~dbg ~unsafe kind layout b indexes (unbox value)]
    | None, _ ->
      Misc.fatal_errorf
        "Lambda_to_flambda_primitives.convert_lprim: Pbigarrayref primitives \
         with an unknown kind should have been removed by Lambda_to_flambda."
    | _, None ->
      Misc.fatal_errorf
        "Lambda_to_flambda_primitives.convert_lprim: Pbigarrayref primitives \
         with an unknown layout should have been removed by Lambda_to_flambda.")
  | Pbigarraydim dimension, [[arg]] ->
    [tag_int (Unary (Bigarray_length { dimension }, arg))]
  | Pbigstring_load_16 true (* unsafe *), [[big_str]; [index]] ->
    [ string_like_load_unsafe ~access_size:Sixteen Bigstring None big_str index
        ~current_region ]
  | Pbigstring_load_32 (true (* unsafe *), mode), [[big_str]; [index]] ->
    [ string_like_load_unsafe ~access_size:Thirty_two Bigstring (Some mode)
        big_str index ~current_region ]
  | Pbigstring_load_64 (true (* unsafe *), mode), [[big_str]; [index]] ->
    [ string_like_load_unsafe ~access_size:Sixty_four Bigstring (Some mode)
        big_str index ~current_region ]
  | Pbigstring_load_16 false (* safe *), [[big_str]; [index]] ->
    [ string_like_load_safe ~dbg ~size_int ~access_size:Sixteen Bigstring None
        big_str index ~current_region ]
  | Pbigstring_load_32 (false (* safe *), mode), [[big_str]; [index]] ->
    [ string_like_load_safe ~dbg ~size_int ~access_size:Thirty_two Bigstring
        (Some mode) big_str index ~current_region ]
  | Pbigstring_load_64 (false (* safe *), mode), [[big_str]; [index]] ->
    [ string_like_load_safe ~dbg ~size_int ~access_size:Sixty_four Bigstring
        (Some mode) big_str index ~current_region ]
  | Pbigstring_set_16 true (* unsafe *), [[bigstring]; [index]; [new_value]] ->
    [ bytes_like_set_unsafe ~access_size:Sixteen Bigstring bigstring index
        new_value ]
  | Pbigstring_set_32 true (* unsafe *), [[bigstring]; [index]; [new_value]] ->
    [ bytes_like_set_unsafe ~access_size:Thirty_two Bigstring bigstring index
        new_value ]
  | Pbigstring_set_64 true (* unsafe *), [[bigstring]; [index]; [new_value]] ->
    [ bytes_like_set_unsafe ~access_size:Sixty_four Bigstring bigstring index
        new_value ]
  | Pbigstring_set_16 false (* safe *), [[bigstring]; [index]; [new_value]] ->
    [ bytes_like_set_safe ~dbg ~size_int ~access_size:Sixteen Bigstring
        bigstring index new_value ]
  | Pbigstring_set_32 false (* safe *), [[bigstring]; [index]; [new_value]] ->
    [ bytes_like_set_safe ~dbg ~size_int ~access_size:Thirty_two Bigstring
        bigstring index new_value ]
  | Pbigstring_set_64 false (* safe *), [[bigstring]; [index]; [new_value]] ->
    [ bytes_like_set_safe ~dbg ~size_int ~access_size:Sixty_four Bigstring
        bigstring index new_value ]
  | Pcompare_ints, [[i1]; [i2]] ->
    [ tag_int
        (Binary
           ( Int_comp
               (Tagged_immediate, Yielding_int_like_compare_functions Signed),
             i1,
             i2 )) ]
  | Pcompare_floats, [[f1]; [f2]] ->
    [ tag_int
        (Binary
           ( Float_comp (Yielding_int_like_compare_functions ()),
             Prim (Unary (Unbox_number Naked_float, f1)),
             Prim (Unary (Unbox_number Naked_float, f2)) )) ]
  | Pcompare_bints int_kind, [[i1]; [i2]] ->
    let unboxing_kind = boxable_number_of_boxed_integer int_kind in
    [ tag_int
        (Binary
           ( Int_comp
               ( standard_int_of_boxed_integer int_kind,
                 Yielding_int_like_compare_functions Signed ),
             Prim (Unary (Unbox_number unboxing_kind, i1)),
             Prim (Unary (Unbox_number unboxing_kind, i2)) )) ]
  | Pprobe_is_enabled { name }, [] ->
    [tag_int (Nullary (Probe_is_enabled { name }))]
  | Pobj_dup, [[v]] -> [Unary (Obj_dup, v)]
  | Pget_header m, [[obj]] -> [get_header obj m ~current_region]
  | ( ( Pmodint Unsafe
      | Pdivbint { is_safe = Unsafe; size = _; mode = _ }
      | Pmodbint { is_safe = Unsafe; size = _; mode = _ }
      | Psetglobal _ | Praise _ | Pccall _ ),
      _ ) ->
    Misc.fatal_errorf
      "Closure_conversion.convert_primitive: Primitive %a (%a) shouldn't be \
       here, either a bug in [Closure_conversion] or the wrong number of \
       arguments"
      Printlambda.primitive prim H.print_list_of_lists_of_simple_or_prim args
  | Pprobe_is_enabled _, _ :: _ ->
    Misc.fatal_errorf
      "Closure_conversion.convert_primitive: Wrong arity for nullary primitive \
       %a (%a)"
      Printlambda.primitive prim H.print_list_of_simple_or_prim
      (List.flatten args)
  | ( ( Pfield _ | Pnegint | Pnot | Poffsetint _ | Pintoffloat | Pfloatofint _
      | Pnegfloat _ | Pabsfloat _ | Pstringlength | Pbyteslength | Pbintofint _
      | Pintofbint _ | Pnegbint _ | Popaque _ | Pduprecord _ | Parraylength _
      | Pduparray _ | Pfloatfield _ | Pcvtbint _ | Poffsetref _ | Pbswap16
      | Pbbswap _ | Pisint _ | Pint_as_pointer _ | Pbigarraydim _ | Pobj_dup
      | Pobj_magic _ | Punbox_float | Pbox_float _ | Punbox_int _ | Pbox_int _
      | Pget_header _ ),
      ([] | _ :: _ :: _ | [([] | _ :: _ :: _)]) ) ->
    Misc.fatal_errorf
      "Closure_conversion.convert_primitive: Wrong arity for unary primitive \
       %a (%a)"
      Printlambda.primitive prim H.print_list_of_lists_of_simple_or_prim args
  | ( ( Paddint | Psubint | Pmulint | Pandint | Porint | Pxorint | Plslint
      | Plsrint | Pasrint | Pdivint _ | Pmodint _ | Psetfield _ | Pintcomp _
      | Paddfloat _ | Psubfloat _ | Pmulfloat _ | Pdivfloat _ | Pfloatcomp _
      | Pstringrefu | Pbytesrefu | Pstringrefs | Pbytesrefs | Pstring_load_16 _
      | Pstring_load_32 _ | Pstring_load_64 _ | Pbytes_load_16 _
      | Pbytes_load_32 _ | Pbytes_load_64 _ | Pisout | Paddbint _ | Psubbint _
      | Pmulbint _ | Pandbint _ | Porbint _ | Pxorbint _ | Plslbint _
      | Plsrbint _ | Pasrbint _ | Pfield_computed _ | Pdivbint _ | Pmodbint _
      | Psetfloatfield _ | Pbintcomp _ | Pbigstring_load_16 _
      | Pbigstring_load_32 _ | Pbigstring_load_64 _
      | Parrayrefu
          (Pgenarray_ref _ | Paddrarray_ref | Pintarray_ref | Pfloatarray_ref _)
      | Parrayrefs
          (Pgenarray_ref _ | Paddrarray_ref | Pintarray_ref | Pfloatarray_ref _)
      | Pcompare_ints | Pcompare_floats | Pcompare_bints _ ),
      ( []
      | [_]
      | _ :: _ :: _ :: _
      | [_; ([] | _ :: _ :: _)]
      | [([] | _ :: _ :: _); _] ) ) ->
    Misc.fatal_errorf
      "Closure_conversion.convert_primitive: Wrong arity for binary primitive \
       %a (%a)"
      Printlambda.primitive prim H.print_list_of_lists_of_simple_or_prim args
  | ( ( Psetfield_computed _ | Pbytessetu | Pbytessets
      | Parraysetu
          (Pgenarray_set _ | Paddrarray_set _ | Pintarray_set | Pfloatarray_set)
      | Parraysets
          (Pgenarray_set _ | Paddrarray_set _ | Pintarray_set | Pfloatarray_set)
      | Pbytes_set_16 _ | Pbytes_set_32 _ | Pbytes_set_64 _
      | Pbigstring_set_16 _ | Pbigstring_set_32 _ | Pbigstring_set_64 _ ),
      ( []
      | [_]
      | [_; _]
      | _ :: _ :: _ :: _ :: _
      | [_; _; ([] | _ :: _ :: _)]
      | [_; ([] | _ :: _ :: _); _]
      | [([] | _ :: _ :: _); _; _] ) ) ->
    Misc.fatal_errorf
      "Closure_conversion.convert_primitive: Wrong arity for ternary primitive \
       %a (%a)"
      Printlambda.primitive prim H.print_list_of_lists_of_simple_or_prim args
  | ( ( Pignore | Psequand | Psequor | Pbytes_of_string | Pbytes_to_string
      | Parray_of_iarray | Parray_to_iarray ),
      _ ) ->
    Misc.fatal_errorf
      "[%a] should have been removed by [Lambda_to_flambda.transform_primitive]"
      Printlambda.primitive prim
  | Pgetglobal _, _ | Pgetpredef _, _ ->
    Misc.fatal_errorf
      "[%a] should have been handled by [Closure_conversion.close_primitive]"
      Printlambda.primitive prim

module Acc = Closure_conversion_aux.Acc
module Expr_with_acc = Closure_conversion_aux.Expr_with_acc

let convert_and_bind acc ~big_endian exn_cont ~register_const0
    (prim : L.primitive) ~(args : Simple.t list list) (dbg : Debuginfo.t)
    ~current_region (cont : Acc.t -> Flambda.Named.t list -> Expr_with_acc.t) :
    Expr_with_acc.t =
  let exprs = convert_lprim ~big_endian prim args dbg ~current_region in
  H.bind_recs acc exn_cont ~register_const0 exprs dbg cont
