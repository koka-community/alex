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

effect val alextrace : bool

// alexScan :: AlexInput -> StartCode -> AlexReturn a
fun alexScan(input: alexInput, sc: int): <pure,alextrace%effects|e> alexReturn
  alexScanUser(Nothing, input, sc)

fun atrace(s: string): alextrace ()
  if alextrace then trace(s) else ()

fun alexScanUser(user: maybe<alexUser>, input: alexInput, sc: int): <pure,alextrace%effects|e> alexReturn
  match alex_scan_tkn(user, input, 0, input, sc, AlexNone)
    (AlexNone, input__') ->
      match alexGetByte(input)
        Nothing ->
          atrace("End of input.")
          AlexEOF
        Just ->
          atrace("Error.")
          AlexError(input__')
    (AlexLastSkip(input__'', len), _) ->
      atrace("Skipping.") 
      AlexSkip(input__'', len)
    (AlexLastAcc(k, input__''', len), _) ->
      atrace("Accept.")
      AlexToken(input__''', len, alex_actions.unsafe-idx(k.ssize_t))

// Push the input through the DFA, remembering the most recent accepting
// state it encountered.
fun alex_scan_tkn(user__:maybe<alexUser>, orig_input:alexInput, len:int, input__:alexInput, s: int, last_acc: alexLastAcc): <pure,alextrace%effects|e> (alexLastAcc, alexInput)
  fun check_accs(acc: alexAcc<<alextrace%effects|e>>): <alextrace%effects|e> alexLastAcc
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
       atrace("State: " ++ s.show ++ ", char: " ++ c.show)
       match c.int
        ord_c ->
          val base = alex_base.unsafe-idx(s.ssize_t)
          val offset = base + ord_c
          val check  = alex_check.unsafe-idx(offset.ssize_t)
          val new_s = if offset >= 0 && check == ord_c
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

type alexAcc<e>
  AlexAccNone
  AlexAcc(i: int)
  AlexAccSkip
  AlexAccPred(i: int, pred: alexAccPred<e>, acc: alexAcc<e>)
  AlexAccSkipPred(pred: alexAccPred<e>, acc: alexAcc<e>)

alias alexAccPred<e> = (maybe<alexUser>, alexInput, int, alexInput) -> e bool;

// -----------------------------------------------------------------------------
// Predicates on a rule

inline fun alexAndPred(p1: alexAccPred<e>, p2: alexAccPred<e>, user__: maybe<alexUser>, in1: alexInput, len: int, in2: alexInput): e bool
  p1(user__, in1, len, in2) && p2(user__, in1, len, in2)

// alexPrevCharIsPred :: Char -> AlexAccPred _
inline fun alexPrevCharIs(c: char, _, input__: alexInput, _, _): <pure%effects> bool
  c == alexInputPrevChar(input__)

inline fun alexPrevCharMatches(f: (char) -> pure bool, _, input__: alexInput, _, _): <pure%effects> bool
  f(alexInputPrevChar(input__))

// alexPrevCharIsOneOfPred :: Array Char Bool -> AlexAccPred _
inline fun alexPrevCharIsOneOf(arr: list<char>, _, input__: alexInput, _, _): <pure%effects> bool
  val prev = alexInputPrevChar(input__)
  arr.any(fn(c) c == prev)

// alexRightContext :: Int -> AlexAccPred _
inline fun alexRightContext(sc:int, user__: maybe<alexUser>, _, _, input__: alexInput): <pure%effects,alextrace|e> bool
  match alex_scan_tkn(user__, input__, 0, input__, sc, AlexNone)
    (AlexNone, _) -> False
    _ -> True
        // TODO: there's no need to find the longest
        // match when checking the right context, just
        // the first match will do.