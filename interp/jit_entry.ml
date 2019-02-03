open Utils.Std
open MinCaml
open Bc_jit

open Jit_util

(* For test *)
let dummy_fun x =
  print_string "apply dummy_fun to " ;
  print_int x ;
  print_newline () ;
  print_string "executed file is " ;
  print_endline Sys.argv.(0) ;
  x + 1

let size = 100000

let make_reg prog stack =
  let reg = Array.make size (Red 0) in
  let interp = find_fundef' prog "interp" in
  ()

let jit_entry bytecode stack values =
  Array.print_array print_int bytecode; print_newline ();
  Array.print_array print_int stack; print_newline ();
  Array.print_array print_int values; print_newline ();
  let reg = Array.make size (Red 0) in
  let mem = Array.make size (Green 0) in
  let ic = open_in "./test_interp.mcml" in
  let prog = Lexing.from_channel ic |> Util.virtualize in
  Emit_virtual.string_of_prog prog |> print_endline ;
  ()

let () =
  Callback.register "jit_entry" jit_entry ;
  Callback.register "dummy_fun" dummy_fun