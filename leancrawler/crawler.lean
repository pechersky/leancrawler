
import meta.expr
import system.io

open tactic declaration environment io io.fs (put_str_ln close)

-- The next instance is there to prevent PyYAML trying to be too smart
meta def my_name_to_string : has_to_string name :=
⟨λ n, "\"" ++ to_string n ++ "\""⟩

local attribute [instance] my_name_to_string

meta def expr.get_pi_app_fn : expr → expr
| (expr.pi _ _ _ e) := e.get_pi_app_fn
| e                 := e.get_app_fn

meta def list_items (e : expr) : list name :=
e.fold [] $ λ e _ cs,
if e.is_constant ∧ ¬ e.const_name ∈ cs
  then e.const_name :: cs
  else cs

meta def mnot : bool → tactic bool := λ p, return (¬ p)

meta def pos_line (p : option pos) : string :=
match p with
| some x := to_string x.line
| _      := ""
end

meta def file_name (p : option string) : string :=
match p with
| some x := x
| _      := "Unknown file"
end

section

structure declaration.modifiers :=
(Class := ff)
(Structure := ff)
(StructureField := ff)
(Inductive := ff)
(Instance := ff)
(IsRecursor := ff)
(IsConstructor := ff)

def bool.to_string_python : has_to_string bool := ⟨λ k, match k with tt := "True" | ff := "False" end⟩
local attribute [instance] bool.to_string_python

instance : has_to_string declaration.modifiers := ⟨λ m,
  "{ class: " ++ to_string m.Class ++
  ", structure: " ++ to_string m.Structure ++
  ", structure_field: " ++ to_string m.StructureField ++
  ", is_recursor: " ++ to_string m.IsRecursor ++
  ", is_constructor: " ++ to_string m.IsConstructor ++
  ", inductive: " ++ to_string m.Inductive ++
  ", instance: " ++ to_string m.Instance ++ " }"⟩

open  tactic declaration environment

meta def declaration.get_kind_string : declaration → string
| (thm _ _ _ _) := "lemma"
| (defn _ _ _ _ _ _) := "definition"
| (cnst _ _ _ _) := "constant"
| (ax _ _ _) := "axiom"


meta def environment.get_modifiers (env : environment) (n : name) : tactic declaration.modifiers :=
do
  c ← (has_attribute `class n >> return tt) <|> return ff,
  i ← (has_attribute `instance n >> return tt) <|> return ff,
  return {
    Class := c,
    Structure := env.is_structure n,
    StructureField := (env.is_projection n).is_some,
    IsConstructor := env.is_constructor n,
    IsRecursor := env.is_recursor n,
    Inductive := env.is_ginductive n,
    Instance := i }
end


meta def print_item_crawl (env : environment) (decl : declaration) : tactic string :=
let name := decl.to_name,
    pos := pos_line (env.decl_pos name),
    fname := file_name (env.decl_olean name) in
do
   let res := "- Name: " ++ to_string name ++ "\n",
   let res := res ++  "  File: " ++ fname ++ "\n",
   let res := res ++  "  Line: " ++ pos ++ "\n",
   let res := res ++  "  Kind: " ++ decl.get_kind_string ++ "\n",
   mods ← env.get_modifiers name,
   let res := res ++  "  Modifiers: " ++ to_string mods ++ "\n",

   pp_type ← pp decl.type,
   let res := res ++  "  Type: " ++ (to_string pp_type).quote ++ "\n",
   type_proofs ← (list_items decl.type).mfilter $ λ c, mk_const c >>= is_proof,
   type_others ← (list_items decl.type).mfilter $ λ c, mk_const c >>= is_proof >>= mnot,
   let res := res ++  "  Type uses proofs: " ++ to_string type_proofs ++ "\n",
   let res := res ++  "  Type uses others: " ++ to_string type_others ++ "\n",

   pp_value ← pp decl.value,
   let res := res ++  "  Value: " ++ (to_string pp_value).quote ++ "\n",
   value_proofs ← (list_items decl.value).mfilter $ λ c, mk_const c >>= is_proof,
   value_others ← (list_items decl.value).mfilter $ λ c, mk_const c >>= is_proof >>= mnot,
   let res := res ++  "  Value uses proofs: " ++ to_string value_proofs ++ "\n",
   let res := res ++  "  Value uses others: " ++ to_string value_others ++ "\n",

   let res := res ++  ("  Target class: " ++ (if mods.Instance then to_string decl.type.get_pi_app_fn else "") ++ "\n"),
   let res := res ++  ("  Parent: " ++  match env.is_projection name with
                           | some info := to_string info.cname ++ "\n"
                           | none :=  "\n"
                           end),
   let res := res ++  ("  Fields: " ++ (to_string $ (env.structure_fields_full name).get_or_else []) ++ "\n"),
   return res


meta def main : tactic unit :=
do curr_env ← get_env,
   h ← unsafe_run_io (mk_file_handle "data.yaml" mode.write),
   let decls := curr_env.fold [] list.cons,
   let filtered_decls := decls.filter
     (λ x, not (to_name x).is_internal),
   filtered_decls.mmap' (λ d,
     do s ← (print_item_crawl curr_env d),
        unsafe_run_io (do io.fs.put_str_ln h s,
                          io.fs.flush h),
        skip),
   unsafe_run_io (close h),
   skip
