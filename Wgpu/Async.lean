
/-! # Async
  Like Task, but `Task.get` is only allowed to be called from IO.
-/

instance : Monad Task where
  pure := Task.pure
  bind := Task.bind

def Result (α : Type) : Type := EStateM.Result IO.Error IO.RealWorld α

def await! (a : Task (Result α)) : IO α := do
  match a.get with
  | .ok a _ => pure a
  | .error e _ => throw e
