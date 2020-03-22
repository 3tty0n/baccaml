open Std
open MinCaml
open Asm
open Printf

let ep = eprintf
let sp = sprintf
let pp = printf

let ( <=> ) e (x, y, t1, t2) =
  match e with
  | IfEq _ -> IfEq (x, y, t1, t2)
  | IfLE _ -> IfLE (x, y, t1, t2)
  | IfGE _ -> IfGE (x, y, t1, t2)
  | _ -> failwith "unexpected expression."
;;

let contains2 var (id_t, id_or_imm) =
  let open Asm in
  var = id_t || match id_or_imm with C n -> false | V x -> var = x
;;

let contains3 var (id_t1, id_t2, id_or_imm) =
  let open Asm in
  var = id_t1 || var = id_t2 || match id_or_imm with C n -> false | V x -> var = x
;;

let rec find var t =
  match t with
  | Let (_, Mov x, t') when var = x -> true
  | Let (_, Add (x, y), t')
  | Let (_, Sub (x, y), t')
  | Let (_, Mul (x, y), t')
  | Let (_, Div (x, y), t')
  | Let (_, Mod (x, y), t')
    when contains2 var (x, y) ->
    true
  | Let (_, IfEq (x, y, t1, t2), t')
  | Let (_, IfLE (x, y, t1, t2), t')
  | Let (_, IfGE (x, y, t1, t2), t')
    when contains2 var (x, y) ->
    true
  | (Ans (IfEq (x, y, t1, t2)) | Ans (IfLE (x, y, t1, t2)) | Ans (IfGE (x, y, t1, t2)))
    when contains2 var (x, y) ->
    true
  | Let (_, e, t) -> find var t
  | Ans (IfEq (x, y, t1, t2)) | Ans (IfLE (x, y, t1, t2)) | Ans (IfGE (x, y, t1, t2)) ->
    find var t1 || find var t2
  | Ans _ -> false
;;

let%test "find test" =
  let t =
    Let
      ( ("x.2", Type.Int)
      , Add ("arg1.1", C 1)
      , Let (("y.3", Type.Int), Add ("x.2", C 3), Ans (Mov "y.3")) )
  in
  find "x.2" t = true
;;

module Const_fold = struct
  let empty_env = M.empty
  let extend_env var exp env = M.add var exp env
  let exists_var var env = M.mem var env
  let lookup key env = M.find key env

  (* for tracing *)
  let rec is_guard_path = function
    | Let (_, e, t) -> is_guard_path_exp e || is_guard_path t
    | Ans e -> is_guard_path_exp e

  and is_guard_path_exp = function
    | CallDir (Id.L x, _, _) -> String.starts_with x "guard_"
    | _ -> false
  ;;

  let%test "is_guard_path test" =
    let t =
      Let
        ( ("pc.402.1292", Int)
        , Set 16
        , Let
            ( ("bytecode.401.1293", Int)
            , CallDir (L "restore_min_caml_bp", [], [])
            , Let
                ( ("Ti195.686.1424", Int)
                , Add ("pc.402.1292", C 2)
                , Ans
                    (CallDir
                       ( L "guard_tracetj0.844"
                       , [ "stack.399"
                         ; "sp2.683.1423"
                         ; "bytecode.401.1293"
                         ; "Ti195.686.1424"
                         ]
                       , [] )) ) ) )
    in
    is_guard_path t = true
  ;;

  let rec is_occur var = function
    | Let (_, e, t) -> is_occur_exp var e || is_occur var t
    | Ans e ->
      (match e with
      | IfEq (x, V y, t1, t2) | IfLE (x, V y, t1, t2) | IfGE (x, V y, t1, t2) ->
        var = x || var = y || is_occur var t1 || is_occur var t2
      | IfEq (x, C _, t1, t2) | IfLE (x, C _, t1, t2) | IfGE (x, C _, t1, t2) ->
        var = x || is_occur var t1 || is_occur var t2
      | _ -> is_occur_exp var e)

  and is_occur_exp (var : Id.t) (e : Asm.exp) : bool =
    match e with
    | Nop -> false
    | Mov x -> x = var
    | Add (x, V y) | Sub (x, V y) | Mul (x, V y) | Div (x, V y) | Mod (x, V y) ->
      x = var || y = var
    | Add (x, C _) | Sub (x, C _) | Mul (x, C _) | Div (x, C _) | Mod (x, C _) -> x = var
    | Ld (x, V y, _) -> x = var || y = var
    | Ld (x, C _, _) -> x = var
    | St (x, y, V z, _) -> x = var || y = var || z = var
    | St (x, y, C _, _) -> x = var || y = var
    | IfEq (x, V y, _, _) | IfLE (x, V y, _, _) | IfGE (x, V y, _, _) ->
      x = var || y = var
    | IfEq (x, C _, _, _) | IfLE (x, C _, _, _) | IfGE (x, C _, _, _) -> x = var
    | CallCls (x, args, fargs) -> x = var || List.mem var args || List.mem var fargs
    | CallDir (Id.L x, args, fargs) -> x = var || List.mem var args || List.mem var fargs
    | _ -> false
  ;;

  let%test_module "is_occur test" =
    (module struct
      let t =
        Let
          ( ("Ti242.609", Int)
          , Sub ("sp.400", C 2)
          , Let
              ( ("Ti244.611", Int)
              , Sub ("sp.400", C 3)
              , Let
                  ( ("v.612", Int)
                  , Ld ("stack.399", V "Ti244.611", 4)
                  , Let
                      ( ("Tu24.613", Unit)
                      , St ("v.612", "stack.399", V "sp.400", 4)
                      , Let
                          ( ("Ti246.615", Int)
                          , Add ("sp.400", C 1)
                          , Let
                              ( ("sp.400.848", Int)
                              , Add ("sp.400", C 1)
                              , Let
                                  ( ("Ti333.507.868", Int)
                                  , Set 0
                                  , Ans (Mov "Ti333.507.868") ) ) ) ) ) ) )
      ;;

      let%test _ = is_occur "Ti242.609" t = false
      let%test _ = is_occur "Ti333.507.868" t = true
    end)
  ;;

  let specialize lhs rhs =
    Option.(
      match lhs, rhs with
      | Add (x, C n), Add (y, C m) -> Add (x, C (n + m)) |> some
      | Add (x, C n), Sub (y, C m) -> Add (x, C (n - m)) |> some
      | Sub (x, C n), Add (y, C m) -> Sub (x, C (n - m)) |> some
      | Sub (x, C n), Sub (y, C m) -> Sub (x, C (n + m)) |> some
      | _ -> none)
  ;;

  let rec const_fold_mov env = function
    | Let ((var, typ), Mov x, t) ->
      ep "var: %s, x: %s\n" var x;
      let env = extend_env var x env in
      const_fold_mov env t
    | Let ((var, typ), e, t) ->
      (match e with
      | Add (x, y) ->
        (match M.find_opt x env with
        | Some var2 -> Let ((var, typ), Add (var2, y), const_fold_mov env t)
        | None -> Let ((var, typ), e, const_fold_mov env t))
      | Sub (x, y) ->
        (match M.find_opt x env with
        | Some var2 -> Let ((var, typ), Sub (var2, y), const_fold_mov env t)
        | None -> Let ((var, typ), e, const_fold_mov env t))
      | Ld (x, V y, z) ->
        (match M.find_opt x env with
        | Some var2 -> Let ((var, typ), Ld (var2, V y, z), const_fold_mov env t)
        | None ->
          (match M.find_opt y env with
          | Some var2 -> Let ((var, typ), Ld (x, V var2, z), const_fold_mov env t)
          | None -> Let ((var, typ), e, const_fold_mov env t)))
      | St (x, y, V z, w) ->
        (match M.find_opt x env with
        | Some var2 -> Let ((var, typ), St (var2, y, V z, w), const_fold_mov env t)
        | None ->
          (match M.find_opt y env with
          | Some var2 -> Let ((var, typ), St (x, var2, V z, w), const_fold_mov env t)
          | None ->
            (match M.find_opt z env with
            | Some var2 -> Let ((var, typ), St (x, y, V var2, w), const_fold_mov env t)
            | None -> Let ((var, typ), e, const_fold_mov env t))))
      | CallCls (x, args, fargs) ->
        Let
          ( (var, typ)
          , CallCls
              ( (if M.mem x env then M.find x env else x)
              , args |> List.map (fun x -> if M.mem x env then M.find x env else x)
              , fargs |> List.map (fun x -> if M.mem x env then M.find x env else x) )
          , const_fold_mov env t )
      | CallDir (id_l, args, fargs) ->
        Let
          ( (var, typ)
          , CallDir
              ( id_l
              , args |> List.map (fun x -> if M.mem x env then M.find x env else x)
              , fargs |> List.map (fun x -> if M.mem x env then M.find x env else x) )
          , const_fold_mov env t )
      | _ -> Let ((var, typ), e, const_fold_mov env t))
    | Ans e -> Ans e
  ;;

  let rec elim_dead_exp = function
    | Let ((var, Type.Unit), e, t) ->
      (* side effect *)
      Let ((var, Type.Unit), e, elim_dead_exp t)
    | Let ((var, typ), e, t) ->
      if is_occur var t then Let ((var, typ), e, elim_dead_exp t) else elim_dead_exp t
    | Ans (IfEq (x, y, t1, t2)) -> Ans (IfEq (x, y, elim_dead_exp t1, elim_dead_exp t2))
    | Ans (IfLE (x, y, t1, t2)) -> Ans (IfLE (x, y, elim_dead_exp t1, elim_dead_exp t2))
    | Ans (IfGE (x, y, t1, t2)) -> Ans (IfGE (x, y, elim_dead_exp t1, elim_dead_exp t2))
    | Ans e -> Ans e
  ;;

  let rec const_fold env = function
    | Let ((var, typ), Mov x, t) when exists_var x env ->
      let exp' = M.find x env in
      let env = extend_env var exp' env in
      Let ((var, typ), exp', const_fold env t)
    | Let ((var, typ), Add (x, y), t) when exists_var x env ->
      let lhs = M.find x env in
      (match specialize lhs (Add (x, y)) with
      | Some e_res ->
        let env = extend_env var e_res env in
        Let ((var, typ), e_res, const_fold env t)
      | None ->
        let env = extend_env var (Add (x, y)) env in
        Let ((var, typ), Add (x, y), const_fold env t))
    | Let ((var, typ), Sub (x, y), t) when exists_var x env ->
      let lhs = M.find x env in
      (match specialize lhs (Sub (x, y)) with
      | Some e_res ->
        let env = extend_env var e_res env in
        Let ((var, typ), e_res, const_fold env t)
      | None ->
        let env = extend_env var (Sub (x, y)) env in
        Let ((var, typ), Sub (x, y), const_fold env t))
    | Let ((var, typ), e, t) ->
      let env = extend_env var e env in
      Let ((var, typ), e, const_fold env t)
    | Ans e ->
      (match e with
      | IfEq (x, y, t1, t2) | IfGE (x, y, t1, t2) | IfLE (x, y, t1, t2) ->
        if is_guard_path t2
        then Ans (e <=> (x, y, const_fold env t1, t2))
        else Ans (e <=> (x, y, t1, const_fold env t2))
      | _ -> Ans e)
  ;;

  let rec const_fold_if env = function
    | Let (x, e, t) -> Let (x, e, const_fold_if env t)
    | Ans e ->
      (match e with
      | IfLE (x, y, t1, t2) | IfGE (x, y, t1, t2) | IfEq (x, y, t1, t2) ->
        if is_guard_path t2
        then (
          let t = const_fold env t1 |> const_fold_mov empty_env |> elim_dead_exp in
          Ans (e <=> (x, y, t, t2)))
        else (
          let t = const_fold env t2 |> const_fold_mov empty_env |> elim_dead_exp in
          Ans (e <=> (x, y, t1, t)))
      | _ -> Ans e)
  ;;

  type offset = int
  type sp = Sp of string * offset

  module M_int = Map.Make(struct type t = offset;; let compare = compare;; end)

  let rec const_fold_stld (offset_env : sp M.t) (stld_env : Id.t M_int.t) = function
    | Let ((var, typ), e, t) ->
      (match e with
      | Add (x, C n) ->
        let offset_env = extend_env var (Sp (x, n)) offset_env in
        Let ((var, typ), e, const_fold_stld offset_env stld_env t)
      | Sub (x, C n) ->
        let offset_env = extend_env var (Sp (x, -n)) offset_env in
        Let ((var, typ), e, const_fold_stld offset_env stld_env t)
      | St (x, y, V z, w) ->
        let Sp (_, offset) = lookup z offset_env in
        let stld_env = M_int.add offset x stld_env in
        Let ((var, typ), e, const_fold_stld offset_env stld_env t)
      | _ -> Let ((var, typ), e, const_fold_stld offset_env stld_env t))
    | Ans e -> Ans e
  ;;
end
