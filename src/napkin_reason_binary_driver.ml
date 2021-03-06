


module IO: sig
  val readFile: string -> string
  val readStdin: unit -> string
end = struct
  (* random chunk size: 2^15, TODO: why do we guess randomly? *)
  let chunkSize = 32768

  let readFile filename =
    let chan = open_in filename in
    let buffer = Buffer.create chunkSize in
    let chunk = (Bytes.create [@doesNotRaise]) chunkSize in
    let rec loop () =
      let len = try input chan chunk 0 chunkSize with Invalid_argument _ -> 0 in
      if len == 0 then (
        close_in_noerr chan;
        Buffer.contents buffer
      ) else (
        Buffer.add_subbytes buffer chunk 0 len;
        loop ()
      )
    in
    loop ()

  let readStdin () =
    let buffer = Buffer.create chunkSize in
    let chunk = (Bytes.create [@doesNotRaise]) chunkSize in
    let rec loop () =
      let len = try input stdin chunk 0 chunkSize with Invalid_argument _ -> 0 in
      if len == 0 then (
        close_in_noerr stdin;
        Buffer.contents buffer
      ) else (
        Buffer.add_subbytes buffer chunk 0 len;
        loop ()
      )
    in
    loop ()
end

let isReasonDocComment (comment: Napkin_comment.t) =
  let content = Napkin_comment.txt comment in
  let len = String.length content in
  if len = 0 then true
  else if len >= 2 && (String.unsafe_get content 0 = '*' && String.unsafe_get content 1 = '*') then false
  else if len >= 1 && (String.unsafe_get content 0 = '*') then true
  else false

let extractConcreteSyntax filename =
  let commentData = ref [] in
  let stringData = ref [] in
  let src =
    if String.length filename > 0 then IO.readFile filename
    else IO.readStdin ()
  in
  let scanner = Napkin_scanner.make (Bytes.of_string src) filename in

  let rec next prevEndPos scanner =
    let (startPos, endPos, token) = Napkin_scanner.scan scanner in
    match token with
    | Eof -> ()
    | Comment c ->
      Napkin_comment.setPrevTokEndPos c prevEndPos;
      commentData := c::(!commentData);
      next endPos scanner
    | String _ ->
      let loc = {Location.loc_start = startPos; loc_end = endPos; loc_ghost = false} in
      let len = endPos.pos_cnum - startPos.pos_cnum in
      let txt = (String.sub [@doesNotRaise]) src startPos.pos_cnum len in
      stringData := (txt, loc)::(!stringData);
      next endPos scanner
    | _ ->
      next endPos scanner
  in
  next Lexing.dummy_pos scanner;
  let comments =
    !commentData
    |> List.filter (fun c -> not (isReasonDocComment c))
    |> List.rev
  in
  (comments, !stringData)

let parsingEngine = {
  Napkin_driver.parseImplementation = begin fun ~forPrinter:_ ~filename:_ ->
   let magic = Config.ast_impl_magic_number in
    ignore ((really_input_string [@doesNotRaise]) stdin (String.length magic));
    let filename = input_value stdin in
    let (comments, stringData) = extractConcreteSyntax filename in
    let ast = input_value stdin in
    let structure = ast
    |> Napkin_ast_conversion.replaceStringLiteralStructure stringData
    |> Napkin_ast_conversion.normalizeReasonArityStructure ~forPrinter:true
    |> Napkin_ast_conversion.structure
    in {
      Napkin_driver.filename = filename;
      source = "";
      parsetree = structure;
      diagnostics = ();
      invalid = false;
      comments = comments;
    }
  end;
  parseInterface = begin fun  ~forPrinter:_ ~filename:_ ->
    let magic = Config.ast_intf_magic_number in
    ignore ((really_input_string [@doesNotRaise]) stdin (String.length magic));
    let filename = input_value stdin in
    let (comments, stringData) = extractConcreteSyntax filename in
    let ast = input_value stdin in
    let signature = ast
    |> Napkin_ast_conversion.replaceStringLiteralSignature stringData
    |> Napkin_ast_conversion.normalizeReasonAritySignature ~forPrinter:true
    |> Napkin_ast_conversion.signature
    in {
      Napkin_driver.filename;
      source = "";
      parsetree = signature;
      diagnostics = ();
      invalid = false;
      comments = comments;
    }
  end;
  stringOfDiagnostics = begin fun ~source:_ ~filename:_ _diagnostics -> "" end;
}
