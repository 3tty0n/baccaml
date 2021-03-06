open Std
open MinCaml
open Asm
open Jit_env
open Jit_util
open Jit_prof
open Printf
module Util = Jit_tracer_util

let pp = print_endline
let sp = sprintf
let other_deps : string list ref = ref []

type mj_env =
  { trace_name : string
  ; red_names : string list
  ; index_pc : int
  ; merge_pc : int
  ; function_pcs : int list
  ; bytecode : int array
  }

let create_mj_env
    ~trace_name
    ~red_names
    ~index_pc
    ~merge_pc
    ~function_pcs
    ~bytecode
  =
  { trace_name; red_names; index_pc; merge_pc; function_pcs; bytecode }
;;

let to_jit_env
    { trace_name; red_names; index_pc; merge_pc; function_pcs; bytecode }
  =
  create_env ~trace_name ~red_names ~index_pc ~merge_pc ~bytecode ~current_pc:0
;;

let rec mj
    p
    reg
    mem
    ({ trace_name; red_names; index_pc; merge_pc; function_pcs; bytecode } as
    env)
    fenv
  = function
  | Ans (CallDir (id_l, args, fargs)) ->
    let { name; args = argst; fargs; body; ret } = fenv "interp" in
    { name; args = argst; fargs; body; ret }
    |> Inlining.inline_fundef reg args
    |> mj p reg mem env fenv
  | Ans exp -> exp |> mj_exp p reg mem env fenv
  | Let ((x, typ), CallDir (Id.L "min_caml_jit_merge_point", args, fargs), body)
    ->
    let pc = List.nth args (index_pc) |> int_of_id_t |> Array.get reg |> value_of in
    Log.debug ("jit_merge_point: " ^ string_of_int pc);
    mj p reg mem env fenv body
  | Let ((x, typ), CallDir (Id.L "min_caml_can_enter_jit", args, fargs), body)
    ->
    let pc =
      List.nth args index_pc |> int_of_id_t |> Array.get reg |> value_of
    in
    Log.debug ("can_enter_jit: " ^ string_of_int pc);
    if pc = merge_pc
    then Ans (CallDir (Id.L trace_name, Util.filter ~reds:red_names args, []))
    else mj p reg mem env fenv body
  | Let ((x, typ), CallDir (Id.L "min_caml_mj_call", args, fargs), body) ->
    let pc = Util.value_of_id_t reg (List.nth args index_pc) in
    let reds = Util.filter red_names args in
    if pc = merge_pc
    then
      Let
        ( (x, typ)
        , CallDir (Id.L trace_name, reds, fargs)
        , mj p reg mem env fenv body )
    else
      Option.fold
        (Trace_prof.find_opt pc)
        ~some:(fun tname ->
          other_deps := !other_deps @ [ tname ];
          Jit_guard.restore
            reg
            ~args
            (Let
               ( (x, typ)
               , CallDir (Id.L tname, args, fargs)
               , mj p reg mem env fenv body )))
        ~none:
          (Option.fold
             (Method_prof.find_opt pc)
             ~some:(fun tname ->
               other_deps := !other_deps @ [ tname ];
               Jit_guard.restore
                 reg
                 ~args
                 (Let
                    ( (x, typ)
                    , CallDir (Id.L tname, args, fargs)
                    , mj p reg mem env fenv body )))
             ~none:
               (Jit_guard.restore
                  reg
                  ~args
                  (Let
                     ( (x, typ)
                     , CallDir (Id.L "interp_no_hints", args, fargs)
                     , mj p reg mem env fenv body ))))
  | Let ((x, typ), CallDir (Id.L x', args, fargs), body)
    when String.(
           starts_with x' "cast_"
           || starts_with x' "frame_reset"
           || starts_with x' "min_caml_") ->
    Util.restore_greens reg args (fun _ ->
        Let
          ((x, typ), CallDir (Id.L x', args, fargs), mj p reg mem env fenv body))
  | Let ((x, typ), CallDir (id_l, args, fargs), body) ->
    let reds = Util.filter ~reds:red_names args in
    Jit_guard.restore
      reg
      ~args
      (Let ((x, typ), CallDir (id_l, reds, []), mj p reg mem env fenv body))
  | Let ((x, typ), exp, body) ->
    (match exp with
    | IfEq _ | IfGE _ | IfLE _ | SIfEq _ | SIfLE _ | SIfGE _ ->
      let t' = mj_if p reg mem env fenv exp in
      let k = mj p reg mem env fenv body in
      Asm.concat t' (x, typ) k
    | St (id_t1, id_t2, id_or_imm, bitsize) ->
      let srcv = reg.(int_of_id_t id_t1) in
      let destv = reg.(int_of_id_t id_t2) in
      let offsetv =
        match id_or_imm with V id -> reg.(int_of_id_t id) | C n -> Green n
      in
      (match srcv, destv with
      | Green n1, Red n2 ->
        reg.(int_of_id_t id_t1) <- Green 0;
        mem.(n1 + (n2 * bitsize)) <- Green (reg.(int_of_id_t id_t1) |> value_of);
        (match offsetv with
        | Green n ->
          let id' = Id.gentmp Type.Int in
          Let
            ( (id_t1, Type.Int)
            , Set n1
            , Let
                ( (id', Type.Int)
                , Set n
                , Let
                    ( (x, typ)
                    , St (id_t1, id_t2, C n, bitsize)
                    , mj p reg mem env fenv body ) ) )
        | Red n ->
          Let
            ( (id_t1, Type.Int)
            , Set n1
            , Let
                ( (x, typ)
                , St (id_t1, id_t2, id_or_imm, bitsize)
                , mj p reg mem env fenv body ) ))
      | _ -> optimize_exp p reg mem (x, typ) env exp fenv body)
    | _ -> optimize_exp p reg mem (x, typ) env exp fenv body)

and optimize_exp p reg mem (x, typ) env exp fenv body =
  match Jit_optimizer.run p exp reg mem with
  | Specialized v ->
    reg.(int_of_id_t x) <- v;
    mj p reg mem env fenv body
  | Not_specialized (e, v) ->
    reg.(int_of_id_t x) <- v;
    Let ((x, typ), e, mj p reg mem env fenv body)

and mj_exp p reg mem ({ index_pc; merge_pc; bytecode } as env) fenv = function
  | CallDir (id_l, argsr, fargs) ->
    fenv "interp" |> Inlining.inline_fundef reg argsr |> mj p reg mem env fenv
  | (IfEq _ | IfLE _ | IfGE _ | SIfEq _ | SIfGE _ | SIfLE _) as exp ->
    mj_if p reg mem env fenv exp
  | exp ->
    (match Jit_optimizer.run p exp reg mem with
    | Specialized v ->
      let id = Id.gentmp Type.Int in
      Let ((id, Type.Int), Set (value_of v), Ans (Mov id))
    | Not_specialized (e, v) -> Ans e)

and mj_if p reg mem ({ index_pc; merge_pc; trace_name; bytecode } as env) fenv =
  let open Util in
  function
  | ( IfEq (id_t, id_or_imm, t1, t2)
    | IfLE (id_t, id_or_imm, t1, t2)
    | IfGE (id_t, id_or_imm, t1, t2) ) as exp ->
    if String.get_name id_t = "mode"
    then (
      let module G = Jit_guard in
      let guard_code = G.TJ.create reg (to_jit_env env) t1 in
      Log.debug
      @@ sp
           "mode checking ==> IfEq(%d, %d)"
           (value_of @@ reg.(int_of_id_t id_t))
           100;
      Ans (IfEq (id_t, id_or_imm, guard_code, mj p reg mem env fenv t2)))
    else (
      let r1 = reg.(int_of_id_t id_t) in
      let r2 =
        match id_or_imm with V x -> reg.(int_of_id_t x) | C n -> Green n
      in
      let n1, n2 = value_of r1, value_of r2 in
      (* Log.debug
       * @@ sp "If (%s, %s) ==> %d %d" id_t (string_of_id_or_imm id_or_imm) n1 n2; *)
      if exp <=> (n1, n2)
      then mj p reg mem env fenv t1
      else mj p reg mem env fenv t2)
  | ( SIfEq (id_t, id_or_imm, t1, t2)
    | SIfGE (id_t, id_or_imm, t1, t2)
    | SIfLE (id_t, id_or_imm, t1, t2) ) as exp ->
    let reg1 = Array.copy reg in
    let reg2 = Array.copy reg in
    let mem1 = Array.copy mem in
    let mem2 = Array.copy mem in
    let r1 = reg.(int_of_id_t id_t) in
    let r2 = reg.(int_of_id_or_imm id_or_imm) in
    (match r1, r2 with
    | Green n1, Green n2 ->
      if exp <=> (n1, n2)
      then t1 |> mj p reg mem env fenv
      else t2 |> mj p reg mem env fenv
    | Red n1, Green n2 ->
      let t1' = mj p reg1 mem1 env fenv t1 in
      let t2' = mj p reg2 mem2 env fenv t2 in
      Ans (exp <|> (id_t, C n2, t1', t2'))
    | Green n1, Red n2 ->
      let t1' = mj p reg1 mem1 env fenv t1 in
      let t2' = mj p reg2 mem2 env fenv t2 in
      let id_t' = match id_or_imm with V id -> id | C _ -> assert false in
      Ans (exp <|> (id_t', C n1, t2', t1'))
    | Red n1, Red n2 ->
      let t1' = mj p reg1 mem1 env fenv t1 in
      let t2' = mj p reg2 mem2 env fenv t2 in
      Ans (exp <|> (id_t, id_or_imm, t1', t2')))
  | e -> failwith (sprintf "un matched pattern in mj_if: %s" (show_exp e))
;;

let run
    prog
    reg
    mem
    ({ trace_name; red_names; index_pc; merge_pc; bytecode } : env)
  =
  Renaming.counter := !Id.counter;
  let fenv name = Fundef.find_fuzzy prog ~name in
  let { args; body } = fenv "interp" in
  let reds =
    args |> List.find_all (fun x -> List.mem (String.get_name x) red_names)
  in
  let env =
    { trace_name
    ; red_names
    ; index_pc
    ; merge_pc
    ; function_pcs = [ merge_pc ]
    ; bytecode
    }
  in
  let trace = mj prog reg mem env fenv body in
  `Result
    ( create_fundef
        ~name:(Id.L env.trace_name)
        ~args:reds
        ~fargs:[]
        ~body:trace
        ~ret:Type.Int
    , if List.length !other_deps = 0 then None else Some !other_deps )
;;
