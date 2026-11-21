------------------------- MODULE ProjectAction -------------------------
EXTENDS Naturals, FiniteSets
VARIABLES phase, starts, target, published, complete, result
vars == <<phase, starts, target, published, complete, result>>
Init == /\ phase = "ready" /\ starts = 0 /\ target = 1 /\ published = 0
        /\ complete = FALSE /\ result = "none"
Confirm == /\ phase = "ready" /\ phase' = "queued"
           /\ UNCHANGED <<starts, target, published, complete, result>>
Start == /\ phase = "queued" /\ starts' = starts + 1 /\ phase' = "running"
         /\ UNCHANGED <<target, published, complete, result>>
Finish == /\ phase = "running" /\ phase' = "terminal"
          /\ complete' \in BOOLEAN
          /\ result' = IF complete' THEN "passed" ELSE "incomplete"
          /\ UNCHANGED <<starts, target, published>>
Cancel == /\ phase \in {"queued", "running"} /\ phase' = "terminal"
          /\ result' = "cancelled" /\ UNCHANGED <<starts, target, published, complete>>
Publish == /\ phase = "terminal" /\ result \in {"passed", "incomplete"}
           /\ phase' = "published" /\ published' = target
           /\ UNCHANGED <<starts, target, complete, result>>
Replay == UNCHANGED vars
Next == Confirm \/ Start \/ Finish \/ Cancel \/ Publish \/ Replay
Spec == Init /\ [][Next]_vars
AtMostOnce == starts <= 1
OriginalBinding == published = 0 \/ published = target
HonestPass == result = "passed" => complete
=============================================================================
