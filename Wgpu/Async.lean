
inductive Device

/- # Async
  Like Task, but `Task.get` is only allowed to be called from IO.
-/

/-- TODO: Mark opaque. -/
def A (α : Type) : Type := Task α
instance : Pure A := ⟨Task.pure⟩
instance : Bind A := ⟨Task.bind⟩
instance : Monad A where

def A.fromTask (t : Task α) : A α := t
instance : Coe (Task α) (A α) := ⟨A.fromTask⟩

/-- The *only way* to actually break out of A. -/
def await (a : A α) : IO α := do return Task.get a

def Result (α : Type) : Type := EStateM.Result IO.Error IO.RealWorld α

def await! (a : A (Result α)) : IO α := do
  match <- await a with
  | .ok a _ => pure a
  | .error e _ => throw e
