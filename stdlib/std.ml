let ( %> ) f g x = g (f x)
let ( $ ) f g x = f (g x)

module Array = struct
  include Array

  let string_of_array f arr =
    "[|" ^ (arr |> Array.to_list |> List.map f |> String.concat "; ") ^ "|]"
  ;;

  let print_array f arr =
    print_string "[|";
    Array.iter
      (fun a ->
        f a;
        print_string "; ")
      arr;
    print_string "|]"
  ;;
end

module String = struct
  include String

  let get_name x = x |> String.split_on_char '.' |> List.hd
  let get_extension x = x |> String.split_on_char '.' |> List.rev |> List.hd

  let contains s1 s2 =
    let re = Str.regexp_string s2 in
    try
      ignore (Str.search_forward re s1 0);
      true
    with
    | Not_found -> false
  ;;

  let starts_with s1 s2 =
    let re = Str.regexp_string s2 in
    try if Str.search_forward re s1 0 = 0 then true else false with
    | Not_found -> false
  ;;

  let%test "get_name test" = get_name "Ti23.55" = "Ti23"
  let%test "starts_with test 1" = (starts_with "min_caml_print_int") "min_caml"

  let%test "starts_with test 2" =
    not (starts_with "__min_caml_print_int" "min_caml")
  ;;
end

module List = struct
  include List

  let string_of f lst = "[" ^ String.concat "; " (List.map f lst) ^ "]"

  let rec unique list =
    let rec go l s =
      match l with
      | [] -> s
      | first :: rest ->
        if List.exists (fun e -> e = first) s
        then go rest s
        else go rest (s @ [ first ])
    in
    go list []
  ;;

  let rec last = function
    | [] -> failwith "last"
    | [ x ] -> x
    | hd :: tl -> last tl
  ;;

  let index elem lst =
    let rec go elem lst i =
      match lst with
      | [] -> raise Not_found
      | hd :: tl -> if hd = elem then i else go elem tl (i + 1)
    in
    go elem lst 0
  ;;

  let index_opt elem lst =
    let rec go elem lst i =
      match lst with
      | [] -> None
      | hd :: tl -> if hd = elem then Some i else go elem tl (i + 1)
    in
    go elem lst 0
  ;;
end
