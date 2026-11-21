/- WG02/WG07: a reviewed gate cannot pass from evidence or review alone. -/
namespace ProjectWorkflow
def passes (evidence review : Bool) : Bool := evidence && review
def allPassed (gates : List (Bool × Bool)) : Bool :=
  gates.all fun gate => passes gate.1 gate.2

theorem missingEvidence (review : Bool) : passes false review = false := by
  simp [passes]
theorem missingReview (evidence : Bool) : passes evidence false = false := by
  simp [passes]
theorem passedNeedsBoth (evidence review : Bool) (h : passes evidence review = true) :
    evidence = true ∧ review = true := by
  cases evidence <;> cases review <;> simp_all [passes]
theorem incompletePrefixCannotPass (gate : Bool × Bool) (rest : List (Bool × Bool))
    (h : passes gate.1 gate.2 = false) : allPassed (gate :: rest) = false := by
  simp [allPassed, h]

#print axioms missingEvidence
#print axioms missingReview
#print axioms passedNeedsBoth
#print axioms incompletePrefixCannotPass
end ProjectWorkflow
