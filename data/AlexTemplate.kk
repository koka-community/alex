// -----------------------------------------------------------------------------
// ALEX TEMPLATE
// -----------------------------------------------------------------------------
// This code is in the PUBLIC DOMAIN; you may copy it freely and use
// it for any purpose whatsoever.

// -----------------------------------------------------------------------------
// Main lexing routines

type alexReturn
  AlexEOF
  AlexError(i: alexInput)
  AlexSkip(i: alexInput, n: int)
  AlexToken(i: alexInput, n: int, a: action) // a is the action type

// alexScan :: AlexInput -> StartCode -> AlexReturn a
fun alexScan(input: alexInput, sc: int): <pure|e> alexReturn
  alexScanUser(Nothing, input, sc)

fun alexScanUser(user: maybe<a>, input: alexInput, sc: int): <pure|e> alexReturn
  match alex_scan_tkn(user, input, 0, input, sc, AlexNone)
    (AlexNone, input__') ->
      match alexGetByte(input)
        Nothing ->
          trace("End of input.")
          AlexEOF
        Just ->
          trace("Error.")
          AlexError(input__')
    (AlexLastSkip(input__'', len), _) ->
      trace("Skipping.") 
      AlexSkip(input__'', len)
    (AlexLastAcc(k, input__''', len), _) ->
      trace("Accept.")
      AlexToken(input__''', len, alex_actions.unsafe-idx(k.ssize_t))

inline extern unsafe-idx( ^v : vector<a>, index : ssize_t ) : total a
  c  "kk_vector_at_borrow"
  cs inline "(#1)[#2]"
  js inline "(#1)[#2]"

// Push the input through the DFA, remembering the most recent accepting
// state it encountered.
fun alex_scan_tkn(user__:maybe<a>, orig_input:alexInput, len:int, input__:alexInput, s: int, last_acc)
  fun check_accs(acc: some<a> alexAcc<a,e>): e alexLastAcc
    match acc
      AlexAccNone -> last_acc
      AlexAcc(a) -> AlexLastAcc(a, input__, len)
      AlexAccSkip -> AlexLastSkip(input__, len)
      AlexAccPred(a, predx, rest)
        -> if predx(user__, orig_input, len, input__) then AlexLastAcc(a, input__, len)
           else check_accs(rest)
      AlexAccSkipPred(predx, rest)
        -> if predx(user__, orig_input, len, input__) then AlexLastSkip(input__, len)
           else check_accs(rest)
  val new_acc = check_accs(alex_accept.unsafe-idx(s.ssize_t))
  match alexGetByte(input__)
     Nothing -> (new_acc, input__)
     Just((c, new_input)) ->
       trace("State: " ++ s.show ++ ", char: " ++ c.show)
       match c.int
        ord_c ->
          val base = alex_base.unsafe-idx(s.ssize_t)
          val offset = base + ord_c
          val check  = alex_check.unsafe-idx(offset.ssize_t)
          val new_s = if offset > 0 && check == ord_c
                          then alex_table.unsafe-idx(offset.ssize_t)
                          else alex_deflt.unsafe-idx(s.ssize_t)
        
          match new_s
              -1 -> (new_acc, input__)
                  // on an error, we want to keep the input *before* the
                  // character that failed, not after.
              _ -> alex_scan_tkn(user__, orig_input, len + 1, new_input, new_s, new_acc)
 

type alexLastAcc
  AlexNone
  AlexLastAcc(i: int, a: alexInput, n: int)
  AlexLastSkip(a: alexInput, n: int)

type alexAcc<u,e>
  AlexAccNone
  AlexAcc(i: int)
  AlexAccSkip
  AlexAccPred(i: int, pred: alexAccPred<u,e>, acc: alexAcc<u,e>)
  AlexAccSkipPred(pred: alexAccPred<u,e>, acc: alexAcc<u,e>)

alias alexAccPred<u,e> = (u, alexInput, int, alexInput) -> e bool;

// -----------------------------------------------------------------------------
// Predicates on a rule

inline fun alexAndPred(p1: alexAccPred<u,e>, p2: alexAccPred<u,e>, user__: u, in1: alexInput, len: int, in2: alexInput): e bool
  p1(user__, in1, len, in2) && p2(user__, in1, len, in2)

// alexPrevCharIsPred :: Char -> AlexAccPred _
inline fun alexPrevCharIs(c: char, _, input__: alexInput, _, _)
  c == alexInputPrevChar(input__)

inline fun alexPrevCharMatches(f: (char) -> pure bool, _, input__: alexInput, _, _)
  f(alexInputPrevChar(input__))

// alexPrevCharIsOneOfPred :: Array Char Bool -> AlexAccPred _
inline fun alexPrevCharIsOneOf(arr: list<char>, _, input__: alexInput, _, _)
  val prev = alexInputPrevChar(input__)
  arr.any(fn(c) c == prev)

// alexRightContext :: Int -> AlexAccPred _
inline fun alexRightContext(sc:int, user__, _, _, input__: alexInput)
  match alex_scan_tkn(user__, input__, 0, input__, sc, AlexNone)
    (AlexNone, _) -> False
    _ -> True
        // TODO: there's no need to find the longest
        // match when checking the right context, just
        // the first match will do.