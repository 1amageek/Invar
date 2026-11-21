------------------------- MODULE ProjectWorkflow -------------------------
EXTENDS Naturals, FiniteSets
\* WG02/WG06/WG07. Validated current evidence/reviews are inputs to this model.
CONSTANT GateCount
Gates == 1..GateCount
VARIABLES evidence, reviews, cursor, phase, returnTo
vars == <<evidence, reviews, cursor, phase, returnTo>>
Init == /\ evidence \in SUBSET Gates /\ reviews \in SUBSET Gates
        /\ cursor = 0 /\ phase = "running" /\ returnTo = 0
Advance == /\ phase = "running" /\ cursor < GateCount
           /\ cursor + 1 \in evidence /\ cursor + 1 \in reviews
           /\ cursor' = cursor + 1
           /\ phase' = IF cursor' = GateCount THEN "passed" ELSE phase
           /\ UNCHANGED <<evidence, reviews, returnTo>>
Return == /\ phase = "running" /\ cursor < GateCount
          /\ ~(cursor + 1 \in evidence /\ cursor + 1 \in reviews)
          /\ phase' = "incomplete" /\ returnTo' = cursor + 1
          /\ UNCHANGED <<evidence, reviews, cursor>>
Next == Advance \/ Return
Spec == Init /\ [][Next]_vars
NoFalsePass == phase = "passed" => evidence = Gates /\ reviews = Gates
PrefixReviewed == \A gate \in 1..cursor: gate \in evidence /\ gate \in reviews
ReturnToOwner == phase = "incomplete" => returnTo = cursor + 1 /\ returnTo \in Gates
NeverPass == phase # "passed"
============================================================================
