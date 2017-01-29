(*
 * Copyright (c) 2013-2017 Thomas Gazagnaire <thomas@gazagnaire.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

(** Irmin public API.

    [Irmin] is a library to design and use persistent stores with
    built-in snapshot, branching and reverting mechanisms. Irmin uses
    concepts similar to {{:http://git-scm.com/}Git} but it exposes
    them as a high level library instead of a complex command-line
    frontend. It features a {e bidirectional} Git backend, where an
    application can read and persist its state using the Git format,
    fully-compatible with the usual Git tools and workflows.

    Irmin is designed to use a large variety of backends. It is
    written in pure OCaml and does not depend on external C stubs; it
    is thus very portable and aims to run everywhere, from Linux to
    browser and MirageOS unikernels.

    Consult the {!basics} and {!examples} of use for a quick
    start. See also the {{!Irmin_unix}documentation} for the unix
    backends.

    {e Release %%VERSION%% - %%HOMEPAGE%% }
*)

open Result

val version: string
(** The version of the library. *)

(** {1 Preliminaries} *)

(** Dynamic types for Irmin values. *)
module Type = Depyt

(** Tasks are used to keep track of the origin of write operations in
    the stores. Tasks model the metadata associated with commit
    objects in Git. *)
module Task: sig

  (** {1 Task} *)

  type t
  (** The type for tasks. *)

  val v: date:int64 -> owner:string -> ?uid:int64 -> string -> t
  (** Create a new task. *)

  val date: t -> int64
  (** Get the task date.

      The date provided by the user when calling the
      {{!Task.v}create} function. Rounding [Unix.gettimeofday ()]
      (when available) is a good value for such date. On more esoteric
      platforms, any monotonic counter is a fine value as well. On the
      Git backend, the date is translated into the commit {e Date}
      field and is expected to be the number of POSIX seconds (thus
      not counting leap seconds) since the Epoch. *)

  val owner: t -> string
  (** Get the task owner.

      The owner identifies the entity (human, unikernel, process,
      thread, etc) performing an operation. For the Git backend, this
      will be directly translated into the {e Author} field. *)

  val uid: t -> int64
  (** Get the task unique identifier.

      By default, it is freshly generated on each call to
      {{!Task.v}create}. The identifier is useful for debugging
      purposes, for instance to relate debug lines to the tasks which
      cause them, and might appear in one line of the commit message
      for the Git backend. *)

  val messages: t -> string list
  (** Get the messages associated to the task.

      Text messages can be added to a task either at creation time,
      using {{!Task.v}create}, or can be appended on already
      created tasks using the {{!Task.add}add} function. For
      the Git backend, this will be translated to the commit
      message.  *)

  val add: t -> string -> unit
  (** Add a message to the task messages list. See
      {{!Task.messages}messages} for more details. *)

  val empty: t
  (** The empty task. *)

  (** {1 Task functions} *)

  type 'a f = 'a -> t
  (** Alias for for user-defined task functions. *)

  val none: unit f
  (** The empty task function. [none ()] is [empty] *)

  (** {1 Value Types} *)

  val t: t Type.t
  (** [t] is the value type for {!t}. *)

end

(** [Merge] provides functions to build custom 3-way merge operators
    for various user-defined contents. *)
module Merge: sig

  type conflict = [ `Conflict of string ]
  (** The type for merge errors. *)

  val ok: 'a -> ('a, conflict) result Lwt.t
  (** Return [Ok x]. *)

  val conflict: ('a, unit, string, ('b, conflict) result Lwt.t) format4 -> 'a
  (** Return [Error (Conflict str)]. *)

  (** {1 Merge Combinators} *)

  type 'a promise = unit -> ('a option, conflict) result Lwt.t
  (** An ['a] promise is a function which, when called, will
      eventually return a value type of ['a]. A promise is an
      optional, lazy and non-blocking value. *)

  val promise: 'a -> 'a promise
  (** [promise a] is the promise containing [a]. *)

  val promise_map: ('a -> 'b) -> 'a promise -> 'b promise
  (** [promise_map f a] is the promise containing [f] applied to what
      is promised by [a]. *)

  val promise_bind: 'a promise -> ('a -> 'b promise) -> 'b promise
  (** [promise_bind a f] is the promise returned by [f] applied to
      what is promised by [a]. *)

  type 'a f = old:'a promise -> 'a -> 'a -> ('a, conflict) result Lwt.t
  (** Signature of a merge function. [old] is the value of the
      least-common ancestor.

      {v
              /----> t1 ----\
      ----> old              |--> result
              \----> t2 ----/
      v}
  *)

  type 'a t
  (** The type for merge combinators. *)

  val v: 'a Type.t -> 'a f -> 'a t
  (** [v dt f] create a merge combinator. *)

  val f: 'a t -> 'a f
  (** [f m] is [m]'s merge function. *)

  val seq: 'a t list -> 'a t
  (** Call the merge functions in sequence. Stop as soon as one is {e
      not} returning a conflict. *)

  val like: 'a Type.t -> 'b t -> ('a -> 'b) -> ('b -> 'a) -> 'a t
  (** Use the merge function defined in another domain. If the
      converting functions raise any exception the merge is a
      conflict. *)

  val like_lwt: 'a Type.t -> 'b t -> ('a -> 'b Lwt.t) -> ('b -> 'a Lwt.t) -> 'a t
  (** Same as {{!Merge.biject}biject} but with blocking domain
      converting functions. *)

  (** {1 Basic Merges} *)

  val default: 'a Type.t -> 'a t
  (** Create a default merge function. This is a simple merge
      function which supports changes in one branch at a time:

      {ul
        {- if [t1=t2] then the result of the merge is [`OK t1];}
        {- if [t1=old] then the result of the merge is [`OK t2];}
        {- if [t2=old] then return [`OK t1];}
        {- otherwise the result is [`Conflict].}
      }
  *)

  val unit: unit t
  val bool: bool t
  val char: char t
  val int: int t
  val int32: int32 t
  val int64: int64 t
  val float: float t

  val string: string t
  (** The default string merge function. Do not do anything clever, just
      compare the strings using the [default] merge function. *)

  val option: 'a t -> 'a option t
  (** Lift a merge function to optional values of the same type. If all
      the provided values are inhabited, then call the provided merge
      function, otherwise use the same behavior as {!default}. *)

  val pair: 'a t -> 'b t -> ('a * 'b) t
  (** Lift merge functions to pair of elements. *)

  val triple: 'a t -> 'b t -> 'c t -> ('a * 'b * 'c) t
  (** Lift merge functions to triple of elements. *)

  (** {1 Counters and Multisets} *)

  type counter = int
  (** The type for counter values. It is expected that the only valid
      operations on counters are {e increment} and {e decrement}. The
      following merge functions ensure that the counter semantics are
      preserved: {e i.e.} it ensures that the number of increments and
      decrements is preserved. *)

  val counter: int t
  (** The merge function for mergeable counters. *)

  (** Multi-sets. *)
  module MultiSet (K: sig include Set.OrderedType val t: t Type.t end):
  sig
    val merge: counter Map.Make(K).t t
  end

  (** {1 Maps and Association Lists} *)

  (** We consider the only valid operations for maps and
      association lists to be:

      {ul
      {- Adding a new bindings to the map.}
      {- Removing a binding from the map.}
      {- Replacing an existing binding with a different value.}
      {- {e Trying to add an already existing binding is a no-op}.}
      }

      We thus assume that no operation on maps is modifying the {e
      key} names. So the following merge functions ensures that {e
      (i)} new bindings are preserved {e (ii)} removed bindings stay
      removed and {e (iii)} modified bindings are merged using the
      merge function of values.

      {b Note:} We only consider sets of bindings, instead of
      multisets. Application developers should take care of concurrent
      addition and removal of similar bindings themselves, by using the
      appropriate {{!Merge.MSet}multi-sets}. *)

  module Set (E: sig include Set.OrderedType val t: t Type.t end):
  sig
    val merge: Set.Make(E).t t
  end
  (** Lift merge functions to sets. *)

  val alist: 'a Type.t -> 'b Type.t -> ('a -> 'b option t) -> ('a * 'b) list t
  (** Lift the merge functions to association lists. *)

  (** Lift the merge functions to maps. *)

  module Map (K: sig include Map.OrderedType val t: t Type.t end):
  sig
    val merge: 'a Type.t -> (K.t -> 'a option t) -> 'a Map.Make(K).t t
  end

  (** Useful merge operators.

      [open Irmin.Merge.Infix] at the top of your file to use them. *)
  module Infix: sig

    (** {1 Useful operators} *)

    val (>>|):
      ('a, conflict) result Lwt.t ->
      ('a -> ('b, conflict) result Lwt.t) ->
      ('b, conflict) result Lwt.t
    (** Same as {!bind}. *)

    val (>?|): 'a promise -> ('a -> 'b promise) -> 'b promise
    (** Same as {!promise_bind}. *)

  end

  (** {1 Value Types} *)

  val conflict_t: conflict Type.t
  (** [conflict_t] is the value type for {!conflict}. *)

  val result_t: 'a Type.t -> ('a, conflict) result Type.t
  (** [result_t] is the value type for merge results. *)

end

(** Differences between values. *)
module Diff: sig

  type 'a t = [`Updated of 'a * 'a | `Removed of 'a | `Added of 'a]
  (** The type for representing differences betwen values. *)

  (** {1 Value Types} *)

  val t: 'a Type.t -> 'a t Type.t
  (** [ddiff_t] is the value type for {!diff}. *)

end

(** {1 Stores} *)


type config
(** The type for backend-specific configuration values.

    Every backend has different configuration options, which are kept
    abstract to the user. *)

type task = Task.t
(** The type for user-defined tasks. See {{!Task}Task}. *)

type 'a diff = 'a Diff.t
(** The type for representing differences betwen values. *)

(** An Irmin store is automatically built from a number of lower-level
    stores, implementing fewer operations, such as {{!AO}append-only}
    and {{!RW}read-write} stores. These low-level stores are provided
    by various backends. *)

(** Read-only backend stores. *)
module type RO = sig

  (** {1 Read-only stores} *)

  type t
  (** The type for read-only backend stores. *)

  type key
  (** The type for keys. *)

  type value
  (** The type for raw values. *)

  val mem: t -> key -> bool Lwt.t
  (** [mem t k] is true iff [k] is present in [t]. *)

  val find: t -> key -> value option Lwt.t
  (** [find t k] is [Some v] if [k] is associated to [v] in [t] and
      [None] is [k] is not present in [t]. *)

end

(** Append-only backend store. *)
module type AO = sig

  (** {1 Append-only stores}

      Append-only stores are read-only store where it is also possible
      to add values. Keys are derived from the values raw contents and
      hence are deterministic. *)

  include RO

  val add: t -> value -> key Lwt.t
  (** Write the contents of a value to the store. It's the
      responsibility of the append-only store to generate a
      consistent key. *)

end

(** Immutable Link store. *)
module type LINK = sig

  (** {1 Immutable Link stores}

      The link store contains {i verified} links between low-level
      keys. This is used to certify that a value can be accessed via
      different keys: because they have been obtained using different
      hash functions (SHA1 and SHA256 for instance) or because the
      value might have different but equivalent concrete
      representation (for instance a set might be represented as
      various equivalent trees). *)

  include RO

  val add: t -> key -> value -> unit Lwt.t
  (** [add t src dst] add a link between the key [src] and the value
      [dst]. *)

end

(** Read-write stores. *)
module type RW = sig

  (** {1 Read-write stores}

      Read-write stores read-only stores where it is also possible to
      update and remove elements, with atomically guarantees. *)

  include RO

  val set: t -> key -> value -> unit Lwt.t
  (** [set t k v] replaces the contents of [k] by [v] in [t]. If [k]
      is not already defined in [t], create a fresh binding.  Raise
      [Invalid_argument] if [k] is the {{!Path.empty}empty path}. *)

  val test_and_set:
    t -> key -> test:value option -> set:value option -> bool Lwt.t
  (** [test_and_set t key ~test ~set] sets [key] to [set] only if
      the current value of [key] is [test] and in that case returns
      [true]. If the current value of [key] is different, it returns
      [false]. [None] means that the value does not have to exist or
      is removed.

      {b Note:} The operation is guaranteed to be atomic. *)

  val remove: t -> key -> unit Lwt.t
  (** [remove t k] remove the key [k] in [t]. *)

  val list: t -> key list Lwt.t
  (** [list t] it the list of keys in [t]. [RW] stores are typically
      smaller than [AO] stores, so scanning these is usually cheap. *)

  type watch
  (** The type of watch handlers. *)

  val watch:
    t -> ?init:(key * value) list -> (key -> value diff -> unit Lwt.t) ->
    watch Lwt.t
  (** [watch t ?init f] adds [f] to the list of [t]'s watch handlers
      and returns the watch handler to be used with {!unwatch}. [init]
      is the optional initial values. It is more efficient to use
      {!watch_key} to watch only a single given key.*)

  val watch_key: t -> key -> ?init:value -> (value diff -> unit Lwt.t) ->
    watch Lwt.t
  (** [watch_key t k ?init f] adds [f] to the list of [t]'s watch
      handlers for the key [k] and returns the watch handler to be
      used with {!unwatch}. [init] is the optional initial value of
      the key. *)

  val unwatch: t -> watch -> unit Lwt.t
  (** [unwatch t w] removes [w] from [t]'s watch handlers. *)

end

(** {1 User-Defined Contents} *)

(** Store paths.

    An Irmin {{!Irmin.S}store} binds {{!Path.S.t}paths} to
    user-defined {{!Contents.S}contents}. Paths are composed by basic
    elements, that we call {{!Path.S.step}steps}. The following [Path]
    module provides functions to manipulate steps and paths. *)
module Path: sig

  (** {1 Path} *)

  (** Signature for path implementations.*)
  module type S = sig

    (** {1 Path} *)

    type t
    (** The type for path values. *)

    val pp: t Fmt.t
    (** [pp] is the pretty-printer for paths. *)

    val of_string: string -> [`Error of string | `Ok of t]
    (** [of_string] parses paths. *)

    type step
    (** Type type for path's steps. *)

    val empty: t
    (** The empty path. *)

    val v: step list -> t
    (** Create a path from a list of steps. *)

    val is_empty: t -> bool
    (** Check if the path is empty. *)

    val cons: step -> t -> t
    (** Prepend a step to the path. *)

    val rcons: t -> step -> t
    (** Append a step to the path. *)

    val decons: t -> (step * t) option
    (** Deconstruct the first element of the path. Return [None] if
        the path is empty. *)

    val rdecons: t -> (t * step) option
    (** Deconstruct the last element of the path. Return [None] if the
        path is empty. *)

    val map: t -> (step -> 'a) -> 'a list
    (** [map t f] maps [f] over all steps of [t]. *)

    val pp_step: step Fmt.t
    (** [pp_step] is pretty-printer for path steps. *)

    val step_of_string: string -> [`Ok of step | `Error of string]
    (** [step_of_string] parses path steps. *)

    (** {1 Value Types} *)

    val t: t Type.t
    (** [t] is the value type for {!t}. *)

    val step_t: step Type.t
    (** [step_t] is the value type for {!step}. *)

  end

  module String_list: S with type step = string and type t = string list
  (** An implementation of paths as string lists. *)

end

(** Hashing functions.

    [Hash] provides user-defined hash function to digest serialized
    contents. Some {{!backend}backends} might be parameterized by such
    hash functions, others might work with a fixed one (for instance,
    the Git format use only SHA1).

    An {{!Hash.SHA1}SHA1} implementation is available to pass to the
    backends. *)
module Hash: sig

  (** {1 Contents Hashing} *)

  module type S = sig

    (** Signature for unique identifiers. *)

    type t
    (** The type for digest hashes. *)

    val pp: t Fmt.t
    (** [pp] is the user-facing pretty-printer for paths. *)

    val of_string: string -> [`Error of string | `Ok of t]
    (** [of_string] parses paths. *)

    val digest: Cstruct.t -> t
    (** Compute a deterministic store key from a {!Cstruct.t} value. *)

    val has_kind: [> `SHA1] -> bool
    (** The kind of generated hash. *)

    val to_raw: t -> Cstruct.t
    (** The raw hash value. *)

    val of_raw: Cstruct.t -> t
    (** Abstract a hash value. *)

    val digest_size: int
    (** [digest_size] is the size of hash results, in bytes. *)

    (** {1 Value Types} *)

    val t: t Type.t
    (** [t] is the value type for {!t}. *)

  end
  (** Signature for hash values. *)

  module SHA1: S
  (** SHA1 digests *)

end

(** [Contents] specifies how user-defined contents need to be {e
    serializable} and {e mergeable}.

    The user need to provide:

    {ul
    {- a pair of [to_json] and [of_json] functions, to be used by the
    REST interface.}
    {- a triple of [size_of], [write] and [read] functions, to
    serialize data on disk or to send it over the network.}
    {- a 3-way [merge] function, to handle conflicts between multiple
    versions of the same contents.}
    }

    Default contents for {{!Contents.String}string},
    {{!Contents.Json}JSON} and {{!Contents.Cstruct}C-buffers like}
    values are provided. *)
module Contents: sig

  module type S0 = sig

    (** {Base Contents}

        In Irmin, all the base contents should be serializable in a
        consistent way. To do this, we rely on [depyt]. *)

    type t
    (** The type for contents. *)

    val t: t Type.t
    (** [t] is the value type for {!t}. *)

  end

  (** [Conv] is the signature for contents which can be converted back
      and forth from the command-line.  *)
  module type Conv = sig

    include S0

    val pp: t Fmt.t
    (** [pp] pretty-prints contents. *)

    val of_string: string -> [`Error of string | `Ok of t]
    (** [of_string] parses contents. *)

  end

  (** [Raw] is the signature for contents. *)
  module type Raw = sig

    include Conv

    val raw: t -> Cstruct.t
    (** [raw t] is the raw contents of [t] to be used for computing
        stable digests. *)

  end

  module type S = sig

    (** {1 Signature for store contents} *)

    type t
    (** The type for user-defined contents. *)

    val t: t Type.t
    (** [t] is the value type for {!t}. *)

    val pp: t Fmt.t
    (** [pp] pretty-prints contents. *)

    val of_string: string -> [`Error of string | `Ok of t]
    (** [of_string] parses contents. *)

    val merge: t option Merge.t
    (** Merge function. Evaluates to [`Conflict msg] if the values
        cannot be merged properly. The arguments of the merge function
        can take [None] to mean that the key does not exists for
        either the least-common ancestor or one of the two merging
        points. The merge function returns [None] when the key's value
        should be deleted. *)

  end

  module String: S with type t = string
  (** String values where only the last modified value is kept on
      merge. If the value has been modified concurrently, the [merge]
      function conflicts. *)

  module Cstruct: S with type t = Cstruct.t
  (** Cstruct values where only the last modified value is kept on
      merge. If the value has been modified concurrently, the [merge]
      function conflicts. *)

  (** Contents store. *)
  module type STORE = sig

    include AO

    val merge: t -> key option Merge.t
    (** [merge t] lifts the merge functions defined on contents values
        to contents key. The merge function will: {e (i)} read the
        values associated with the given keys, {e (ii)} use the merge
        function defined on values and {e (iii)} write the resulting
        values into the store to get the resulting key. See
        {!Contents.S.merge}.

        If any of these operations fail, return [`Conflict]. *)

    module Key: Hash.S with type t = key
    (** [Key] provides base functions for user-defined contents keys. *)

    module Val: S with type t = value
    (** [Val] provides base functions for user-defined contents values. *)

  end

  (** [Store] creates a contents store. *)
  module Store (S: sig
      include AO
      module Key: Hash.S with type t = key
      module Val: S with type t = value
    end):
    STORE with type t = S.t
           and type key = S.key
           and type value = S.value

end

(** User-defined branches. *)
module Branch: sig

  (** {1 Branches} *)

  (** The signature for branches. Irmin branches are similar to Git
      branches: they are used to associated user-defined names to head
      commits. Branches havve a default value: the
      {{!Branch.S.master}master} branch. *)
  module type S = sig

    (** {1 Signature for Branches} *)

    type t
    (** The type for branches. *)

    val t: t Type.t
    (** [t] is the value type for {!t}. *)

    val pp: t Fmt.t
    (** [pp] pretty-prints branches. *)

    val of_string: string -> [`Error of string | `Ok of t ]
    (** [of_string] parses branch names. *)

    val master: t
    (** The name of the master branch. *)

    val is_valid: t -> bool
    (** Check if the branch is valid. *)

  end

  module String: S with type t = string
  (** [String] is an implementation of {{!Branch.S}S} where branches
      are strings. The [master] branch is ["master"]. Valid branch
      names contain only alpha-numeric characters, [-], [_], [.], and
      [/]. *)

  (** [STORE] specifies the signature for branch stores.

      A {i branch store} is a mutable and reactive key / value store,
      where keys are branch names created by users and values are keys
      are head commmits. *)
  module type STORE = sig

    (** {1 Reference Store} *)

    include RW

    val list: t -> key list Lwt.t
    (** [list t] list all the branches present in [t]. *)

    module Key: S with type t = key
    (** Base functions on keys. *)

    module Val: Hash.S with type t = value
    (** Base functions on values. *)

  end

end

(** [Metadata] defines metadata that is attached to contents but stored in
    nodes. The Git backend uses this to indicate the type of file (normal,
    executable or symlink). *)
module Metadata: sig

  module type S = sig

    type t
    (** The type for metadata. *)

    val t: t Type.t
    (** [t] is the value type for {!t}. *)

    val merge: t Merge.t
    (** [merge] is the merge function for metadata. *)

    val default: t
    (** The default metadata to attach, for APIs that don't
        care about metadata. *)

  end

  module None: S with type t = unit
  (** A metadata definition for systems that don't use metadata. *)

end

(** [Private] defines functions only useful for creating new
    backends. If you are just using the library (and not developing a
    new backend), you should not use this module. *)
module Private: sig

  (** Backend configuration.

    A backend configuration is a set of {{!keys}keys} mapping to
    typed values. Backends define their own keys. *)
  module Conf: sig

    (** {1 Configuration converters}

        A configuration converter transforms a string value to an OCaml
        value and vice-versa. There are a few
        {{!builtin_converters}built-in converters}. *)

    type 'a parser = string -> [ `Error of string | `Ok of 'a ]
    (** The type for configuration converter parsers. *)

    type 'a printer = 'a Fmt.t
    (** The type for configuration converter printers. *)

    type 'a converter = 'a parser * 'a printer
    (** The type for configuration converters. *)

    val parser: 'a converter -> 'a parser
    (** [parser c] is [c]'s parser. *)

    val printer: 'a converter -> 'a printer
    (** [converter c] is [c]'s printer. *)

    (** {1:keys Keys} *)

    type 'a key
    (** The type for configuration keys whose lookup value is ['a]. *)

    val key: ?docs:string -> ?docv:string -> ?doc:string ->
      string -> 'a converter -> 'a -> 'a key
    (** [key ~docs ~docv ~doc name conv default] is a configuration key named
        [name] that maps to value [default] by default. [conv] is
        used to convert key values provided by end users.

        [docs] is the title of a documentation section under which the
        key is documented. [doc] is a short documentation string for the
        key, this should be a single sentence or paragraph starting with
        a capital letter and ending with a dot.  [docv] is a
        meta-variable for representing the values of the key
        (e.g. ["BOOL"] for a boolean).

        @raise Invalid_argument if the key name is not made of a
        sequence of ASCII lowercase letter, digit, dash or underscore.
        FIXME not implemented.

        {b Warning.} No two keys should share the same [name] as this
        may lead to difficulties in the UI. *)

    val name: 'a key -> string
    (** The key name. *)

    val conv: 'a key -> 'a converter
    (** [tc k] is [k]'s converter. *)

    val default: 'a key -> 'a
    (** [default k] is [k]'s default value. *)

    val doc: 'a key -> string option
    (** [doc k] is [k]'s documentation string (if any). *)

    val docv: 'a key -> string option
    (** [docv k] is [k]'s value documentation meta-variable (if any). *)

    val docs: 'a key -> string option
    (** [docs k] is [k]'s documentation section (if any). *)

    val root: string option key
    (** Default [--root=ROOT] argument. *)

    (** {1:conf Configurations} *)

    type t = config
    (** The type for configurations. *)

    val empty: t
    (** [empty] is the empty configuration. *)

    val singleton: 'a key -> 'a -> t
    (** [singleton k v] is the configuration where [k] maps to [v]. *)

    val is_empty: t -> bool
    (** [is_empty c] is [true] iff [c] is empty. *)

    val mem: t -> 'a key -> bool
    (** [mem c k] is [true] iff [k] has a mapping in [c]. *)

    val add: t -> 'a key -> 'a -> t
    (** [add c k v] is [c] with [k] mapping to [v]. *)

    val rem: t -> 'a key -> t
    (** [rem c k] is [c] with [k] unbound. *)

    val union: t -> t -> t
    (** [union r s] is the union of the configurations [r] and [s]. *)

    val find: t -> 'a key -> 'a option
    (** [find c k] is [k]'s mapping in [c], if any. *)

    val get: t -> 'a key -> 'a
    (** [get c k] is [k]'s mapping in [c].

        {b Raises.} [Not_found] if [k] is not bound in [d]. *)

    (** {1:builtin_converters Built-in value converters}  *)

    val bool: bool converter
    (** [bool] converts values with [bool_of_string].  *)

    val int: int converter
    (** [int] converts values with [int_of_string]. *)

    val string: string converter
    (** [string] converts values with the identity function. *)

    val uri: Uri.t converter
    (** [uri] converts values with {!Uri.of_string}. *)

    val some: 'a converter -> 'a option converter
    (** [string] converts values with the identity function. *)

  end

  (** [Watch] provides helpers to register event notifications on
      read-write stores. *)
  module Watch: sig

    (** {1 Watch Helpers} *)

    (** The signature for watch helpers. *)
    module type S = sig

      (** {1 Watch Helpers} *)

      type key
      (** The type for store keys. *)

      type value
      (** The type for store values. *)

      type watch
      (** The type for watch handlers. *)

      type t
      (** The type for watch state. *)

      val stats: t -> int * int
      (** [stats t] is a tuple [(k,a)] represeting watch stats. [k] is
          the number of single key watchers for the store [t] and [a] the
          number of global watchers for [t]. *)

      val notify: t -> key -> value option -> unit Lwt.t
      (** Notify all listeners in the given watch state that a key has
          changed, with the new value associated to this key. [None]
          means the key has been removed. *)

      val v: unit -> t
      (** Create a watch state. *)

      val clear: t -> unit Lwt.t
      (** Clear all register listeners in the given watch state. *)

      val watch_key: t -> key -> ?init:value -> (value diff -> unit Lwt.t) ->
        watch Lwt.t
      (** Watch a given key for changes. More efficient than {!watch}. *)

      val watch: t -> ?init:(key * value) list ->
        (key -> value diff -> unit Lwt.t) -> watch Lwt.t
      (** Add a watch handler. To watch a specific key, use
          {!watch_key} which is more efficient. *)

      val unwatch: t -> watch -> unit Lwt.t
      (** Remove a watch handler. *)

      val listen_dir: t -> string
        -> key:(string -> key option)
        -> value:(key -> value option Lwt.t)
        -> (unit -> unit Lwt.t) Lwt.t
      (** Register a thread looking for changes in the given directory
          and return a function to stop watching and free up
          resources. *)

    end

    val workers: unit -> int
    (** [workers ()] is the number of background worker threads
        managing event notification currently active. *)

    type hook = int -> string -> (string -> unit Lwt.t) -> (unit -> unit Lwt.t) Lwt.t
    (** The type for watch hooks. *)

    val none: hook
    (** [none] is the hooks which asserts false. *)

    val set_listen_dir_hook: hook -> unit
    (** Register a function which looks for file changes in a
        directory and return a function to stop watching. It is
        probably best to use {!Irmin_watcher.hook} there. By default,
        it uses {!none}. *)

    (** [Make] builds an implementation of watch helpers. *)
    module Make(K: Contents.S0) (V: Contents.S0):
      S with type key = K.t and type value = V.t

  end

  module Lock: sig
    (** {1 Process locking helpers} *)

    module type S = sig

      type t
      (** The type for lock manager. *)

      type key
      (** The type for key to be locked. *)

      val v: unit -> t
      (** Create a lock manager. *)

      val with_lock: t -> key -> (unit -> 'a Lwt.t) -> 'a Lwt.t
      (** [with_lock t k f] executes [f ()] while holding the exclusive
          lock associated to the key [k]. *)

    end

    module Make (K: Contents.S0): S with type key = K.t
    (** Create a lock manager implementation. *)

  end

  (** [Node] provides functions to describe the graph-like structured
      values.

      The node blocks form a labeled directed acyclic graph, labeled
      by {{!Path.S.step}steps}: a list of steps defines a
      unique path from one node to an other.

      Each node can point to user-defined {{!Contents.S}contents}
      values. *)
  module Node: sig

    module type S = sig

      (** {1 Node values} *)

      type t
      (** The type for node values. *)

      type metadata
      (** The type for node metadata. *)

      type contents
      (** The type for contents keys. *)

      type node
      (** The type for node keys. *)

      type step
      (** The type for steps between nodes. *)

      type value = [`Node of node | `Contents of contents * metadata ]
      (** The type for either node keys or contents keys combined with
          their metadata. *)

      val v: (step * value) list -> t
      (** [create l] is a new node. *)

      val list: t -> (step * value) list
      (** [list t] is the contents of [t]. *)

      val empty: t
      (** [empty] is the empty node. *)

      val is_empty: t -> bool
      (** [is_empty t] is true iff [t] is {!empty}. *)

      val find: t -> step -> value option
      (** [find t s] is the value associated with [s] in [t].

          A node can point to user-defined
          {{!Node.S.contents}contents}. The edge between the node and
          the contents is labeled by a {{!Node.S.step}step}. *)

      val update: t -> step -> value -> t
      (** [update t s v] is [t]s where [find t v] is [Some s]. *)

      val remove: t -> step -> t
      (** [remove t s] is [t] where [find t v] is [None]. *)

      (** {1 Value types} *)

      val t: t Type.t
      (** [t] is the value type for {!t}. *)

      val metadata_t: metadata Type.t
      (** [metadata_t] is the value type for {!metadata}. *)

      val contents_t: contents Type.t
      (** [contents_t] is the value type for {!contents}. *)

      val node_t: node Type.t
      (** [node_t] is the value type for {!node}. *)

      val step_t: step Type.t
      (** [step_t] is the value type for {!step}. *)

      val value_t: value Type.t
      (** [value_t] is the value type for {!value}. *)

    end

    (** [Node] provides a simple node implementation, parameterized by
        the contents [C], node [N], paths [P] and metadata [M]. *)
    module Make (C: Contents.S0) (N: Contents.S0) (P: Path.S) (M: Metadata.S):
      S with type contents = C.t
         and type node = N.t
         and type step = P.step
         and type metadata = M.t

    (** [STORE] specifies the signature for node stores. *)
    module type STORE = sig

      include AO

      module Path: Path.S
      (** [Path] provides base functions on node paths. *)

      val merge: t -> key option Merge.t
      (** [merge] is the 3-way merge function for nodes keys. *)

      module Key: Hash.S with type t = key
      (** [Key] provides base functions for node keys. *)

      module Metadata: Metadata.S
      (** [Metadata] provides base functions for node metadata. *)

      (** [Val] provides base functions for node values. *)
      module Val: S with type t = value
                     and type node = key
                     and type metadata = Metadata.t
                     and type step = Path.step

      (** [Contents] is the underlying contents store. *)
      module Contents: Contents.STORE with type key = Val.contents
    end

    (** [Store] creates node stores. *)
    module Store
        (C: Contents.STORE)
        (P: Path.S)
        (M: Metadata.S)
        (S: sig
           include AO
           module Key: Hash.S with type t = key
           module Val: S with type t = value
                          and type node = key
                          and type metadata = M.t
                          and type contents = C.key
                          and type step = P.step
         end):
      STORE with type t = C.t * S.t
             and type key = S.key
             and type value = S.value
             and module Path = P
             and module Metadata = M
             and module Key = S.Key
             and module Val = S.Val


    (** [Graph] specifies the signature for node graphs. A node graph
        is a deterministic DAG, labeled by steps. *)
    module type GRAPH = sig

      (** {1 Node Graphs} *)

      type t
      (** The type for store handles. *)

      type metadata
      (** The type for node metadata. *)

      type contents
      (** The type of user-defined contents. *)

      type node
      (** The type for node values. *)

      type step
      (** The type of steps. A step is used to pass from one node to
          another. *)

      type path
      (** The type of store paths. A path is composed of
          {{!step}steps}. *)

      type value = [ `Node of node | `Contents of contents * metadata ]
      (** The type for store values. *)

      val empty: t -> node Lwt.t
      (** The empty node. *)

      val v: t -> (step * value) list -> node Lwt.t
      (** [v t n] is a new node containing [n]. *)

      val list: t -> node -> (step * value) list Lwt.t
      (** [list t n] is the contents of the node [n]. *)

      val find: t -> node -> path -> value option Lwt.t
      (** [find t n p] is the contents of the path [p] starting form
          [n]. *)

      val update: t -> node -> path -> value -> node Lwt.t
      (** [update t n p v] is the node [x] such that [find t x p] is
          [Some v] and it behaves the same [n] for other
          operations. *)

      val remove: t -> node -> path -> node Lwt.t
      (** [remove t n path] is the node [x] such that [find t x] is
          [None] and it behhaves then same as [n] for other
          operations. *)

      val closure: t -> min:node list -> max:node list -> node list Lwt.t
      (** [closure t ~min ~max] is the transitive closure [c] of [t]'s
          nodes such that:

          {ul
          {- There is a path in [t] from any nodes in [min] to nodes
          in [c]. If [min] is empty, that condition is always true.}
          {- There is a path in [t] from any nodes in [c] to nodes in
          [max]. If [max] is empty, that condition is always false.}
          }

          {B Note:} Both [min] and [max] are subsets of [c].*)

      (** {1 Value Types} *)

      val metadata_t: metadata Type.t
      (** [metadat_t] is the value type for {!metadata}. *)

      val contents_t: contents Type.t
      (** [contents_t] is the value type for {!contents}. *)

      val node_t: node Type.t
      (** [node_t] is the value type for {!node}. *)

      val step_t: step Type.t
      (** [step_t] is the value type for {!step}. *)

      val path_t: path Type.t
      (** [path_t] is the value type for {!path}. *)

      val value_t: value Type.t
      (** [value_t] is the value type for {!value}. *)

    end

    module Graph (S: STORE): GRAPH
      with type t = S.t
       and type contents = S.Contents.key
       and type metadata = S.Val.metadata
       and type node = S.key
       and type path = S.Path.t
       and type step = S.Path.step

  end

  (** Commit values represent the store history.

      Every commit contains a list of predecessor commits, and the
      collection of commits form an acyclic directed graph.

      Every commit also can contain an optional key, pointing to a
      {{!Private.Commit.STORE}node} value. See the
      {{!Private.Node.STORE}Node} signature for more details on node
      values. *)
  module Commit: sig

    module type S = sig

      (** {1 Commit values} *)

      type t
      (** The type for commit values. *)

      type commit
      (** Type for commit keys. *)

      type node
      (** Type for node keys. *)

      val v: task -> node:node -> parents:commit list -> t
      (** Create a commit. *)

      val node: t -> node
      (** The underlying node. *)

      val parents: t -> commit list
      (** The commit parents. *)

      val task: t -> task
      (** The commit provenance. *)

      (** {1 Value Types} *)

      val t: t Type.t
      (** [t] is the value type for {!t}. *)

      val commit_t: commit Type.t
      (** [commit_t] is the value type for {!commit}. *)

      val node_t: node Type.t
      (** [node_t] is the value type for {!node}. *)

    end

    (** [Make] provides a simple implementation of commit values,
        parameterized by the commit [C] and node [N]. *)
    module Make (C: Contents.S0) (N: Contents.S0):
      S with type commit = C.t and type node = N.t

    (** [STORE] specifies the signature for commit stores. *)
    module type STORE = sig

      (** {1 Commit Store} *)

      include AO

      val merge: t -> task:task -> key option Merge.t
      (** [merge] is the 3-way merge function for commit keys. *)

      module Key: Hash.S with type t = key
      (** [Key] provides base functions for commit keys. *)

      (** [Val] provides functions for commit values. *)
      module Val: S with type t = value and type commit = key

      (** [Node] is the underlying node store. *)
      module Node: Node.STORE with type key = Val.node

    end

    (** [Store] creates a new commit store. *)
    module Store
        (N: Node.STORE)
        (S: sig
           include AO
           module Key: Hash.S with type t = key
           module Val: S with type t = value
                          and type commit = key
                          and type node = N.key
         end):
      STORE with type t = N.t * S.t
             and type key = S.key
             and type value = S.value
             and module Key = S.Key
             and module Val = S.Val

    (** [History] specifies the signature for commit history. The
        history is represented as a partial-order of commits and basic
        functions to search through that history are provided.

        Every commit can point to an entry point in a node graph, where
        user-defined contents are stored. *)
    module type HISTORY = sig

      (** {1 Commit History} *)

      type t
      (** The type for store handles. *)

      type node
      (** The type for node values. *)

      type commit
      (** The type for commit values. *)

      val v: t -> node:node -> parents:commit list -> task:task -> commit Lwt.t
      (** Create a new commit. *)

      val node: t -> commit -> node option Lwt.t
      (** [node t c] is [c]'s commit node or [None] is [c] is not
          present in [t].

          A commit might contain a graph
          {{!Private.Node.GRAPH.node}node}. *)

      val parents: t -> commit -> commit list Lwt.t
      (** Get the commit parents.

          Commits form a append-only, fully functional, partial-order
          data-structure: every commit carries the list of its
          immediate predecessors. *)

      val merge: t -> task:task -> commit Merge.t
      (** [merge t] is the 3-way merge function for commit.  *)

      val lcas: t -> ?max_depth:int -> ?n:int -> commit -> commit ->
        [`Ok of commit list | `Max_depth_reached | `Too_many_lcas ] Lwt.t
      (** Find the lowest common ancestors
          {{:http://en.wikipedia.org/wiki/Lowest_common_ancestor}lca}
          between two commits. *)

      val lca: t -> task:task -> ?max_depth:int -> ?n:int -> commit list ->
        (commit option, Merge.conflict) result Lwt.t
      (** Compute the lowest common ancestors ancestor of a list of
          commits by recursively calling {!lcas} and merging the
          results.

          If one of the merges results in a conflict, or if a call to
          {!lcas} returns either [`Max_depth_reached] or
          [`Too_many_lcas] then the function returns [None]. *)

      val three_way_merge:
        t -> task:task -> ?max_depth:int -> ?n:int -> commit -> commit ->
        (commit, Merge.conflict) result Lwt.t
      (** Compute the {!lcas} of the two commit and 3-way merge the
          result. *)

      val closure: t -> min:commit list -> max:commit list -> commit list Lwt.t
      (** Same as {{!Private.Node.GRAPH.closure}GRAPH.closure} but for
          the history graph. *)

      (** {1 Value Types} *)

      val node_t: node Type.t
      (** [node_t] is the value type for {!node}. *)

      val commit_t: commit Type.t
      (** [commit_t] is the value type for {!commit}. *)

    end

    (** Build a commit history. *)
    module History (S: STORE): HISTORY
      with type t = S.t
       and type node = S.Node.key
       and type commit = S.key

  end

  (** The signature for slices. *)
  module Slice: sig

    module type S = sig

      (** {1 Slices} *)

      type t
      (** The type for slices. *)

      type contents
      (** The type for exported contents. *)

      type node
      (** The type for exported nodes. *)

      type commit
      (** The type for exported commits. *)

      type value = [ `Contents of contents | `Node of node | `Commit of commit ]
      (** The type for exported values. *)

      val empty: unit -> t Lwt.t
      (** Create a new empty slice. *)

      val add: t -> value -> unit Lwt.t
      (** [add t v] adds [v] to [t]. *)

      val iter: t -> (value -> unit Lwt.t) -> unit Lwt.t
      (** [iter t f] calls [f] on all values of [t]. *)

      (** {1 Value Types} *)

      val t: t Type.t
      (** [t] is the value type for {!t}. *)

      val contents_t: contents Type.t
      (** [content_t] is the value type for {!contents}. *)

      val node_t: node Type.t
      (** [node_t] is the value type for {!node}. *)

      val commit_t: commit Type.t
      (** [commit_t] is the value type for {!commit}. *)

      val value_t: value Type.t
      (** [value_t] is the value type for {!value}. *)

    end

    (** Build simple slices. *)
    module Make (C: Contents.STORE) (N: Node.STORE) (H: Commit.STORE):
      S with type contents = C.key * C.value
         and type node = N.key * N.value
         and type commit = H.key * H.value

  end

  module Sync: sig

    module type S = sig

      (** {1 Remote synchronization} *)

      type t
      (** The type for store handles. *)

      type commit
      (** The type for store heads. *)

      type branch
      (** The type for branch IDs. *)

      val fetch: t -> ?depth:int -> uri:string -> branch ->
        [`Head of commit | `No_head | `Error] Lwt.t
      (** [fetch t uri] fetches the contents of the remote store
          located at [uri] into the local store [t]. Return the head
          of the remote branch with the same name, which is now in the
          local store. [No_head] means no such branch exists. *)

      val push: t -> ?depth:int -> uri:string -> branch -> [`Ok | `Error] Lwt.t
      (** [push t uri] pushes the contents of the local store [t] into
          the remote store located at [uri]. *)

    end

    (** [None] is an implementation of {{!Private.Sync.S}S} which does
        nothing. *)
    module None (H: Contents.S0) (B: Contents.S0): sig
      include S with type commit = H.t and type branch = B.t

      val v: 'a -> t Lwt.t
      (** Create a remote store handle. *)
    end

  end

  (** The complete collection of private implementations. *)
  module type S = sig

    (** {1 Private Implementations} *)

    (** Private content store. *)
    module Contents: Contents.STORE

    (** Private nod store. *)
    module Node: Node.STORE with type Val.contents = Contents.key

    (** Private commit store. *)
    module Commit: Commit.STORE with type Val.node = Node.key

    (** Private branch store. *)
    module Branch: Branch.STORE with type value = Commit.key

    (** Private slices. *)
    module Slice: Slice.S
      with type contents = Contents.key * Contents.value
       and type node = Node.key * Node.value
       and type commit = Commit.key * Commit.value

    (** Private repositories. *)
    module Repo: sig
      type t
      val v: config -> t Lwt.t
      val contents_t: t -> Contents.t
      val node_t: t -> Node.t
      val commit_t: t -> Commit.t
      val branch_t: t -> Branch.t
    end

    (** URI-based low-level sync. *)
    module Sync: sig
      include Sync.S with type commit = Commit.key and type branch = Branch.key
      val v: Repo.t -> t Lwt.t
    end

  end

end

(** {1 High-level Stores}

    An Irmin store is a branch-consistent store where keys are lists
    of steps.

    An example is a Git repository where keys are filenames, {e i.e.}
    list of ['/']-separated strings. More complex examples are
    structured values, where steps might contain first-class field
    accessors and array offsets.

    Irmin provides the following features:

    {ul
    {- Support for fast clones, branches and merges, in a fashion very
       similar to Git.}
    {- Efficient taging areas for fast, transient, in-memory operations.}
    {- Fast {{!Sync}synchronization} primitives between remote
       stores, using native backend protocols (as the Git protocol)
       when available.}
    }
*)

(** Irmin stores. *)
module type S = sig

  (** {1 IrminSstores}

      Irmin stores are tree-like read-write stores with
      extended capabilities. They allow an application (or a
      collection of applications) to work with multiple local states,
      which can be forked and merged programmatically, without having
      to rely on a global state. In a way very similar to version
      control systems, Irmin local states are called {i branches}.

      There are two kinds of store in Irmin: the ones based on
      {{!persistent}persistent} named branches and the ones based
      {{!temporary}temporary} detached heads. These exist relative to a
      local, larger (and shared) store, and have some (shared)
      contents. This is exactly the same as usual version control
      systems, that the informed user can see as an implicit purely
      functional data-structure. *)

  type t
  (** The type for branch-consistent stores. *)

  type step
  (** The type for {!key} steps. *)

  type key
  (** The type for store keys. A key is a sequence of {!step}s. *)

  type metadata
  (** The type for store metadata. *)

  type contents
  (** The type for store contents. *)

  type node
  (** The type for store nodes. *)

  type tree = [ `Empty | `Node of node | `Contents of contents * metadata ]
  (** The type for store trees. *)

  type commit
  (** Type for commit identifiers. Similar to Git's commit SHA1s. *)

  type branch
  (** Type for persistent branch names. Branches usually share a
      common global namespace and it's the user's responsibility to
      avoid name clashes. *)

  type slice
  (** Type for store slices. *)

  (** Repositories. *)
  module Repo: sig

    (** {1 Repositories}

        A repository contains a set of branches. *)

    type t
    (** The type of repository handles. *)

    val v: config -> t Lwt.t
    (** [v mk_task config] connects to a repository in a
        backend-specific manner. *)

    val heads: t -> commit list Lwt.t
    (** [heads] is {!Head.list}. *)

    val branches: t -> branch list Lwt.t
    (** [branches] is {Branch.list}. *)

    val export: ?full:bool -> ?depth:int ->
      ?min:commit list -> ?max:commit list ->
      t -> slice Lwt.t
    (** [export t ~depth ~min ~max] exports the store slice between
        [min] and [max], using at most [depth] history depth (starting
        from the max).

        If [max] is not specified, use the current [heads]. If [min] is
        not specified, use an unbound past (but can still be limited by
        [depth]).

        [depth] is used to limit the depth of the commit history. [None]
        here means no limitation.

        If [full] is set (default is true), the full graph, including the
        commits, nodes and contents, is exported, otherwise it is the
        commit history graph only. *)

    val import: t -> slice -> [`Ok | `Error] Lwt.t
    (** [import t s] imports the contents of the slice [s] in [t]. Does
        not modify branches. *)

    val task_of_commit: t -> commit -> task option Lwt.t
    (** [task_of_commit t c] is the description of the commit
        [c]. Useful to retrieve the commit date and the committer
        name. Return [None] if [c] is not present in [t]. *)

  end

  val empty: Repo.t -> t Lwt.t
  (** [empty repo task] is a temporary, empty store. Becomes a
      normal temporary store after the first update. *)

  val master: Repo.t -> t Lwt.t
  (** [master repo] is a persistent store based on [r]'s master
      branch. This operation is cheap, can be repeated multiple
      times. *)

  val of_branch: Repo.t -> branch -> t Lwt.t
  (** [of_branch r name] is a persistent store based on the branch
      [name]. Similar to [master], but use [name] instead
      {!Branch.S.master}. *)

  val of_commit: Repo.t -> commit -> t Lwt.t
  (** [of_commit r c] is a temporary store, based on the commit
      [c].

      Temporary stores do not have stable names: instead they can be
      addressed using the hash of the current commit. Temporary stores
      are similar to Git's detached heads. In a temporary store, all
      the operations are performed relative to the current head and
      update operations can modify the current head: the current
      stores's head will automatically become the new head obtained
      after performing the update. *)

  val repo: t -> Repo.t
  (** [repo t] is the repository containing [t]. *)

  val tree: t -> tree Lwt.t
  (** [tree t] is [t]'s current tree. Contents is not allowed at the
      root of the tree. *)

  val status: t -> [ `Empty | `Branch of branch | `Commit of commit ]
  (** [status t] is [t]'s status. It can either be a branch, a commit
      or empty. *)

  (** Managing the store's heads. *)
  module Head: sig

    val v: Repo.t -> task -> parents:commit list -> tree -> commit Lwt.t
    (** [v r task ~parents:p t] is the commit [c] such that:
        {ul
        {- [Repo.task_of_commit r c = task]}
        {- [parents (of_commit r c) = p]}
        {- [tree (of_commit r c) = t]}}
    *)

    val list: Repo.t -> commit list Lwt.t
    (** [list t] is the list of all the heads in local store. Similar
        to [git rev-list --all]. *)

    val find: t -> commit option Lwt.t
    (** [find t] is the current head of the store [t]. This works for
        both persistent and temporary branches. In the case of a
        persistent branch, this involves getting the the head
        associated with the branch, so this may block. In the case of
        a temporary store, it simply returns the current head. Returns
        [None] if the store has no contents. Similar to [git rev-parse
        HEAD]. *)

    val get: t -> commit Lwt.t
    (** Same as {!find} but raise [Invalid_argument] if the store does
        not have any contents. *)

    val set: t -> commit -> unit Lwt.t
    (** [set t h] updates [t]'s contents with the contents of the
        commit [h]. Can cause data loss as it discards the current
        contents. Similar to [git reset --hard <hash>]. *)

    val fast_forward: t -> ?max_depth:int -> ?n:int -> commit -> bool Lwt.t
    (** [fast_forward t h] is similar to {!update} but the [t]'s head
        is updated to [h] only if [h] is stricly in the future of
        [t]'s current head. Return [false] if it is not the case. If
        present, [max_depth] or [n] are used to limit the search space
        of the lowest common ancestors (see {!lcas}). *)

    val test_and_set:
      t -> test:commit option -> set:commit option -> bool Lwt.t
    (** Same as {!update_head} but check that the value is [test] before
        updating to [set]. Use {!update} or {!merge} instead if
        possible. *)

    (** [merge ~into:t ?max_head ?n commit] merges the contents of the
        commit associated to [commit] into [t]. [max_depth] is the
        maximal depth used for getting the lowest common ancestor. [n]
        is the maximum number of lowest common ancestors. If present,
        [max_depth] or [n] are used to limit the search space of the
        lowest common ancestors (see {!lcas}). *)
    val merge: into:t -> task -> ?max_depth:int -> ?n:int -> commit ->
      (unit, Merge.conflict) result Lwt.t

    val parents: t -> commit list Lwt.t
    (** [parents t] are [t]'s parent commits.  *)

  end

  (** Managing store's trees. *)

  module Tree: sig
    (** [Tree] provides in-memory partial mirror of the store, with
        lazy reads and delayed writes.

        Trees are like staging area in Git: they are temporary
        non-persistent areas (they disappear if the host crash), held
        in memory for efficiency, where reads are done lazily and
        writes are done only when needed on commit: if you modify a
        key twice, only the last change will be written to the store
        when you commit.  *)

    (** {1 Constructors} *)

    val empty: tree
    (** [empty] is the empty tree. Empty trees do not have associated
        backend configuration values, as they can perform in-memory
        operation, independently of any given backend.

        {i Note}: there is another way to obtain an empty tree using
        [`Node h] where [h] is the hash of the empty tree for the
        current repository. Don't use [(=) `Empty] to check for tree
        tree emptiness, unless you really know what you are doing.  *)

    val of_contents: ?metadata:metadata -> contents -> tree
    (** [of_contents c] is the sub-tree built from the contents
        [c]. *)

    val of_node: node -> tree
    (** [of_node n] is the sub-tree built from the node [n]. *)

    val kind: tree -> key -> [`Contents | `Node | `Empty] Lwt.t
    (** [kind t k] is the type of [s] in [t]. It could either be a
        tree node or some file contents. It is [`Empty] if [k] is not
        present in [t]. *)

    val list: tree -> key -> (step * [`Contents | `Node]) list Lwt.t
    (** [list t key] is the list of files and sub-nodes stored under [k]
        in [t]. *)

    (** {1 Diffs} *)

    val diff: tree -> tree -> (key * (contents * metadata) diff) list Lwt.t
    (** [diff x y] is the difference of contents between [x] and [y]. *)

    (** {1 Manipulating Contents} *)

    val mem: tree -> key -> bool Lwt.t
    (** [mem t k] is true iff [k] is associated to some contents in
        [t]. *)

    val findm: tree -> key -> (contents * metadata) option Lwt.t
    (** [find t k] is [Some (b, m)] if [k] is associated to the contents
        [b] and metadata [m] in [t] and [None] if [k] is not present in
        [t]. *)

    val find: tree -> key -> contents option Lwt.t
    (** [find] is similar to {!find} but it discards metadata. *)

    val getm: tree -> key -> (contents * metadata) Lwt.t
    (** Same as {!find} but raise [Invalid_arg] if [k] is not present
        in [t]. *)

    val get: tree -> key -> contents Lwt.t
    (** Same as {!get} but ignore the metadata. *)

    val add: tree -> key -> ?metadata:metadata -> contents -> tree Lwt.t
    (** [add t k c] is [t] where the key [k] is bound to the contents
        [c]. *)

    val remove: tree -> key -> tree Lwt.t
    (** [remove t k] is [t] where [k] bindings has been removed. *)

    (** {1 Manipulating Subtrees} *)

    val memv: tree -> key -> bool Lwt.t
    (** [memv t k] is false iff [getv k = `Empty]. *)

    val getv: tree -> key -> tree Lwt.t
    (** [getv t k] is [v] if [k] is associated to [v] in [t].  It is
        [`Empty] if [k] is not present in [t]. *)

    val addv: tree -> key -> tree -> tree Lwt.t
    (** [addv t k v] is [t] where the key [k] is bound to the tree
        [v]. *)

    val merge: tree Merge.t
    (** [merge] is the 3-way merge function for trees. *)

    (** {1 Concrete Trees} *)

    type concrete =
      [ `Empty
      | `Tree of (step * concrete) list
      | `Contents of contents * metadata ]
    (** The type for concrete trees. *)

    val of_concrete: concrete -> tree
    (** [of_concrete c] is the subtree equivalent to the concrete tree
        [c]. *)

    val to_concrete: tree -> concrete Lwt.t
    (** [to_concrete t] is the concrete tree equivalent to the subtree
        [t]. *)

  end

  (** {1 Reads} *)

  val kind: t -> key -> [`Contents | `Node | `Empty] Lwt.t
  (** [kind] is {!Tree.kind} applied to [t]'s root tree. *)

  val list: t -> key -> (step * [`Contents | `Node]) list Lwt.t
  (** [list t] is {!Tree.list} applied to [t]'s root tree. *)

  val mem: t -> key -> bool Lwt.t
  (** [mem t] is {!Tree.mem} applied to [t]'s root tree. *)

  val memv: t -> key -> bool Lwt.t
  (** [memv t] is {!Tree.memv} applied to [t]'s root tree. *)

  val findm: t -> key -> (contents * metadata) option Lwt.t
  (** [findm t] is {!Tree.findm} applied to [t]'s root tree. *)

  val find: t -> key -> contents option Lwt.t
  (** [find t] is {!Tree.find} applied to [t]'s root tree. *)

  val getm: t -> key -> (contents * metadata) Lwt.t
  (** [getm t] is {!Tree.getm} applied on [t]'s root tree. *)

  val get: t -> key -> contents Lwt.t
  (** [get t] is {!Tree.get} applied to [t]'s root tree. *)

  val getv: t -> key -> tree Lwt.t
  (** [getv t] is {!Tree.getv} applied to [t]'s root tree. *)

  (** {1 Writes} *)

  val setv: t -> task -> ?parents:commit list -> key -> tree -> unit Lwt.t
  (** [set t ta ?parents p v] {e replaces} the sub-tree under [p] in
      the branch [t] by the contents of the tree [v], using the task
      [ta]. If [parents] is not set, use [t]'s current head as
      parent. *)

  val set: t -> task -> ?parents:commit list -> key ->
    ?metadata:metadata -> contents -> unit Lwt.t
  (** Same as {!setv} but for contents. If [metadata] is not givent
      (default) pre-existing metadata is kept as is. If new metadata
      new to be created and [metadata] is not provided,
      {!Metadata.default} is used. *)

  val mergev: t -> task -> parents:commit list -> ?max_depth:int -> ?n:int ->
    key -> tree -> (unit, Merge.conflict) result Lwt.t
  (** [mergev t ta ~parents k v] {e merges} the tree [v] with the contents of
      the sub-tree under [p] in [t]. Merging means applying the 3-way
      merge between [v] and [t]'s sub-tree under [k]. Automatically
      adds the lca to [parents]. If [parents] is not set, use [t]'s
      and the [lca] heads. *)

  val remove: t -> task -> key -> unit Lwt.t
  (** Same as {!RW.remove} but create a commit with the given
      task. *)

  (** {1 Clones} *)

  val clone: src:t -> dst:branch -> t Lwt.t
  (** [clone ~src ~dst] makes [dst] points to [Head.get src]. [dst] is
      created if needed. Remove the current contents en [dst] if [src]
      is {!empty}. *)

  (** {1 Watches} *)

  type watch
  (** The type for store watches. *)

  val watch:
    t -> ?init:commit -> (commit diff -> unit Lwt.t) -> watch Lwt.t
  (** [watch t f] calls [f] every time the contents of [t]'s head is
      updated.

      {b Note:} even if [f] might skip some head updates, it will
      never be called concurrently: all consecutive calls to [f] are
      done in sequence, so we ensure that the previous one ended
      before calling the next one. *)

  val watch_key: t -> key -> ?init:commit ->
    ((commit * tree) diff -> unit Lwt.t) -> watch Lwt.t
  (** [watch_key t key f] calls [f] every time the [key]'s value is
      added, removed or updated. If the current branch is deleted,
      no signal is sent to the watcher. *)

  val unwatch: watch -> unit Lwt.t
  (** [unwatch w] disable [w]. Return once the [w] is fully
      disabled. *)

  (** {1 Merges and Common Ancestors.} *)

  val merge: into:t -> task -> ?max_depth:int -> ?n:int -> t ->
    (unit, Merge.conflict) result Lwt.t
  (** [merge ~into ta t] merges [t]'s current branch into [x]'s
      current branch using the task [ta]. After that operation, the
      two stores are still independent. Similar to [git merge
      <branch>]. *)

  val merge_with_branch: t -> task -> ?max_depth:int -> ?n:int -> branch ->
    (unit, Merge.conflict) result Lwt.t
  (** Same as {!merge} but with a branch ID. *)

  val merge_with_commit: t -> task -> ?max_depth:int -> ?n:int -> commit ->
    (unit, Merge.conflict) result Lwt.t
  (** Same as {!merge} but with a commit ID. *)

  val lcas: ?max_depth:int -> ?n:int -> t -> t ->
    [`Ok of commit list | `Max_depth_reached | `Too_many_lcas ] Lwt.t
  (** [lca ?max_depth ?n msg t1 t2] returns the collection of least
      common ancestors between the heads of [t1] and [t2] branches.

      {ul
      {- [max_depth] is the maximum depth of the exploration (default
      is [max_int]). Return [`Max_depth_reached] if this depth is
      exceeded.}
      {- [n] is the maximum expected number of lcas. Stop the
      exploration as soon as [n] lcas are found. Return
      [`Too_many_lcas] if more [lcas] are found. }
      }
  *)

  val lcas_with_branch: t -> ?max_depth:int -> ?n:int -> branch ->
    [`Ok of commit list | `Max_depth_reached | `Too_many_lcas] Lwt.t
  (** Same as {!lcas} but takes a branch ID as argument. *)

  val lcas_with_commit: t -> ?max_depth:int -> ?n:int -> commit ->
    [`Ok of commit list | `Max_depth_reached | `Too_many_lcas] Lwt.t
  (** Same as {!lcas} but takes a commit ID as argument. *)

  (** {1 History} *)

  module History: Graph.Sig.P with type V.t = commit
  (** An history is a DAG of heads. *)

  val history:
    ?depth:int -> ?min:commit list -> ?max:commit list -> t ->
    History.t Lwt.t
  (** [history ?depth ?min ?max t] is a view of the history of the
      store [t], of depth at most [depth], starting from the [max]
      (or from the [t]'s head if the list of heads is empty) and
      stopping at [min] if specified. *)

  (** Manipulate branches. *)
  module Branch: sig

    (** {1 Branch Store}

        Manipulate relations between {{!branch}branches} and
        {{!commit}commits}. *)

    val mem: Repo.t -> branch -> bool Lwt.t
    (** [mem r b] is true iff [b] is present in [r]. *)

    val find: Repo.t -> branch -> commit option Lwt.t
    (** [find r b] is [Some c] iff [c] is bound to [b] in [t]. It is
        [None] if [b] is not present in [t]. *)

    val get: Repo.t -> branch -> commit Lwt.t
    (** [get t b] is similar to {!find} but raise [Invalid_argument]
        if [b] is not present in [t]. *)

    val set: Repo.t -> branch -> commit -> unit Lwt.t
    (** [set t b c] bounds [c] to [b] in [t]. *)

    val remove: Repo.t -> branch -> unit Lwt.t
    (** [remove t b] removes [b] from [t]. *)

    val list: Repo.t -> branch list Lwt.t
    (** [list t] is the list of branches present in [t]. *)

    val watch:
      Repo.t -> branch -> ?init:commit -> (commit diff -> unit Lwt.t)
      -> watch Lwt.t
    (** [watch t b f] calls [f] on every change in [b]. *)

    (** [watch_all t f] calls [f] on every branch-related change in
        [t], including creation/deletion events. *)
    val watch_all:
      Repo.t ->
      ?init:(branch * commit) list -> (branch -> commit diff -> unit Lwt.t)
      -> watch Lwt.t

    include Branch.S with type t = branch
    (** Base functions for branches. *)

  end

  module Key: Path.S with type t = key and type step = step
  (** [Key] provides base functions for the stores's paths. *)

  module Status: Contents.Conv with
    type t = [ `Empty | `Branch of branch | `Commit of commit ]
  (** [Status] provides base functions for store statuses. *)

  module Contents: Contents.S with type t = contents
  (** [Contents] provides base functions for the store's contents. *)

  module Commit: Hash.S with type t = commit
  (** [Commit] provides base functions for commit identifiers. *)

  module Metadata: Metadata.S with type t = metadata
  (** [Metadata] provides base functions for node metadata. *)

  (** {1 Value Types} *)

  val step_t: step Type.t
  (** [step_t] is the value type for {!step}. *)

  val key_t: key Type.t
  (** [key_t] is the value type for {!key}. *)

  val metadata_t: metadata Type.t
  (** [metadata_t] is the value type for {!metadata}. *)

  val contents_t: contents Type.t
  (** [contents_t] is the value type for {!contents}. *)

  val node_t: node Type.t
  (** [node_t] is the value type for {!node}. *)

  val tree_t: tree Type.t
  (** [tree_t] is the value type for {!tree}. *)

  val commit_t: commit Type.t
  (** [commit_t] is the value type for {!commit}. *)

  val branch_t: branch Type.t
  (** [branch_t] is the value type for {!branch}. *)

  val slice_t: slice Type.t
  (** [slice_t] is the value type for {!slice}. *)

  val kind_t: [`Node | `Contents] Type.t
  (** [kind_t] is the value type for values returned by {!kind}. *)

  val kinde_t: [`Empty | `Node | `Contents] Type.t
  (** [kind_t] is like {!kind_t} but also allow [`Empty] values. *)

  val lca_t: [`Ok of commit list | `Max_depth_reached | `Too_many_lcas ] Type.t
  (** [lca_t] is the value type for {!lca} results. *)

  (** Private functions, which might be used by the backends. *)
  module Private: sig
    include Private.S
      with type Contents.value = contents
       and type Commit.key = commit
       and type Node.Metadata.t = metadata
       and module Node.Path = Key
       and type Branch.key = branch
       and type Slice.t = slice
       and type Repo.t = Repo.t

    (** {1 Store Nodes vs. Private Nodes}  *)

    val import_node: Repo.t -> Node.key -> node Lwt.t
    val export_node: Repo.t -> node -> Node.key Lwt.t
  end
end

(** [S_MAKER] is the signature exposed by any backend providing {!S}
    implementations. [C] is the implementation for user-defined
    contents, [B] is the implementation for branches and [H] is the
    implementation for object (blobs, trees, commits) hashes. It does
    not use any native synchronization primitives. *)
module type S_MAKER =
  functor (C: Contents.S) ->
  functor (P: Path.S) ->
  functor (B: Branch.S) ->
  functor (H: Hash.S) ->
    S with type key = P.t
       and type step = P.step
       and module Key = P
       and type contents = C.t
       and type branch = B.t
       and type commit = H.t

(** {2 Synchronization} *)

type remote
(** The type for remote stores. *)

val remote_uri: string -> remote
(** [remote_uri s] is the remote store located at [uri]. Use the
    optimized native synchronization protocol when available for the
    given backend. *)


(** {1:examples Examples}

    These examples are in the [examples] directory of the
    distribution.

    {3 Synchronization}

    A simple synchronization example, using the
    {{!Irmin_unix.Irmin_git}Git} backend and the {!Sync} helpers. The
    code clones a fresh repository if the repository does not exist
    locally, otherwise it performs a fetch: in this case, only
    the missing contents is downloaded.

{[
open Lwt
open Irmin_unix

module S = Irmin_git.FS(Irmin.Contents.String)(Irmin.Branch.String)(Irmin.Hash.SHA1)
module Sync = Irmin.Sync(S)
let config = Irmin_git.config ~root:"/tmp/test" ()

let upstream =
  if Array.length Sys.argv = 2 then (Irmin.remote_uri Sys.argv.(1))
  else (Printf.eprintf "Usage: sync [uri]\n%!"; exit 1)

let test () =
  S.Repo.v config
  >>= fun r  -> S.master r task
  >>= fun t  -> Sync.pull_exn (t "Syncing with upstream store") upstream `Update
  >>= fun () -> S.get t ["README.md"]
  >>= fun r  -> Printf.printf "%s\n%!" r; return_unit

let () =
  Lwt_main.run (test ())
]}

    {3 Mergeable logs}

    We will demonstrate the use of custom merge operators by
    defining mergeable debug log files. We first define a log entry
    as a pair of a timestamp and a message, using the combinator
    exposed by {{:https://github.com/mirage/mirage-tc}mirage-tc}:

{[
  module Entry = struct
    include Tc.Pair (Tc.Int)(Tc.String)
    let compare (x, _) (y, _) = Pervasives.compare x y
    let time = ref 0
    let v message = incr time; !time, message
  end
]}

    A log file is a list of entries (one per line), ordered by
    decreasing order of timestamps. The 3-way [merge] operator for log
    files concatenates and sorts the new entries and prepend them
    to the common ancestor's ones.

{[
  module Log: Irmin.Contents.S with type t = Entry.t list = struct
    module Path = Irmin.Path.String_list
    module S = Tc.List(Entry)
    include S

    (* Get the timestamp of the latest entry. *)
    let timestamp = function
      | [] -> 0
      | (timestamp, _ ) :: _ -> timestamp

    (* Compute the entries newer than the given timestamp. *)
    let newer_than timestamp entries =
      let rec aux acc = function
        | [] -> List.rev acc
        | (h, _) :: _ when h <= timestamp -> List.rev acc
        | h::t -> aux (h::acc) t
      in
      aux [] entries

    let merge_log _path ~old t1 t2 =
      let open Irmin.Merge.OP in
      old () >>| fun old ->
      let old = match old with None -> [] | Some o -> o in
      let ts = timestamp old in
      let t1 = newer_than ts t1 in
      let t2 = newer_than ts t2 in
      let t3 = List.sort Entry.compare (List.rev_append t1 t2) in
      ok (List.rev_append t3 old)

    let merge path = Irmin.Merge.option (module S) (merge_log path)

  end
]}

    {b Note:} The serialisation primitives provided by
    {{:https://github.com/mirage/mirage-tc}mirage-tc}: are not very
    efficient in this case as they parse the file every-time. For real
    usage, you would write buffered versions of [Log.read] and
    [Log.write].

    To persist the log file on disk, we need to choose a backend. We
    show here how to use the on-disk [Git] backend on Unix.

{[
  (* Bring [Irmin_unix.task] and [Irmin_unix.Irmin_git] in scope. *)
  open Irmin_unix

  (* Build an Irmin store containing log files. *)
  module S = Irmin_git.FS(Log)(Irmin.Branch.String)(Irmin.Hash.SHA1)

  (* Set-up the local configuration of the Git repository. *)
  let config = Irmin_git.config ~root:"/tmp/irmin/test" ~bare:true ()
]}

  We can now define a toy example to use our mergeable log files.

{[
  open Lwt

  (* Name of the log file. *)
  let file = [ "local"; "debug" ]

  (* Read the entire log file. *)
  let read_file t =
    S.find t file >>= function
    | None   -> return_nil
    | Some l -> return l

  (* Persist a new entry in the log. *)
  let log t fmt =
    Printf.ksprintf (fun message ->
        read_file t >>= fun logs ->
        let logs = Entry.v message :: logs in
        S.update (t "Adding a new entry") file logs
      ) fmt

  let () =
    Lwt_main.run begin
      S.Repo.v config
      >>= fun r -> S.master r task
      >>= fun t  -> log t "Adding a new log entry"
      >>= fun () -> Irmin.clone_force task (t "Cloning the store") "x"
      >>= fun x  -> log x "Adding new stuff to x"
      >>= fun () -> log x "Adding more stuff to x"
      >>= fun () -> log x "More. Stuff. To x."
      >>= fun () -> log t "I can add stuff on t also"
      >>= fun () -> log t "Yes. On t!"
      >>= fun () -> Irmin.merge_exn "Merging x into t" x ~into:t
      >>= fun () -> return_unit
    end
]}

*)

(** {1 Helpers} *)

val remote_store: (module S with type t = 'a) -> 'a -> remote
(** [remote_store t] is the remote corresponding to the local store
    [t]. Synchronization is done by importing and exporting store
    {{!BC.slice}slices}, so this is usually much slower than native
    synchronization using {!remote_uri} but it works for all
    backends. *)

(** [SYNC] provides functions to synchronization an Irmin store with
    local and remote Irmin stores. *)
module type SYNC = sig

  (** {1 Native Synchronization} *)

  type db
  (** Type type for store handles. *)

  type commit
  (** The type for store heads. *)

  val fetch:
    db -> ?depth:int -> remote -> [`Head of commit | `No_head | `Error] Lwt.t
  (** [fetch t ?depth r] populate the local store [t] with objects for
      the remote store [r], using [t]'s current branch. The [depth]
      parameter limits the history depth. Return [None] if either the
      local or remote store do not have a valid head. *)

  val fetch_exn: db -> ?depth:int -> remote -> commit Lwt.t
  (** Same as {!fetch} but raise [Invalid_argument] if either the
      local or remote store do not have a valid head. *)

  val pull: db -> ?depth:int -> remote -> [`Merge of task | `Update] ->
    ([`Ok | `No_head | `Error], Merge.conflict) result Lwt.t
  (** [pull t ?depth r s] is similar to {{!Sync.fetch}fetch} but it
      also updates [t]'s current branch. [s] is the update strategy:

      {ul
      {- [`Merge] uses {S.merge_head}. This strategy can return a conflict.}
      {- [`Update] uses {S.update_head.}}
      } *)

  val pull_exn: db -> ?depth:int -> remote -> [`Merge of task | `Update] ->
    unit Lwt.t
  (** Same as {!pull} but raise {!Merge.Conflict} in case of
      conflict. *)

  val push: db -> ?depth:int -> remote -> [`Ok | `Error] Lwt.t
  (** [push t ?depth r] populates the remote store [r] with objects
      from the current store [t], using [t]'s current branch. If [b]
      is [t]'s current branch, [push] also updates the head of [b] in
      [r] to be the same as in [t].

      {b Note:} {e Git} semantics is to update [b] only if the new
      head if more recent. This is not the case in {e Irmin}. *)

  val push_exn: db -> ?depth:int -> remote -> unit Lwt.t
  (** Same as {!push} but raise [Invalid_argument] if an error
      happens. *)

end

(** The default [Sync] implementation. *)
module Sync (S: S): SYNC with type db = S.t and type commit = S.commit

(** [Dot] provides functions to export a store to the Graphviz `dot`
    format. *)
module Dot (S: S): sig

  (** {1 Dot Export} *)

  val output_buffer:
    S.t -> ?html:bool -> ?depth:int -> ?full:bool -> date:(int64 -> string) ->
    Buffer.t -> unit Lwt.t
    (** [output_buffer t ?html ?depth ?full buf] outputs the Graphviz
        representation of [t] in the buffer [buf].

        [html] (default is false) enables HTML labels.

        [depth] is used to limit the depth of the commit history. [None]
        here means no limitation.

        If [full] is set (default is not) the full graph, including the
        commits, nodes and contents, is exported, otherwise it is the
        commit history graph only. *)

end

(** {1:backend Backends}

    API to create new Irmin backends. A backend is an implementation
    exposing either a concrete implementation of {!S} or a functor
    providing {!S} once applied.

    There are two ways to create a concrete {!Irmin.S} implementation:

    {ul
    {- {!Make} creates a store where all the objects are stored in the
    same store, using the same internal keys format and a custom binary
    format based on {{:https://github.com/janestreet/bin_prot}bin_prot},
    with no native synchronization primitives: it is usually what is
    needed to quickly create a new backend.}
    {- {!Make_with_metadata} is similar to {!Make} but allows to
    specify the kind of metadata stored in the nodes.}
    {- {!Make_ext} creates a store with a {e deep} embedding of each
    of the internal stores into separate store, with a total control over
    the binary format and using the native synchronization protocols
    when available. This is mainly used by the Git backend, but could
    be used for other similar backends as well in the future.}
    }
*)

(** [AO_MAKER] is the signature exposed by append-only store
    backends. [K] is the implementation of keys and [V] is the
    implementation of values. *)
module type AO_MAKER = functor (K: Hash.S) -> functor (V: Contents.Raw) -> sig

  include AO with type key = K.t and type value = V.t

  val v: config -> t Lwt.t
  (** [v config] is a function returning fresh store handles, with the
      configuration [config], which is provided by the backend. *)
end

(** [LINK_MAKER] is the signature exposed by store which enable adding
    relation between keys. This is used to decouple the way keys are
    manipulated by the Irmin runtime and the keys used for
    storage. This is useful when trying to optimize storage for
    random-access file operations or for encryption. *)
module type LINK_MAKER = functor (K: Hash.S) -> sig
  include LINK with type key = K.t and type value = K.t
  val v: config -> t Lwt.t
end

(** [RW_MAKER] is the signature exposed by read-write store
    backends. [K] is the implementation of keys and [V] is the
    implementation of values.*)
module type RW_MAKER =
  functor (K: Contents.Conv) -> functor (V: Contents.Conv) ->
sig

  include RW with type key = K.t and type value = V.t

  val v: config -> t Lwt.t
  (** [v config] is a function returning fresh store handles, with the
      configuration [config], which is provided by the backend. *)

end

module Make (AO: AO_MAKER) (RW: RW_MAKER): S_MAKER
(** Simple store creator. Use the same type of all of the internal
    keys and store all the values in the same store. *)

module Make_with_metadata (M: Metadata.S) (AO: AO_MAKER) (RW: RW_MAKER): S_MAKER
(** Similar to {!Make} but allows to specify the kind of metadata
    stored in the nodes. *)

(** Advanced store creator. *)
module Make_ext (P: Private.S): S
  with type key = P.Node.Path.t
   and type contents = P.Contents.value
   and type branch = P.Branch.key
   and type commit = P.Branch.value
   and type step = P.Node.Path.step
   and type metadata = P.Node.Val.metadata
   and type Key.step = P.Node.Path.step
   and type Repo.t = P.Repo.t
